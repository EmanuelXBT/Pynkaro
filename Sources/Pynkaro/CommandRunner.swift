import Foundation

/// Executa comandos de shell com streaming de saída (linha a linha).
/// A UI observa `onLine`; o completion entrega o exit code.
final class CommandRunner {

    struct Output {
        let exitCode: Int32
        let text: String
    }

    /// Executa um comando shell completo (ex.: "ollama pull qwen2.5:7b").
    /// Usa /bin/bash -lc para resolver PATH, ~ e encadeamentos.
    func run(_ command: String,
             onLine: @escaping (String) -> Void = { _ in },
             completion: @escaping (Output) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        var buffer = Data()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            buffer.append(data)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = String(data: buffer[..<nl], encoding: .utf8) ?? ""
                buffer.removeSubrange(buffer.startIndex...nl)
                DispatchQueue.main.async { onLine(line) }
            }
        }

        process.terminationHandler = { proc in
            DispatchQueue.main.async {
                completion(Output(exitCode: proc.terminationStatus, text: ""))
            }
        }

        do {
            try process.run()
        } catch {
            completion(Output(exitCode: -1, text: error.localizedDescription))
        }
    }

    /// Executa e aguarda (sem streaming) — usado em verificações rápidas.
    func runSync(_ command: String) -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return Output(exitCode: process.terminationStatus,
                          text: String(data: data, encoding: .utf8) ?? "")
        } catch {
            return Output(exitCode: -1, text: error.localizedDescription)
        }
    }
}
