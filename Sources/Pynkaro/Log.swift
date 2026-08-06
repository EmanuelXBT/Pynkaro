import Foundation

/// Política de log do Pynkaro:
/// - Em produção (.app), o stdout registra **apenas erros** — o diálogo do
///   assistente (estados, transcrições, respostas) não vai para o log.
/// - Em desenvolvimento (`swift run` / binário direto), `debug` imprime tudo.
enum Log {
    /// true fora do .app (modo dev: `swift run` ou binário direto).
    static var isDev: Bool {
        Bundle.main.bundleURL.pathExtension != "app"
    }

    /// Diálogo/informação — imprime apenas em modo dev.
    static func debug(_ message: String) {
        if isDev { print(message) }
    }

    /// Erros — sempre impressos (é o que o log deve registrar em produção).
    static func error(_ message: String) {
        print(message)
    }
}
