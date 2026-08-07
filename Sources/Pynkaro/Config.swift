import Foundation
import Security

/// Chaves de API do Pynkaro.
///
/// Ordem de resolução (a primeira encontrada vence):
///   1. Keychain do macOS — onde a interface do app salva (usuários finais)
///   2. config.json — diretório atual ou ~/.config/pynkaro/ (desenvolvimento)
///   3. Variáveis de ambiente ANTHROPIC_API_KEY / ELEVENLABS_API_KEY (fallback)
///
/// Modo Umbrel (self-hosted): se `PYNKARO_LLM_BASE_URL` (Ollama) e/ou
/// `PYNKARO_KOKORO_URL` (Kokoro TTS) estiverem definidas, o Pynkaro usa os
/// serviços locais do servidor em vez das APIs pagas. Nenhuma chave de API
/// é necessária nesse modo.
struct Config: Decodable {
    var anthropicApiKey: String?
    var elevenLabsApiKey: String?
    // Modo Umbrel: campos opcionais no config.json (durável — valem mesmo
    // quando o app é aberto pelo Finder, onde env vars do shell não chegam).
    var ollamaUrl: String?
    var kokoroUrl: String?
    var llmModel: String?
    var kokoroVoice: String?
    var searxngUrl: String?
    var wakeWords: [String]?
    /// Habilita a apresentação pré-definida ("se apresente" → IntroScript).
    /// OFF por padrão; ligue para demonstrações/vídeo. Resolução:
    /// env var PYNKARO_INTRO_ENABLED > config.json (intro_enabled).
    var introEnabled: Bool?
    /// Modo de operação explícito: "mac" | "umbrel" | "api". Gravado pelas
    /// Configurações/Instalador. Configs antigos sem o campo são inferidos
    /// pela URL (localhost → Mac, IP LAN → Umbrel, ausente → API).
    var mode: String?
    /// Locale do reconhecimento de fala (ex.: "pt-BR", "en-US"). Default "pt-BR".
    /// Resolução: env var PYNKARO_SPEECH_LOCALE > config.json (speech_locale).
    var speechLocale: String?

    enum CodingKeys: String, CodingKey {
        case anthropicApiKey = "anthropic_api_key"
        case elevenLabsApiKey = "elevenlabs_api_key"
        case ollamaUrl = "ollama_url"
        case kokoroUrl = "kokoro_url"
        case llmModel = "llm_model"
        case kokoroVoice = "kokoro_voice"
        case searxngUrl = "searxng_url"
        case wakeWords = "wake_words"
        case introEnabled = "intro_enabled"
        case mode = "mode"
        case speechLocale = "speech_locale"
    }

    static let shared = load()

    // MARK: - Leitura

    static var anthropicKey: String? {
        resolve(keychainAccount: "anthropic_api_key",
                fileValue: shared.anthropicApiKey,
                envVar: "ANTHROPIC_API_KEY")
    }

    static var elevenLabsKey: String? {
        resolve(keychainAccount: "elevenlabs_api_key",
                fileValue: shared.elevenLabsApiKey,
                envVar: "ELEVENLABS_API_KEY")
    }

    // MARK: - Modo Umbrel (self-hosted)

    /// Base URL do Ollama (ex.: http://umbrel.local:11434/v1). Se definida,
    /// o Pynkaro usa o LLM local em vez da API da Anthropic.
    /// Resolução: env var PYNKARO_LLM_BASE_URL > config.json (ollama_url).
    static var ollamaBaseURL: String? {
        env("PYNKARO_LLM_BASE_URL") ?? shared.ollamaUrl
    }

    /// Base URL do Kokoro TTS (ex.: http://umbrel.local:8877). Se definida,
    /// o Pynkaro usa o TTS local em vez da ElevenLabs.
    /// Resolução: env var PYNKARO_KOKORO_URL > config.json (kokoro_url).
    static var kokoroBaseURL: String? {
        env("PYNKARO_KOKORO_URL") ?? shared.kokoroUrl
    }

    /// Modelo do Ollama (default razoável para português + hardware modesto).
    /// Resolução: env var PYNKARO_LLM_MODEL > config.json (llm_model).
    static var ollamaModel: String {
        env("PYNKARO_LLM_MODEL") ?? shared.llmModel ?? "qwen2.5:7b"
    }

    /// Voz pt-BR do Kokoro (as disponíveis dependem do modelo baixado).
    /// Resolução: env var PYNKARO_KOKORO_VOICE > config.json (kokoro_voice).
    static var kokoroVoice: String {
        env("PYNKARO_KOKORO_VOICE") ?? shared.kokoroVoice ?? "pm_alex"
    }

    /// Base URL do SearXNG (ex.: http://umbrel.local:8080). Se definida,
    /// o Pynkaro busca na web antes de montar o prompt do Ollama.
    /// Resolução: env var PYNKARO_SEARXNG_URL > config.json (searxng_url).
    static var searxngBaseURL: String? {
        env("PYNKARO_SEARXNG_URL") ?? shared.searxngUrl
    }

    /// Lista de wake words do config.json (além do padrão "pincaro").
    static var wakeWords: [String]? {
        shared.wakeWords
    }

    /// Apresentação pré-definida ("se apresente") ATIVADA? OFF por padrão —
    /// ligue via config.json (`intro_enabled: true`) ou env
    /// `PYNKARO_INTRO_ENABLED=1` (ex.: gravação de vídeo de demonstração).
    static var introEnabled: Bool {
        if let envValue = env("PYNKARO_INTRO_ENABLED") {
            return envValue == "1" || envValue.lowercased() == "true"
        }
        return shared.introEnabled ?? false
    }

    /// Locale do reconhecimento de fala (ex.: "pt-BR", "en-US"). Default "pt-BR".
    /// Resolução: env var PYNKARO_SPEECH_LOCALE > config.json (speech_locale).
    static var speechLocale: String {
        env("PYNKARO_SPEECH_LOCALE") ?? shared.speechLocale ?? "pt-BR"
    }

    /// Modos de operação suportados pelo Pynkaro.
    enum PynkaroMode: String {
        /// Tudo roda no próprio Mac (Ollama local + Kokoro via LaunchAgent).
        case mac = "mac"
        /// Serviços na Umbrel da rede (Ollama/Kokoro/SearXNG via LAN).
        case umbrel = "umbrel"
        /// APIs pagas (Anthropic + ElevenLabs).
        case api = "api"
    }

    /// Inferência do modo pela URL (usada quando o config não tem `mode`).
    /// Separada do Config.shared (estático) para ser testável.
    static func inferMode(ollamaURL: String?) -> PynkaroMode {
        guard let url = ollamaURL else { return .api }
        if url.contains("localhost") || url.contains("127.0.0.1") {
            return .mac
        }
        return .umbrel
    }

    /// Modo atual. Usa o campo `mode` do config quando presente; para configs
    /// antigos (sem o campo), infere pela URL: localhost → Mac, IP de rede →
    /// Umbrel, ausente → API. Essa inferência é o que elimina o conflito
    /// "config do Mac aparecendo na aba Umbrel".
    static var operationMode: PynkaroMode {
        if let raw = shared.mode, let mode = PynkaroMode(rawValue: raw) {
            return mode
        }
        return inferMode(ollamaURL: ollamaBaseURL)
    }

    private static func env(_ key: String) -> String? {
        let value = ProcessInfo.processInfo.environment[key]
        return (value?.isEmpty ?? true) ? nil : value
    }

    // MARK: - Escrita (janela de Configurações)

    static func setAnthropicKey(_ value: String) {
        Keychain.write(value.trimmingCharacters(in: .whitespacesAndNewlines),
                       account: "anthropic_api_key")
    }

    static func setElevenLabsKey(_ value: String) {
        Keychain.write(value.trimmingCharacters(in: .whitespacesAndNewlines),
                       account: "elevenlabs_api_key")
    }

    // MARK: - Gravação do config.json (opções de servidor)

    /// Salva as opções no config.json de ~/.config/pynkaro/. O app relê o
    /// arquivo na próxima inicialização (Config.shared é estático).
    /// Campos vazios são omitidos — sem `ollama_url` o app volta ao modo API.
    /// `mode` é sempre gravado para o seletor de Configurações abrir a aba
    /// correta (mac/umbrel/api), eliminando a ambiguidade da inferência por URL.
    static func saveUmbrelOptions(mode: PynkaroMode,
                                  ollamaUrl: String?, kokoroUrl: String?,
                                  searxngUrl: String?, llmModel: String?,
                                  kokoroVoice: String?, wakeWords: [String]?,
                                  speechLocale: String?) {
        var dict: [String: Any] = ["mode": mode.rawValue]
        if let ollamaUrl, !ollamaUrl.isEmpty { dict["ollama_url"] = ollamaUrl }
        if let kokoroUrl, !kokoroUrl.isEmpty { dict["kokoro_url"] = kokoroUrl }
        if let searxngUrl, !searxngUrl.isEmpty { dict["searxng_url"] = searxngUrl }
        if let llmModel, !llmModel.isEmpty { dict["llm_model"] = llmModel }
        if let kokoroVoice, !kokoroVoice.isEmpty { dict["kokoro_voice"] = kokoroVoice }
        if let wakeWords, !wakeWords.isEmpty { dict["wake_words"] = wakeWords }
        if let speechLocale, !speechLocale.isEmpty { dict["speech_locale"] = speechLocale }

        let fm = FileManager.default
        let url = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/pynkaro/config.json")
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: dict,
                                                  options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url)
            Log.debug("🔧 Configurações salvas em \(url.path)")
        } catch {
            Log.error("⚠️ Falha ao salvar configurações: \(error.localizedDescription)")
        }
    }

    // MARK: - Interno

    private static func resolve(keychainAccount: String,
                                fileValue: String?,
                                envVar: String) -> String? {
        if let stored = Keychain.read(keychainAccount), !stored.isEmpty {
            return stored
        }
        if let fileValue, !fileValue.isEmpty {
            return fileValue
        }
        if let envValue = ProcessInfo.processInfo.environment[envVar], !envValue.isEmpty {
            return envValue
        }
        return nil
    }

    private static func load() -> Config {
        let fm = FileManager.default
        // Prioridade: ~/.config/pynkaro/config.json PRIMEIRO (é onde o app de
        // menu bar e o "Instalar versão local" gravam). O config.json da raiz
        // do projeto é só fallback de desenvolvimento — se viesse antes, um
        // config antigo (ex.: modo Umbrel) sobrescreveria o modo local do Mac.
        let candidates = [
            fm.homeDirectoryForCurrentUser.appendingPathComponent(".config/pynkaro/config.json"),
            URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("config.json")
        ]
        for url in candidates where fm.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                let config = try JSONDecoder().decode(Config.self, from: data)
                Log.debug("🔑 Configuração carregada de \(url.path)")
                return config
            } catch {
                Log.error("⚠️ Não consegui ler \(url.path): \(error.localizedDescription)")
            }
        }
        return Config(anthropicApiKey: nil, elevenLabsApiKey: nil)
    }
}

/// Acesso mínimo ao Keychain (senhas genéricas do serviço com.ralbuque.pynkaro).
private enum Keychain {
    private static let service = "com.ralbuque.pynkaro"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Grava o valor (substituindo o existente); valor vazio remove a entrada.
    static func write(_ value: String, account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var attributes = base
        attributes[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
