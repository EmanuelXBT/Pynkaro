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

    enum CodingKeys: String, CodingKey {
        case anthropicApiKey = "anthropic_api_key"
        case elevenLabsApiKey = "elevenlabs_api_key"
        case ollamaUrl = "ollama_url"
        case kokoroUrl = "kokoro_url"
        case llmModel = "llm_model"
        case kokoroVoice = "kokoro_voice"
        case searxngUrl = "searxng_url"
        case wakeWords = "wake_words"
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

    /// Base URL do SearXNG (ex.: http://192.168.0.189:8080). Se definida,
    /// o Pynkaro busca na web antes de montar o prompt do Ollama.
    /// Resolução: env var PYNKARO_SEARXNG_URL > config.json (searxng_url).
    static var searxngBaseURL: String? {
        env("PYNKARO_SEARXNG_URL") ?? shared.searxngUrl
    }

    /// Lista de wake words do config.json (além do padrão "pincaro").
    static var wakeWords: [String]? {
        shared.wakeWords
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
        let candidates = [
            URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("config.json"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent(".config/pynkaro/config.json")
        ]
        for url in candidates where fm.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                let config = try JSONDecoder().decode(Config.self, from: data)
                print("🔑 Configuração carregada de \(url.path)")
                return config
            } catch {
                print("⚠️ Não consegui ler \(url.path): \(error.localizedDescription)")
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
