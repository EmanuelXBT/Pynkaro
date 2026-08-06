import AppKit

/// Relança o app (via LaunchServices para .app, ou o binário direto no caso
/// de `swift run`) e encerra a instância atual. Compartilhado entre as
/// janelas de Configurações (PynkaroApp) e Instalação (SetupView) — antes
/// havia duas cópias idênticas desta lógica.
enum AppRestart {
    static func relaunch() {
        let task = Process()
        if Bundle.main.bundleURL.pathExtension == "app" {
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = [Bundle.main.bundleURL.path]
        } else {
            // CommandLine.arguments[0] pode ser só o nome do binário quando
            // executado via `swift run` (sem caminho), o que faz o run()
            // falhar silenciosamente e o app morre SEM relançar — e as
            // mudanças de config (ex.: wake words) só valem no processo novo.
            // Bundle.main.executablePath é sempre absoluto e confiável.
            task.executableURL = URL(fileURLWithPath: Bundle.main.executablePath
                                     ?? CommandLine.arguments[0])
        }
        do {
            try task.run()
        } catch {
            print("⚠️ Falha ao relançar o app: \(error.localizedDescription)")
        }
        // Pequena espera para o novo processo iniciar antes de encerrar o
        // atual (evita perder o terminal no modo `swift run`).
        usleep(300_000)
        NSApp.terminate(nil)
    }
}
