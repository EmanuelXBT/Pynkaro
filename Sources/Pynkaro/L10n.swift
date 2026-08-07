import Foundation

/// Localização inline do Pynkaro. Resolve strings conforme o idioma do sistema
/// (Locale.current.languageCode). Strings não traduzidas caem em português.
///
/// Uso: `L10n.listening` → "Ouvindo…" (pt) / "Listening…" (en).
enum L10n {

    /// Idioma ativo: "pt" = português, "en" = inglês, "system" = detecta do OS.
    /// Controlado por Config.uiLanguage (env/config.json) com fallback "system".
    private static var activeLanguage: String {
        let configured = Config.uiLanguage
        if configured == "pt" || configured == "en" { return configured }
        // "system" ou valor inválido: detecta do sistema
        let system = Locale.current.language.languageCode?.identifier ?? "pt"
        return system.hasPrefix("pt") ? "pt" : "en"
    }

    /// Retorna a string em português ou inglês conforme o idioma do sistema.
    /// Idiomas além de pt/en caem em português.
    private static func loc(_ pt: String, _ en: String) -> String {
        activeLanguage.hasPrefix("pt") ? pt : en
    }

    // MARK: - Status (menu bar + AssistantController)

    static let starting         = loc("Aguardando configuração…",       "Waiting for setup…")
    static let waiting          = loc("Aguardando \"Píncaro\"",         "Waiting for \"Píncaro\"")
    static let listening        = loc("Ouvindo…",                       "Listening…")
    static let thinking         = loc("Pensando…",                      "Thinking…")
    static let speaking         = loc("Falando…",                       "Speaking…")
    static let paused           = loc("Escuta pausada",                 "Listening paused")
    static let pauseListening   = loc("Pausar escuta",                  "Pause listening")
    static let resumeListening  = loc("Retomar escuta",                 "Resume listening")
    static let recentErrors     = loc("⚠️ Erros recentes — veja Logs", "⚠️ Recent errors — see Logs")

    // MARK: - Menu bar

    static let installLocal     = loc("Instalar versão local",          "Install local version")
    static let avatarScreen     = loc("Tela do avatar",                 "Avatar screen")
    static let settingsMenu     = loc("Configurações…",                 "Settings…")
    static let quitApp          = loc("Sair do Pynkaro",                "Quit Pynkaro")

    // MARK: - Legendas do avatar (VoiceAssistant)

    static let youPrefix        = loc("Você: ",                         "You: ")

    // MARK: - Configurações

    static let welcomeTitle     = loc("Bem-vindo ao Pynkaro! 🦊",      "Welcome to Pynkaro! 🦊")
    static let welcomeBody      = loc("Configure como o Pynkaro deve funcionar. As chaves de API ficam no Keychain do seu Mac e nunca saem dele.",
                                       "Configure how Pynkaro should work. API keys stay in your Mac's Keychain and never leave it.")
    static let settingsTitle    = loc("Configurações do Pynkaro",       "Pynkaro Settings")
    static let operationMode    = loc("Modo de operação",               "Operation mode")
    static let logsButton       = loc("Logs",                           "Logs")
    static let modeMac          = loc("Mac",                            "Mac")
    static let modeUmbrel       = loc("Umbrel",                         "Umbrel")
    static let modeApi          = loc("API paga",                       "Paid API")
    static let modeMacDesc      = loc("LLM (Ollama) e voz (Kokoro) rodam 100% no seu Mac. Nenhuma chave é necessária.",
                                       "LLM (Ollama) and voice (Kokoro) run 100% on your Mac. No API keys needed.")
    static let modeUmbrelDesc   = loc("LLM e voz rodam na sua Umbrel (Ollama, Kokoro, SearXNG). Nenhuma chave é necessária.",
                                       "LLM and voice run on your Umbrel (Ollama, Kokoro, SearXNG). No API keys needed.")
    static let modeApiDesc      = loc("LLM via Anthropic e voz via ElevenLabs. Requer chaves de API.",
                                       "LLM via Anthropic and voice via ElevenLabs. Requires API keys.")
    static let serverMac        = loc("Servidor local (Mac)",           "Local server (Mac)")
    static let serverUmbrel     = loc("Servidor local (Umbrel)",        "Local server (Umbrel)")
    static let ollamaUrlLabel   = loc("Ollama URL",                     "Ollama URL")
    static let kokoroUrlLabel   = loc("Kokoro URL",                     "Kokoro URL")
    static let searxngUrlLabel  = loc("SearXNG URL",                    "SearXNG URL")
    static let modelLabel       = loc("Modelo",                         "Model")
    static let modelCustom      = loc("Personalizado: ",                "Custom: ")
    static let voiceLabel       = loc("Voz",                            "Voice")
    static let voiceSystem      = loc("Voz do sistema (Mac)",           "System voice (Mac)")
    static let voiceCustom      = loc("Personalizado: ",                "Custom: ")
    static let voiceShowAll     = loc("Mostrar todas as vozes",         "Show all voices")
    static let wakeWordsLabel   = loc("Wake words (separadas por vírgula)", "Wake words (comma separated)")
    static let micLanguageLabel = loc("Idioma do microfone",            "Microphone language")
    static let uiLanguageLabel  = loc("Idioma da interface",            "Interface language")
    static let uiLangSystem     = loc("Sistema",                        "System")
    static let uiLangPT         = loc("Português (BR)",                 "Portuguese (BR)")
    static let uiLangEN         = loc("Inglês",                         "English")
    static let micDownloadWarn  = loc("⚠️ Este idioma requer download do pacote de voz em Ajustes do Sistema > Teclado > Ditado.",
                                       "⚠️ This language requires downloading the speech pack in System Settings > Keyboard > Dictation.")
    static let anthropicLabel   = loc("Chave da Anthropic (obrigatória)", "Anthropic key (required)")
    static let elevenLabsLabel  = loc("Chave da ElevenLabs (opcional)",   "ElevenLabs key (optional)")
    static let elevenLabsHint   = loc("Sem ela, o app usa a voz do sistema", "Without it, the app uses the system voice")
    static let createKeyAnthropic = loc("Criar chave em console.anthropic.com", "Create key at console.anthropic.com")
    static let createKeyEleven    = loc("Criar chave em elevenlabs.io",       "Create key at elevenlabs.io")
    static let saveFooter       = loc("Chaves são salvas no Keychain; opções de servidor no config.json. Reinicie o app para aplicar.",
                                       "Keys are saved in Keychain; server options in config.json. Restart the app to apply.")
    static let saveAndStart     = loc("Salvar e começar",               "Save and start")
    static let saveButton       = loc("Salvar",                         "Save")

    // MARK: - Setup (instalação local)

    static let setupTitle       = loc("Pynkaro — Configuração local",   "Pynkaro — Local setup")
    static let setupWelcome     = loc("Instalação local no Mac 🦊",     "Local setup on Mac 🦊")
    static let setupSubtitle    = loc("Seu Mac tem %@ GB de RAM. Escolha o modelo e clique em \"Instalar e configurar\" — o app executa a sequência completa e reinicia com a configuração aplicada.",
                                       "Your Mac has %@ GB of RAM. Choose a model and click \"Install and configure\" — the app runs the full sequence and restarts with the configuration applied.")
    static let setupModelGroup  = loc("1. Modelo (LLM)",                "1. Model (LLM)")
    static let setupVoiceGroup  = loc("2. Voz Kokoro local",            "2. Local Kokoro voice")
    static let setupVoiceDesc   = loc("Instalado automaticamente pelo orquestrador (venv + modelo baixado na 1ª execução). Os comandos manuais abaixo são apenas o fallback:",
                                       "Installed automatically by the orchestrator (venv + model downloaded on first run). The manual commands below are fallback only:")
    static let setupUsePaidApi  = loc("Usar API paga…",                 "Use paid API…")
    static let setupInstallBtn  = loc("Instalar e configurar",          "Install and configure")
    static let setupInstalling  = loc("Instalando…",                    "Installing…")
    static let setupDoneTitle   = loc("✅ Instalação concluída!",       "✅ Installation complete!")
    static let setupDoneBody    = loc("O Pynkaro está pronto. Abra as Configurações para ajustar wake words, voz e outros detalhes.",
                                       "Pynkaro is ready. Open Settings to adjust wake words, voice, and other details.")
    static let setupRAMWarning  = loc("⚠️ Ocultas (RAM insuficiente):", "⚠️ Hidden (insufficient RAM):")
    static let setupRAMDetail   = loc("Ocupa ~%@ GB | exige %@ GB de RAM (este Mac tem %@ GB)",
                                       "Takes ~%@ GB | requires %@ GB RAM (this Mac has %@ GB)")
    static let setupRAMBlocked  = loc("❌ %@ exige %@ GB de RAM; este Mac tem %@ GB.",
                                       "❌ %@ requires %@ GB RAM; this Mac has %@ GB.")
    static let setupOpenSettings = loc("Abrir Configurações",           "Open Settings")

    // MARK: - Logs

    static let logsCopy         = loc("Copiar",                         "Copy")
    static let logsOpenFolder   = loc("Abrir pasta",                    "Open folder")
    static let logsClear        = loc("Limpar",                         "Clear")
    static let logsEmpty        = loc("Nenhum log ainda.",              "No logs yet.")

    // MARK: - Misc

    static let okButton         = loc("OK",                             "OK")
    static let cancelButton     = loc("Cancelar",                       "Cancel")
    static let copyButton       = loc("Copiar",                         "Copy")
    static let copiedCheck      = loc("Copiado ✓",                      "Copied ✓")
}
