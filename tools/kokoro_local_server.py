#!/usr/bin/env python3
"""
Pynkaro — servidor TTS Kokoro local (macOS).

Expõe um endpoint OpenAI-compatível /v1/audio/speech usando kokoro-onnx,
o mesmo protocolo que o Kokoro-FastAPI do Umbrel. O Pynkaro aponta
kokoro_url para http://localhost:8888 e funciona sem mudanças no app.

Uso:
    python3 kokoro_local_server.py            # usa venv ~/.pynkaro-tts (cria se faltar)
    python3 kokoro_local_server.py --port 8888

Instalação (uma vez):
    python3 -m venv ~/.pynkaro-tts
    ~/.pynkaro-tts/bin/pip install -U kokoro-onnx soundfile fastapi uvicorn numpy

Os modelos (kokoro-v1.0.onnx + voices-v1.0.bin, ~300 MB) são baixados
automaticamente para ~/.pynkaro-tts/models/ na primeira execução.
"""
import argparse
import hashlib
import io
import os
import sys
import urllib.request
import wave
from pathlib import Path

import numpy as np
from fastapi import FastAPI
from fastapi.responses import Response
from pydantic import BaseModel
import uvicorn

MODEL_VERSION = "v1.0"
MODEL_URL = ("https://github.com/thewh1teagle/kokoro-onnx/releases/download/"
             f"model-files-{MODEL_VERSION}/kokoro-{MODEL_VERSION}.onnx")
VOICES_URL = ("https://github.com/thewh1teagle/kokoro-onnx/releases/download/"
              f"model-files-{MODEL_VERSION}/voices-{MODEL_VERSION}.bin")

# SHA-256 esperados dos arquivos de modelo (pin do release model-files-v1.0).
# Garantem que um download corrompido ou um release comprometido não seja
# carregado. Para atualizar o release, baixe os arquivos e rode:
#   sha256sum kokoro-<VERSAO>.onnx voices-<VERSAO>.bin
MODEL_SHA256 = "7d5df8ecf7d4b1878015a32686053fd0eebe2bc377234608764cc0ef3636a6c5"
VOICES_SHA256 = "bca610b8308e8d99f32e6fe4197e7ec01679264efed0cac9140fe9c29f1fbf7d"

DEFAULT_PORT = 8888
DEFAULT_VOICE = "pm_alex"


def sha256(path: Path) -> str:
    """SHA-256 de um arquivo, em chunks (memória constante)."""
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def ensure_model_dir() -> Path:
    """Diretório dos modelos dentro do venv (~/.pynkaro-tts/models)."""
    venv = Path.home() / ".pynkaro-tts"
    model_dir = venv / "models"
    model_dir.mkdir(parents=True, exist_ok=True)
    return model_dir


def verify_or_download(url: str, dest: Path, expected_sha256: str) -> None:
    """Baixa (se faltar) e valida o SHA-256 do arquivo de modelo.

    Arquivos existentes também são validados — um arquivo corrompido no
    disco (ex.: download interrompido antes do rename) é detectado e
    baixado de novo. Em caso de divergência de hash o arquivo é removido
    e o processo aborta com erro claro (nunca carrega modelo não verificado).
    """
    if dest.exists() and dest.stat().st_size > 0:
        if sha256(dest) == expected_sha256:
            print(f"✅ {dest.name} verificado (SHA-256 ok).")
            return
        print(f"⚠️ {dest.name} com SHA-256 divergente. Baixando novamente...")
        dest.unlink()

    print(f"⬇️  Baixando {dest.name} (~{dest.name.startswith('kokoro') and '300 MB' or '28 MB'})...")
    tmp = dest.with_suffix(dest.suffix + ".part")
    req = urllib.request.Request(url, headers={"User-Agent": "Pynkaro/1.0"})
    with urllib.request.urlopen(req) as resp, open(tmp, "wb") as out:
        total = int(resp.headers.get("Content-Length", 0))
        done = 0
        while True:
            chunk = resp.read(1024 * 256)
            if not chunk:
                break
            out.write(chunk)
            done += len(chunk)
            if total:
                pct = done * 100 // total
                print(f"\r   {pct:3d}% ({done // (1024 * 1024)} MB)", end="", flush=True)
    print()
    tmp.rename(dest)

    actual = sha256(dest)
    if actual != expected_sha256:
        dest.unlink()
        raise RuntimeError(
            f"Falha de integridade em {dest.name}: SHA-256 {actual} != esperado "
            f"{expected_sha256}. O download pode ter sido corrompido ou o release "
            f"mudou; verifique a conexão e tente novamente."
        )
    print(f"✅ {dest.name} verificado (SHA-256 ok).")


def load_kokoro():
    from kokoro_onnx import Kokoro  # import tardio: falha amigável se não instalado

    model_dir = ensure_model_dir()
    model_path = model_dir / f"kokoro-{MODEL_VERSION}.onnx"
    voices_path = model_dir / f"voices-{MODEL_VERSION}.bin"
    verify_or_download(MODEL_URL, model_path, MODEL_SHA256)
    verify_or_download(VOICES_URL, voices_path, VOICES_SHA256)
    print("🧠 Carregando Kokoro (pode levar alguns segundos na 1ª vez)...")
    return Kokoro(str(model_path), str(voices_path))


kokoro = None
app = FastAPI(title="Pynkaro Kokoro local", version="1.0")


class SpeechRequest(BaseModel):
    model: str = "kokoro"
    input: str
    voice: str = DEFAULT_VOICE
    response_format: str = "wav"  # aceito; sempre devolvemos wav


@app.get("/v1/models")
def models():
    return {"object": "list", "data": [{"id": "kokoro", "object": "model"}]}


@app.get("/v1/audio/voices")
def voices():
    """Catálogo de vozes (OpenAI-compatível, mesmo formato do Kokoro-FastAPI).

    O app Pynkaro chama GET /v1/audio/voices para popular o picker de vozes
    (agrupadas por idioma, pt-BR primeiro). Sem este endpoint o picker cai
    no fallback de TextField.
    """
    if kokoro is None:
        return Response(content="Kokoro não carregado", status_code=503)
    ids = kokoro.get_voices()
    return {"voices": [{"id": v, "name": v} for v in ids]}


@app.post("/v1/audio/speech")
def speech(req: SpeechRequest):
    if kokoro is None:
        return Response(content="Kokoro não carregado", status_code=503)
    # Vozes "p*" (pf_/pm_) são português do Brasil; demais, inglês.
    lang = "pt-br" if req.voice.startswith("p") else "en-us"
    samples, sample_rate = kokoro.create(req.input, voice=req.voice, speed=1.0, lang=lang)

    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(int(sample_rate))
        w.writeframes((samples * 32767).astype(np.int16).tobytes())
    return Response(content=buf.getvalue(), media_type="audio/wav")


def main() -> None:
    parser = argparse.ArgumentParser(description="Pynkaro Kokoro TTS local (OpenAI-compatível)")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    args = parser.parse_args()

    global kokoro
    try:
        kokoro = load_kokoro()
    except ImportError:
        print("❌ kokoro-onnx não instalado. Rode:")
        print("   python3 -m venv ~/.pynkaro-tts && ~/.pynkaro-tts/bin/pip install -U kokoro-onnx soundfile fastapi uvicorn numpy")
        sys.exit(1)

    print(f"🗣️  Kokoro local no ar: http://localhost:{args.port}/v1/audio/speech")
    print("   Configure o Pynkaro com kokoro_url = http://localhost:8888")
    uvicorn.run(app, host="127.0.0.1", port=args.port, log_level="warning")


if __name__ == "__main__":
    main()
