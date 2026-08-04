import Foundation

/// Gerencia serviços persistentes via LaunchAgent (sobrevivem a reboot e ao
/// fechamento do app). Usado pelos servidores Kokoro e MLX no modo Mac local.
final class ServiceManager {

    static let shared = ServiceManager()

    private let agentsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents")
    private let runner = CommandRunner()

    func isLoaded(label: String) -> Bool {
        let out = runner.runSync("launchctl print gui/$(id -u)/\(label)")
        return out.exitCode == 0
    }

    /// Instala (ou atualiza) um LaunchAgent e o carrega via launchctl.
    func install(label: String, command: [String], logPath: String) -> Bool {
        let plistURL = agentsDir.appendingPathComponent("\(label).plist")
        let dict: [String: Any] = [
            "Label": label,
            "ProgramArguments": command,
            "RunAtLoad": true,
            "KeepAlive": true,
            "StandardOutPath": logPath,
            "StandardErrorPath": logPath,
        ]
        do {
            try FileManager.default.createDirectory(at: agentsDir,
                                                    withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: dict,
                                                          format: .xml, options: 0)
            try data.write(to: plistURL)
            // Descarrega versão anterior (se houver) e carrega a nova.
            _ = runner.runSync("launchctl bootout gui/$(id -u)/\(label) 2>/dev/null")
            let out = runner.runSync("launchctl bootstrap gui/$(id -u) \(plistURL.path)")
            return out.exitCode == 0
        } catch {
            return false
        }
    }

    func uninstall(label: String) {
        let plistURL = agentsDir.appendingPathComponent("\(label).plist")
        _ = runner.runSync("launchctl bootout gui/$(id -u)/\(label) 2>/dev/null")
        try? FileManager.default.removeItem(at: plistURL)
    }
}
