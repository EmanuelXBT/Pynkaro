import Foundation
import Security

/// Chaves de API do Pynkaro.
///
/// Ordem de resolução (a primeira encontrada vence):
///   1. Keychain do macOS — onde a interface do app salva (usuários finais)
///   2. config.json — diretório atual ou ~/.config/pynkaro/ (desenvolvimento)
///   3. Variáveis de ambiente ANTHROPIC_API_KEY / ELEVENLABS_API_KEY (fallback)
struct Config: Decodable {
    var anthropicApiKey: String?
    var elevenLabsApiKey: String?

    enum CodingKeys: String, CodingKey {
        case anthropicApiKey = "anthropic_api_key"
        case elevenLabsApiKey = "elevenlabs_api_key"
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
