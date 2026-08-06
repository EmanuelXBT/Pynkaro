import Foundation
import Combine
import UserNotifications

/// Política de log do Pynkaro:
/// - Em produção (.app), o stdout registra **apenas erros** — o diálogo do
///   assistente (estados, transcrições, respostas) não vai para o log.
/// - Em desenvolvimento (`swift run` / binário direto), `debug` imprime tudo.
enum Log {
    /// true fora do .app (modo dev: `swift run` ou binário direto).
    static var isDev: Bool {
        Bundle.main.bundleURL.pathExtension != "app"
    }

    /// Diálogo/informação — imprime apenas em modo dev e registra no painel.
    static func debug(_ message: String) {
        if isDev { print(message) }
        LogStore.shared.add(level: .debug, message: message)
    }

    /// Erros — sempre impressos, registrados no painel + arquivo e, em
    /// produção, notificados pelo sistema.
    static func error(_ message: String) {
        print(message)
        LogStore.shared.add(level: .error, message: message)
    }
}

/// Buffer de eventos em memória (painel de Logs nas Configurações) + arquivo
/// persistente (~/Library/Logs/Pynkaro/pynkaro.log) + indicador de erros não
/// vistos (menu bar) + notificação do sistema em produção.
final class LogStore: ObservableObject {
    static let shared = LogStore()

    enum Level: String {
        case debug, error
    }

    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let date: Date
        let level: Level
        let message: String
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var hasUnseenErrors = false

    private let maxEntries = 500

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    // MARK: - Caminhos

    var logsDirectoryURL: URL {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Logs/Pynkaro", isDirectory: true)
    }

    var logFileURL: URL {
        logsDirectoryURL.appendingPathComponent("pynkaro.log")
    }

    // MARK: - Registro

    func add(level: Level, message: String) {
        let entry = Entry(date: Date(), level: level, message: message)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.entries.append(entry)
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
            if level == .error {
                self.hasUnseenErrors = true
            }
        }
        appendToFile(entry)
        if level == .error && !Log.isDev {
            sendNotification(entry)
        }
    }

    /// Marca os erros como vistos (limpa o indicador da menu bar).
    func markSeen() {
        DispatchQueue.main.async { [weak self] in
            self?.hasUnseenErrors = false
        }
    }

    /// Limpa o buffer do painel e o arquivo em disco.
    func clear() {
        DispatchQueue.main.async { [weak self] in
            self?.entries.removeAll()
            self?.hasUnseenErrors = false
        }
        do {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                try FileManager.default.removeItem(at: logFileURL)
            }
        } catch {
            print("⚠️ Não consegui limpar o arquivo de log: \(error.localizedDescription)")
        }
    }

    // MARK: - Arquivo persistente

    private func appendToFile(_ entry: Entry) {
        let line = "\(Self.dateFormatter.string(from: entry.date)) [\(entry.level.rawValue.uppercased())] \(entry.message)\n"
        do {
            try FileManager.default.createDirectory(at: logsDirectoryURL,
                                                    withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: logFileURL.path) {
                try line.data(using: .utf8)?.write(to: logFileURL)
            } else {
                let handle = try FileHandle(forWritingTo: logFileURL)
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(line.data(using: .utf8) ?? Data())
            }
        } catch {
            print("⚠️ Não consegui escrever o log em \(logFileURL.path): \(error.localizedDescription)")
        }
    }

    // MARK: - Notificação do sistema (produção)

    private func sendNotification(_ entry: Entry) {
        // Blindagem em profundidade: UNUserNotificationCenter.current()
        // crasha fora de um bundle .app (ex.: binário de dev direto).
        guard !Log.isDev else { return }
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Pynkaro — erro"
        content.body = entry.message
        content.sound = .default
        center.add(UNNotificationRequest(identifier: UUID().uuidString,
                                         content: content,
                                         trigger: nil))
    }
}
