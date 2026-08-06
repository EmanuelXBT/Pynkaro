# 🦊 Pynkaro - Umbrel & Mac via PrismML BonsAI

Assistente de voz local para macOS, 100% self-hosted. Fica ouvindo o microfone; ao ouvir **"Píncaro"**,ou a palavra que desejar, captura a pergunta, transcreve localmente, envia para um **LLM local** e fala a resposta com a voz do **Kokoro** — **sem nenhuma assinatura de API**.

Três modos de operação:

| Modo | LLM | TTS | Onde roda |
|---|---|---|---|
| **🍎 100% local no Mac** | Ollama no próprio Mac | Kokoro local (kokoro-onnx) | Tudo no MacBook |
| **🖥️ Umbrel** | Ollama na Umbrel | Kokoro-FastAPI na Umbrel | Mac + servidor na LAN |
| **☁️ API paga** | Anthropic (Claude) | ElevenLabs | Nuvem (requer chaves) |

> Fork de [ralbuque/Pynkaro](https://github.com/ralbuque/Pynkaro) com foco em quem roda um servidor [Umbrel](https://umbrel.com): a versão original usa a API paga da Anthropic (Claude) e ElevenLabs; esta versão substitui ambas por serviços locais — no seu servidor **ou** no próprio Mac. [Clique aqui](https://github.com/EmanuelXBT/hermes-agent-umbrel) para ser redirecionado a um tutorial de instalação do Umbrel junto ao Hermes Agent.

## ✨ Destaques

- **Wake word "Píncaro"** — detecção por transcrição contínua on-device (Speech framework da Apple)
- **Transcrição 100% local** — nenhum áudio sai do Mac
- **LLM local** — Ollama no Mac (`qwen2.5` ou **Bonsai-27B**) ou na Umbrel (`qwen2.5:3b`)
- **Voz local** — Kokoro TTS (pt-BR nativo, ~82M params, qualidade próxima de TTS pagos) no Mac ou na Umbrel
- **Instalação automática** — menu **"Instalar versão local"**: escolhe o modelo, o app instala tudo e reinicia configurado
- **Auto-cura do Kokoro** — no startup o app verifica se o servidor TTS está de pé; se não, reinicia o LaunchAgent sozinho antes de cair no fallback
- **Avatar animado** — janela flutuante com lip sync (por amplitude no modo local/Umbrel); o `avatar.png` também vira o **ícone do app** no `make_app.sh`
- **Privacidade** — o único tráfego de rede é dentro da sua LAN (Mac ↔ Umbrel) ou nenhum (modo Mac)

## 📋 Requisitos

- **MacBook:** macOS 13+ (Apple Silicon recomendado), Command Line Tools (`xcode-select --install`)
- Para transcrição 100% local: **Ajustes do Sistema → Teclado → Ditado → ative** e baixe o idioma **Português (Brasil)**
- **Modo Mac 100% local:** Homebrew + Python 3.10+ (`brew install python@3.12`)
- **Modo Umbrel:** Umbrel com os apps [**Ollama**](https://umbrel.com) e [**Kokoro**](https://umbrel.com) instalados

## 🚀 Instalação 100% local no Mac (novo)

Tudo roda no próprio MacBook — não depende da Umbrel. Latência de resposta ~2-5 s.

### Pré-requisitos

- macOS 13+, Apple Silicon (M1+) recomendado, Command Line Tools (`xcode-select --install`)
- **Homebrew** ([brew.sh](https://brew.sh))
- **Python 3.10+** (o Python do sistema é 3.9 — instale `brew install python@3.12`)

### Instalação automática (recomendada)

1. `git clone https://github.com/EmanuelXBT/Pynkaro && cd Pynkaro`
2. `swift run -c release` (ou `./make_app.sh` para o `.app` de menu bar)
3. Menu bar → **"Instalar versão local"** → escolha o modelo → **"Instalar e configurar"**
4. O app executa a sequência completa com log em tempo real (instala o Ollama se faltar, baixa o modelo, cria os venvs do Kokoro, registra os serviços) e **reinicia com a configuração aplicada**

### Opções de modelo

| Opção | RAM usada | RAM mínima do Mac | Instalação automática |
|---|---|---|---|
| `qwen2.5:3b` | ~2 GB | 4 GB | Ollama (`brew install --cask ollama` + pull) |
| `qwen2.5:7b` | ~6 GB | 8 GB | Ollama |
| `qwen2.5:14b` | ~11 GB | 16 GB | Ollama |
| **Bonsai-27B Q1_0** (27B em ~4 GB) | ~4-5 GB | 32 GB | Ollama |
| **Bonsai-27B 1-bit** | ~4-6 GB | 32 GB | MLX (`mlx_lm.server` via LaunchAgent) |
| **Bonsai-27B Ternary 2-bit** | ~8-9 GB | 32 GB | MLX |

> **Bonsai-27B** (prism-ml): modelo de pesos binários/ternários — um 27B que cabe em poucos GB, otimizado para Apple Silicon. O **Ternary 2-bit** mantém ~95% da qualidade FP16.
>
> **Bloqueio por hardware:** o instalador detecta a RAM do Mac e **oculta automaticamente** as opções incompatíveis (aviso laranja). Ex.: num Mac de 16 GB, os 27B não aparecem — 27B em 16 GB fica em swap e não responde na prática. O limite por opção está na coluna "RAM mínima do Mac".

### Como funciona por baixo

- **Serviços persistentes** via LaunchAgents em `~/Library/LaunchAgents/`:
  - `com.pynkaro.kokoro` → Kokoro local (`~/.pynkaro-tts/bin/python3 kokoro_local_server.py`, porta **8888**)
  - `com.pynkaro.mlx1` / `com.pynkaro.mlx2` → `mlx_lm.server` (porta **11435**)
- **Config**: o "Instalar e configurar" grava `~/.config/pynkaro/config.json` apontando para `localhost` (prioridade máxima de leitura)
- Para remover um serviço: `launchctl bootout gui/$(id -u)/com.pynkaro.kokoro`

### Instalação manual (equivalente)

```bash
# LLM
brew install --cask ollama
ollama pull qwen2.5:7b          # ou o modelo escolhido

# Voz Kokoro (Python 3.10+ obrigatório)
python3.12 -m venv ~/.pynkaro-tts
~/.pynkaro-tts/bin/pip install -U pip kokoro-onnx soundfile fastapi uvicorn numpy
~/.pynkaro-tts/bin/python3 tools/kokoro_local_server.py   # baixa o modelo na 1ª execução

# Config
cat > ~/.config/pynkaro/config.json << 'EOF'
{
  "mode": "mac",
  "ollama_url": "http://localhost:11434/v1",
  "kokoro_url": "http://localhost:8888",
  "llm_model": "qwen2.5:7b",
  "kokoro_voice": "pm_alex"
}
EOF
```

### Voltar ao modo Umbrel

Use **Configurações → Servidor local (Umbrel)** e salve — ou edite `~/.config/pynkaro/config.json` trocando `localhost` pelos endereços do servidor (ex.: `http://192.168.0.189:11434/v1`) e o `mode` para `"umbrel"`, e reinicie.

## 🚀 Modo Umbrel (servidor na LAN)

### 1. Clone

```bash
git clone https://github.com/EmanuelXBT/Pynkaro
cd Pynkaro
```

### 2. Configure (config.json)

Crie o arquivo `config.json` na raiz (é ignorado pelo git):

```bash
cat > config.json << 'EOF'
{
  "mode": "umbrel",
  "ollama_url": "http://umbrel.local:11434/v1",
  "kokoro_url": "http://umbrel.local:8880",
  "llm_model": "qwen2.5:3b",
  "kokoro_voice": "pm_alex"
}
EOF
```

> **Se `umbrel.local` não resolver no seu Mac**, use o IP do servidor (ex.: `http://192.168.0.189:11434/v1`).

### 3. Porta do Kokoro (uma única configuração manual)

O app Kokoro da Umbrel, por padrão, só é acessível pelo proxy autenticado. Para o Pynkaro acessá-lo direto pela LAN, exponha a porta **8880**:

1. Abra o **Files** da Umbrel → **Apps → Kokoro → docker-compose.yml**
2. No serviço `web`, adicione:
   ```yaml
   services:
     web:
       ports:
         - "8880:8880"
   ```
3. Salve, **Pare e inicie** o app Kokoro (não apenas Restart — Stop + Start recria o container com a porta)

### 4. Compile e rode

```bash
swift run -c release
```

Na primeira execução o macOS pede permissões de **Microfone** e **Reconhecimento de Fala** → **Permitir**.

## 🎤 Uso

1. Aguarde `👂 Aguardando "Píncaro"...`
2. Diga: **"Píncaro, que horas são?"** (ou diga só "Píncaro", aguarde o `🎤 Pode falar...` e pergunte)
3. Ele transcreve no Mac, envia o texto para o Ollama na Umbrel, e responde com a voz do Kokoro
4. O histórico da conversa é mantido durante a sessão

### Como o assistente responde

- **Idioma:** o modelo pode raciocinar em inglês internamente, mas **toda resposta é em português do Brasil** — sem misturar outros idiomas, exceto palavras-<empréstimo</em> sem tradução natural (`software`, `cache`, `feedback`...)
- **Tom:** claro, direto e profissional; humor **opcional e sutil** — só aparece se a pergunta for claramente descontraída
- **Tamanho:** uma única frase, no máximo ~40 palavras — **exceto** quando a pergunta pede explicitamente comparação/listagem/explicação ("principais diferenças", "compare", "liste"...), caso em que a resposta pode ter até ~150 palavras
- **Resposta ampla na tela:** respostas longas (>45 palavras) abrem a **janela de leitura** (canto superior direito, redimensionável) com o texto completo — o usuário lê enquanto ouve
- **Cancelar por voz:** durante a fala, diga **"esquece"** (ou "cancela") para interromper a resposta imediatamente
- **Anti-alucinação:** o modelo **não inventa** produtos, serviços ou fatos. Se a pergunta parecer erro de transcrição (ex.: "PlayStation BR dois" em vez de "PlayStation VR2"), ele responde que não tem certeza e pede para reformular — "não sei" é melhor que inventar
- O comportamento é definido pelo **system prompt** no `ClaudeClient.swift` (recomputado a cada pergunta com a data/hora)

## 🍎 App de menu bar (sem terminal)

```bash
./make_app.sh          # gera Pynkaro.app e Pynkaro.dmg
```

O app vive na menu bar (sem ícone no Dock). O `make_app.sh` também:
- **Gera o ícone do app** (`AppIcon.icns`) a partir do `avatar.png` automaticamente (sips + iconutil, 16px a 1024px retina) e o registra no Info.plist — o avatar vira o ícone do Finder/Dock
- Copia os recursos do avatar (`avatar_mid.png`, `avatar_open.png`, etc.) e o `tools/kokoro_local_server.py` para dentro do bundle

Rodando como `.app`, o `config.json` é lido de `~/.config/pynkaro/config.json` — copie o arquivo para lá:

```bash
mkdir -p ~/.config/pynkaro
cp config.json ~/.config/pynkaro/config.json
```

> **Gatekeeper:** com assinatura ad-hoc, o app só roda sem bloqueio no Mac em que foi compilado. Para outros Macs, seria preciso Developer ID + notarização (conta Apple Developer, US$ 99/ano).

## ⚙️ Configuração

### config.json (recomendado — vale em qualquer contexto)

| Campo | Descrição |
|---|---|
| `mode` | Modo explícito: `"mac"` \| `"umbrel"` \| `"api"` — gravação automática pelas Configurações; sem o campo, o app infere pela URL (localhost → mac, IP LAN → umbrel, ausente → api) |
| `ollama_url` | Base URL do Ollama (ex.: `http://umbrel.local:11434/v1`) — **ativa o modo local/Umbrel** |
| `kokoro_url` | Base URL do Kokoro TTS (ex.: `http://umbrel.local:8880`) |
| `llm_model` | Modelo do Ollama (padrão: `qwen2.5:7b`) |
| `kokoro_voice` | Voz pt-BR do Kokoro (padrão: `pm_alex`) |
| `searxng_url` | Base URL do SearXNG (ex.: `http://umbrel.local:8080`) — **habilita busca na web no modo Umbrel** |
| `wake_words` | Lista de wake words (ex.: `["pincaro", "jupiter"]`) — todas ativam o assistente |
| `anthropic_api_key` | *(opcional)* chave da Anthropic — só para o modo nuvem |
| `elevenlabs_api_key` | *(opcional)* chave da ElevenLabs — só para o modo nuvem |

### Variáveis de ambiente (alternativa, têm prioridade)

| Variável | Padrão | Descrição |
|---|---|---|
| `PYNKARO_LLM_BASE_URL` | *(vazio)* | Base URL do Ollama (equivale a `ollama_url`) |
| `PYNKARO_LLM_MODEL` | `qwen2.5:7b` | Modelo do Ollama |
| `PYNKARO_KOKORO_URL` | *(vazio)* | Base URL do Kokoro (equivale a `kokoro_url`) |
| `PYNKARO_KOKORO_VOICE` | `pm_alex` | Voz pt-BR do Kokoro |
| `PYNKARO_KOKORO_MODEL` | `kokoro` | Modelo do Kokoro-FastAPI |
| `PYNKARO_SEARXNG_URL` | *(vazio)* | Base URL do SearXNG (equivale a `searxng_url`) |
| `PYNKARO_MODEL` | `claude-sonnet-5` | Modelo da Anthropic (modo nuvem) |
| `PYNKARO_VOICE` | melhor voz masculina pt-BR | Voz do sistema (fallback) |
| `PYNKARO_WAKE_WORD` | `pincaro` | Wake word (acentos/maiúsculas ignorados) |
| `PYNKARO_WEB_SEARCH` | `1` | Busca na web (só funciona no modo nuvem Anthropic) |

### Como funciona a escolha de serviços

| Serviço | Prioridade | Fallback |
|---|---|---|
| **LLM** | Ollama (se `ollama_url`/`PYNKARO_LLM_BASE_URL`) → Anthropic | — |
| **Voz** | Kokoro (se `kokoro_url`/`PYNKARO_KOKORO_URL`) → ElevenLabs → voz do sistema | — |

- **Modo local (Mac)** = `mode: "mac"` (ou URL `localhost`) → LLM e Kokoro rodam no próprio Mac, sem chaves
- **Modo Umbrel ativo** = `mode: "umbrel"` (ou URL de IP LAN) → o onboarding de chaves é pulado, nenhuma chave paga é necessária
- **Modo API** = `mode: "api"` (ou sem `ollama_url`) → Anthropic + ElevenLabs
- Sem `kokoro_url` e sem chave ElevenLabs → voz do sistema do Mac (gratuita)

> **Configurações:** janela com 3 abas (**Servidor local (Mac) / Servidor local (Umbrel) / API paga**). O campo `mode` é sempre gravado, então a aba correta abre sozinha — um config local do Mac não aparece mais na aba Umbrel. Salvar reinicia o app (o `Config.shared` é estático).
>
> **Prioridade de leitura do config:** `~/.config/pynkaro/config.json` (onde o `.app` e o "Instalar versão local" gravam) **vence** o `config.json` da raiz do projeto. Se o app parecer usar o modo errado, confira qual arquivo está sendo lido no log (`🔑 Configuração carregada de ...`).

## 🖼️ Avatar na tela

Salve a imagem do assistente como `avatar.png` na raiz do projeto (ou `~/.config/pynkaro/avatar.png`) — PNG com fundo transparente fica melhor. O avatar aparece com fade no canto inferior direito quando a wake word é detectada e some quando a resposta termina.

**Boca animada:** no modo Umbrel, o lip sync usa a **amplitude do áudio** (sem timestamps de caractere como a ElevenLabs). Sprites opcionais: `avatar_mid.png` (entreaberta) e `avatar_open.png` (aberta); `avatar_round.png` (o/u) e `avatar_fv.png` (f/v) opcionais. Sem sprites, o avatar fica estático.

**Rig 2D (Rive):** se existir `avatar.riv`, é usado no lugar dos PNGs (boca via input numérico `mouth` 0–4 do state machine). Veja o contrato completo no `CLAUDE.md`.

## 🔍 Troubleshooting

| Problema | Solução |
|---|---|
| Pediu chave da Anthropic | O `ollama_url` não está no `config.json` (ou não foi lido — confirme com `cat config.json`) |
| **"Falha ao instalar Kokoro (exit 1)"** | Python do sistema é 3.9 — instale `brew install python@3.12` e remova os venvs antigos (`rm -rf ~/.pynkaro-tts ~/.pynkaro-mlx`); rode "Instalar e configurar" de novo |
| **Kokoro "Could not connect" no modo Mac** | O venv `~/.pynkaro-tts` pode estar com Python 3.9 ou sem numpy — o instalador agora detecta e recria sozinho; verifique `tail ~/.pynkaro-tts/server.log` |
| **"Falha ao registrar o LaunchAgent"** | O agente já estava carregado — o app agora faz retry + kickstart; manual: `launchctl bootout gui/$(id -u)/com.pynkaro.kokoro; sleep 0.5; launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.pynkaro.kokoro.plist; launchctl kickstart -k gui/$(id -u)/com.pynkaro.kokoro` |
| **Config do Mac aparece na aba Umbrel** | O campo `mode` do config.json decide a aba; reabra as Configurações depois de salvar (ou reinicie o app) |
| **App fala "rodando no Umbrel" no modo Mac** | `~/.config/pynkaro/config.json` tem prioridade — confira o log `🔑 Configuração carregada de ...` e o conteúdo do arquivo |
| Kokoro não responde | Confirme a porta exposta: `curl -X POST http://IP:8880/v1/audio/speech -H "Content-Type: application/json" -d '{"model":"kokoro","input":"teste","voice":"pm_alex"}'` |
| **Bonsai-27B demora muito (modo Mac)** | GGUF Q1_0 roda na CPU — use `qwen2.5:7b` para uso diário ou a variante MLX do 27B ("Instalar versão local" → Bonsai-27B 1-bit/Ternary via MLX) |
| **Modelo 27B não aparece no instalador** | Não é bug: o bloqueio por RAM ocultou a opção (27B exige 32 GB). Use qwen 3b/7b/14b conforme a RAM do Mac |
| **Resposta errada em andamento** | Diga **"esquece"** (ou "cancela") durante a fala — o assistente interrompe na hora e volta a aguardar |
| **Modelo inventa produto/serviço inexistente** | Reforce pedindo para reformular; o prompt tem regra anti-alucinação — "PlayStation BR dois" (erro de transcrição de "VR2") deve gerar pedido de confirmação |
| **`ollama rm` "model not found"** | Copie o nome exato do `ollama list` — um ponto extra no final (`Q1_0.`) faz o comando falhar |
| Ollama lento | Use modelo menor (`qwen2.5:3b` em vez de `7b`); o timeout do Ollama é 240 s (120 s era insuficiente para a 1ª carga de modelos grandes) |
| Wake word não detectada | Ajuste do ditado pt-BR; teste `PYNKARO_WAKE_WORD` |
| Erro de build (Rive/XCFramework) | `swift package reset && rm -rf ~/Library/Caches/org.swift.swiftpm .build && swift package resolve && swift build` |
| Voz estranha | Troque `kokoro_voice` (listar vozes: `curl http://IP:8880/v1/audio/voices`) |

## 🏗️ Arquitetura

```
PynkaroApp.swift        → entrada do app (menu bar SwiftUI, onboarding, configurações)
VoiceAssistant.swift    → máquina de estados (aguardando → capturando → pensando → falando)
SpeechRecognizer.swift  → AVAudioEngine + SFSpeechRecognizer (pt-BR, on-device)
ClaudeClient.swift      → LLM: Ollama (/v1/chat/completions) ou Anthropic (Messages API)
KokoroSpeaker.swift     → TTS via Kokoro (/v1/audio/speech) — Umbrel ou local :8888
ElevenLabsSpeaker.swift → TTS nuvem (modo alternativo, com timestamps p/ lip sync)
Speaker.swift           → AVSpeechSynthesizer (voz do sistema, fallback)
AvatarWindow.swift      → janela flutuante com avatar (sprites PNG ou rig Rive)
AnswerWindow.swift      → janela de leitura p/ respostas amplas (>45 palavras)
Config.swift            → config.json (~/.config tem prioridade) + env vars + Keychain
SetupView.swift         → janela "Instalar versão local" (opções + log streaming)
SetupOrchestrator.swift → máquina de estados da instalação (idempotente)
CommandRunner.swift     → executor de comandos com saída linha a linha
ServiceManager.swift    → LaunchAgents p/ Kokoro/MLX (launchctl bootstrap)
tools/kokoro_local_server.py → servidor TTS local (kokoro-onnx, OpenAI-compatível)
```

Detalhes: a sessão de reconhecimento é reiniciada a cada 45 s (limite do SFSpeechRecognizer); o fim da pergunta é detectado por silêncio (1,8 s); a escuta é pausada enquanto o assistente fala.

## 📜 Licença e créditos

- Projeto original: [ralbuque/Pynkaro](https://github.com/ralbuque/Pynkaro)
- TTS: [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) via [Kokoro-FastAPI](https://github.com/remsky/Kokoro-FastAPI)
- LLM: [Ollama](https://ollama.com) com modelos Qwen 2.5
