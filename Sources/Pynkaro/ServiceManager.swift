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
    /// Se o agente já está carregado (ex.: re-instalação), o bootout é
    /// assíncrono e o bootstrap imediato falharia com "service already
    /// loaded" — por isso há retry e fallback para o estado atual.
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
            Thread.sleep(forTimeInterval: 0.4)  // bootout é assíncrono
            var out = runner.runSync("launchctl bootstrap gui/$(id -u) \(plistURL.path)")
            if out.exitCode != 0 {
                // Primeira tentativa pode falhar se o bootout ainda não
                // completou; espera e tenta de novo.
                Thread.sleep(forTimeInterval: 0.6)
                out = runner.runSync("launchctl bootstrap gui/$(id -u) \(plistURL.path)")
            }
            if out.exitCode == 0 { return true }
            // Bootstrap ainda falhou, mas o agente está ativo (caso de
            // re-instalação): reinicia com o novo comando e considera OK.
            if isLoaded(label: label) {
                _ = runner.runSync("launchctl kickstart -k gui/$(id -u)/\(label)")
                return true
            }
            return false
        } catch {
            return false
        }
    }

    func uninstall(label: String) {
        let plistURL = agentsDir.appendingPathComponent("\(label).plist")
        _ = runner.runSync("launchctl bootout gui/$(id -u)/\(label) 2>/dev/null")
        try? FileManager.default.removeItem(at: plistURL)
    }

    /// Reinicia um LaunchAgent carregado (kill + start) sem recarregar o
    /// plist. Usado na auto-cura: se o servidor não responde no startup,
    /// o app tenta relançar o agente antes de cair no fallback.
    func kickstart(label: String) {
        _ = runner.runSync("launchctl kickstart -k gui/$(id -u)/\(label)")
    }
}
