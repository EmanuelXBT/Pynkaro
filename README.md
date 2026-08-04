# 🦊 Pynkaro — Umbrel Edition

Assistente de voz local para macOS, 100% self-hosted. Fica ouvindo o microfone; ao ouvir **"Píncaro"**, captura a pergunta, transcreve localmente, envia para o **Ollama** rodando na sua Umbrel e fala a resposta com a voz do **Kokoro** — **sem nenhuma assinatura de API**.

> Fork de [ralbuque/Pynkaro](https://github.com/ralbuque/Pynkaro) com foco em quem roda um servidor [Umbrel](https://umbrel.com): a versão original usa a API paga da Anthropic (Claude) e ElevenLabs; esta versão substitui ambas por serviços locais do seu servidor. [Clique aqui](https://github.com/EmanuelXBT/hermes-agent-umbrel) para ser redirecionado a um tutorial de instalação do Umbrel junto ao Hermes Agent.

## ✨ Destaques

- **Wake word "Píncaro"** — detecção por transcrição contínua on-device (Speech framework da Apple)
- **Transcrição 100% local** — nenhum áudio sai do Mac
- **LLM local** — Ollama na Umbrel (`qwen2.5:3b` ou o modelo que você quiser)
- **Voz local** — Kokoro TTS na Umbrel (pt-BR nativo, ~82M params, qualidade próxima de TTS pagos)
- **Avatar animado** — janela flutuante com lip sync (por amplitude no modo Umbrel)
- **Privacidade** — o único tráfego de rede é **dentro da sua LAN** (Mac ↔ Umbrel)

## 📋 Requisitos

- **MacBook:** macOS 13+ (Apple Silicon recomendado), Command Line Tools (`xcode-select --install`)
- **Umbrel** com os apps instalados:
  - [**Ollama**](https://umbrel.com) — app oficial da Umbrel (LLM)
  - [**Kokoro**](https://umbrel.com) — app oficial da Umbrel (TTS)
- Para transcrição 100% local: **Ajustes do Sistema → Teclado → Ditado → ative** e baixe o idioma **Português (Brasil)**

## 🚀 Instalação (modo Umbrel — recomendado)

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

## 🍎 App de menu bar (sem terminal)

```bash
./make_app.sh          # gera Pynkaro.app e Pynkaro.dmg
```

O app vive na menu bar (sem ícone no Dock). Rodando como `.app`, o `config.json` é lido de `~/.config/pynkaro/config.json` — copie o arquivo para lá:

```bash
mkdir -p ~/.config/pynkaro
cp config.json ~/.config/pynkaro/config.json
```

> **Gatekeeper:** com assinatura ad-hoc, o app só roda sem bloqueio no Mac em que foi compilado. Para outros Macs, seria preciso Developer ID + notarização (conta Apple Developer, US$ 99/ano).

## ⚙️ Configuração

### config.json (recomendado — vale em qualquer contexto)

| Campo | Descrição |
|---|---|
| `ollama_url` | Base URL do Ollama (ex.: `http://umbrel.local:11434/v1`) — **ativa o modo Umbrel** |
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

- **Modo Umbrel ativo** = `ollama_url` definido → o onboarding de chaves é pulado, nenhuma chave paga é necessária
- Sem `kokoro_url` e sem chave ElevenLabs → voz do sistema do Mac (gratuita)

## 🖼️ Avatar na tela

Salve a imagem do assistente como `avatar.png` na raiz do projeto (ou `~/.config/pynkaro/avatar.png`) — PNG com fundo transparente fica melhor. O avatar aparece com fade no canto inferior direito quando a wake word é detectada e some quando a resposta termina.

**Boca animada:** no modo Umbrel, o lip sync usa a **amplitude do áudio** (sem timestamps de caractere como a ElevenLabs). Sprites opcionais: `avatar_mid.png` (entreaberta) e `avatar_open.png` (aberta); `avatar_round.png` (o/u) e `avatar_fv.png` (f/v) opcionais. Sem sprites, o avatar fica estático.

**Rig 2D (Rive):** se existir `avatar.riv`, é usado no lugar dos PNGs (boca via input numérico `mouth` 0–4 do state machine). Veja o contrato completo no `CLAUDE.md`.

## 🔍 Troubleshooting

| Problema | Solução |
|---|---|
| Pediu chave da Anthropic | O `ollama_url` não está no `config.json` (ou não foi lido — confirme com `cat config.json`) |
| Kokoro não responde | Confirme a porta exposta: `curl -X POST http://IP:8880/v1/audio/speech -H "Content-Type: application/json" -d '{"model":"kokoro","input":"teste","voice":"pm_alex"}'` |
| Ollama lento | Use modelo menor (`qwen2.5:3b` em vez de `7b`); o timeout do Ollama é 120 s |
| Wake word não detectada | Ajuste do ditado pt-BR; teste `PYNKARO_WAKE_WORD` |
| Erro de build (Rive/XCFramework) | `swift package reset && rm -rf ~/Library/Caches/org.swift.swiftpm .build && swift package resolve && swift build` |
| Voz estranha | Troque `kokoro_voice` (listar vozes: `curl http://IP:8880/v1/audio/voices`) |

## 🏗️ Arquitetura

```
PynkaroApp.swift        → entrada do app (menu bar SwiftUI, onboarding, configurações)
VoiceAssistant.swift    → máquina de estados (aguardando → capturando → pensando → falando)
SpeechRecognizer.swift  → AVAudioEngine + SFSpeechRecognizer (pt-BR, on-device)
ClaudeClient.swift      → LLM: Ollama (/v1/chat/completions) ou Anthropic (Messages API)
KokoroSpeaker.swift     → TTS via Kokoro-FastAPI na Umbrel (/v1/audio/speech)
ElevenLabsSpeaker.swift → TTS nuvem (modo alternativo, com timestamps p/ lip sync)
Speaker.swift           → AVSpeechSynthesizer (voz do sistema, fallback)
AvatarWindow.swift      → janela flutuante com avatar (sprites PNG ou rig Rive)
Config.swift            → config.json + env vars + Keychain
```

Detalhes: a sessão de reconhecimento é reiniciada a cada 45 s (limite do SFSpeechRecognizer); o fim da pergunta é detectado por silêncio (1,8 s); a escuta é pausada enquanto o assistente fala.

## 📜 Licença e créditos

- Projeto original: [ralbuque/Pynkaro](https://github.com/ralbuque/Pynkaro)
- TTS: [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) via [Kokoro-FastAPI](https://github.com/remsky/Kokoro-FastAPI)
- LLM: [Ollama](https://ollama.com) com modelos Qwen 2.5
