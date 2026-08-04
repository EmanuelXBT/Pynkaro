import Foundation
import Combine

// MARK: - Opção de instalação (compartilhada com a SetupView)

struct SetupOption: Identifiable {
    let id: String
    let label: String
    let ollamaUrl: String
    let modelName: String
    let needsMLX: Bool
    let ramNote: String
    let pullCommand: String?      // nil se MLX (não usa ollama pull)
    let serverLabel: String?      // nil se Ollama (serviço nativo do app)
    let serverCommand: [String]?  // comando do LaunchAgent (MLX)
}

extension SetupOption {
    static let all: [SetupOption] = [
        SetupOption(id: "qwen3b",
                    label: "qwen2.5:3b (rápido, RAM mínima)",
                    ollamaUrl: "http://localhost:11434/v1",
                    modelName: "qwen2.5:3b",
                    needsMLX: false,
                    ramNote: "~2 GB de RAM",
                    pullCommand: "ollama pull qwen2.5:3b",
                    serverLabel: nil,
                    serverCommand: nil),
        SetupOption(id: "qwen7b",
                    label: "qwen2.5:7b (equilíbrio)",
                    ollamaUrl: "http://localhost:11434/v1",
                    modelName: "qwen2.5:7b",
                    needsMLX: false,
                    ramNote: "~6 GB de RAM",
                    pullCommand: "ollama pull qwen2.5:7b",
                    serverLabel: nil,
                    serverCommand: nil),
        SetupOption(id: "qwen14b",
                    label: "qwen2.5:14b (qualidade, 24 GB+)",
                    ollamaUrl: "http://localhost:11434/v1",
                    modelName: "qwen2.5:14b",
                    needsMLX: false,
                    ramNote: "~11 GB de RAM",
                    pullCommand: "ollama pull qwen2.5:14b",
                    serverLabel: nil,
                    serverCommand: nil),
        SetupOption(id: "bonsaiQ1",
                    label: "Bonsai-27B Q1_0 via Ollama (27B em ~4 GB)",
                    ollamaUrl: "http://localhost:11434/v1",
                    modelName: "hf.co/prism-ml/Bonsai-27B-gguf:Q1_0",
                    needsMLX: false,
                    ramNote: "~4-5 GB de RAM",
                    pullCommand: "ollama pull hf.co/prism-ml/Bonsai-27B-gguf:Q1_0",
                    serverLabel: nil,
                    serverCommand: nil),
        SetupOption(id: "bonsaiMlx1",
                    label: "Bonsai-27B 1-bit via MLX (mais rápido no M4)",
                    ollamaUrl: "http://localhost:11435/v1",
                    modelName: "prism-ml/Bonsai-27B-mlx-1bit",
                    needsMLX: true,
                    ramNote: "~4-6 GB de RAM",
                    pullCommand: nil,
                    serverLabel: "com.pynkaro.mlx1",
                    serverCommand: ["\(NSHomeDirectory())/.pynkaro-mlx/bin/mlx_lm.server",
                                    "--model", "prism-ml/Bonsai-27B-mlx-1bit",
                                    "--port", "11435"]),
        SetupOption(id: "bonsaiMlxTer",
                    label: "Bonsai-27B Ternary 2-bit via MLX (qualidade 95% do FP16)",
                    ollamaUrl: "http://localhost:11435/v1",
                    modelName: "prism-ml/Ternary-Bonsai-27B-mlx-2bit",
                    needsMLX: true,
                    ramNote: "~8-9 GB de RAM",
                    pullCommand: nil,
                    serverLabel: "com.pynkaro.mlx2",
                    serverCommand: ["\(NSHomeDirectory())/.pynkaro-mlx/bin/mlx_lm.server",
                                    "--model", "prism-ml/Ternary-Bonsai-27B-mlx-2bit",
                                    "--port", "11435"]),
    ]

    static func recommendedID(ramGB: Int) -> String {
        if ramGB < 12 { return "qwen3b" }
        if ramGB < 24 { return "qwen7b" }
        return "qwen14b"
    }
}

// MARK: - Orquestrador de instalação (máquina de estados)

/// Executa a sequência de instalação conforme a opção escolhida, com log
/// streaming. Etapas são idempotentes: verificam o que já existe antes de
/// reinstalar. Serviços persistentes (Kokoro/MLX) são LaunchAgents.
final class SetupOrchestrator: ObservableObject {
    @Published var logLines: [String] = []
    @Published var isRunning = false
    @Published var currentStep = ""

    private let runner = CommandRunner()
    private let services = ServiceManager.shared
    private let fm = FileManager.default

    private let kokoroLabel = "com.pynkaro.kokoro"

    /// Escolhe um Python >= 3.10 (kokoro-onnx exige). Prefere as versões do
    /// Homebrew; o python3 do Command Line Tools costuma ser 3.9 (incompatível).
    private func resolvePython() -> String {
        let candidates = ["python3.12", "python3.11", "python3.10", "python3"]
        for candidate in candidates {
            let out = runner.runSync("command -v \(candidate) && \(candidate) --version")
            if out.exitCode == 0 { return candidate }
        }
        return "python3"
    }

    func install(option: SetupOption, onApply: @escaping (SetupOption) -> Void) {
        guard !isRunning else { return }
        isRunning = true
        log("🦊 Iniciando instalação: \(option.label)")

        prepareLLM(option: option) { [weak self] ok in
            guard let self else { return }
            guard ok else { self.finish(success: false); return }
            self.prepareKokoro { ok in
                guard ok else { self.finish(success: false); return }
                self.log("✅ Instalação concluída. Aplicando configuração e reiniciando...")
                onApply(option)
            }
        }
    }

    private func finish(success: Bool) {
        isRunning = false
        log(success ? "✅ Concluído." : "❌ Instalação interrompida por erro.")
    }

    // MARK: - LLM

    private func prepareLLM(option: SetupOption, completion: @escaping (Bool) -> Void) {
        if option.needsMLX {
            prepareMLX(option: option, completion: completion)
        } else {
            prepareOllama(option: option, completion: completion)
        }
    }

    private func prepareOllama(option: SetupOption, completion: @escaping (Bool) -> Void) {
        currentStep = "Instalando Ollama"
        let which = runner.runSync("command -v ollama")
        if which.exitCode == 0 {
            log("✅ Ollama já instalado.")
            pullModel(option: option, completion: completion)
        } else {
            log("📦 Instalando Ollama (cask)...")
            runner.run("if command -v brew >/dev/null; then brew install --cask ollama; else echo 'ERRO_BREW'; fi",
                       onLine: { self.log($0) }) { out in
                if out.exitCode == 0 && !out.text.contains("ERRO_BREW") {
                    self.pullModel(option: option, completion: completion)
                } else {
                    self.log("❌ Homebrew não encontrado. Instale em https://brew.sh e rode novamente.")
                    completion(false)
                }
            }
        }
    }

    private func pullModel(option: SetupOption, completion: @escaping (Bool) -> Void) {
        guard let pull = option.pullCommand else { completion(true); return }
        currentStep = "Baixando modelo"
        log("⬇️  \(pull) — pode levar alguns minutos...")
        runner.run(pull, onLine: { self.log($0) }) { out in
            completion(out.exitCode == 0)
        }
    }

    private func prepareMLX(option: SetupOption, completion: @escaping (Bool) -> Void) {
        currentStep = "Instalando MLX"
        let venvPython = "\(NSHomeDirectory())/.pynkaro-mlx/bin/python3"
        if fm.fileExists(atPath: venvPython) {
            log("✅ MLX já instalado.")
            startMLXServer(option: option, completion: completion)
        } else {
            log("📦 Criando venv e instalando mlx-lm (pode demorar)...")
            let python = resolvePython()
            log("🐍 Usando \(python) (\(runner.runSync("\(python) --version").text.trimmingCharacters(in: .whitespacesAndNewlines)))")
            runner.run("\(python) -m venv ~/.pynkaro-mlx && ~/.pynkaro-mlx/bin/pip install -U mlx-lm",
                       onLine: { self.log($0) }) { out in
                if out.exitCode == 0 {
                    self.startMLXServer(option: option, completion: completion)
                } else {
                    self.log("❌ Falha ao instalar MLX (exit \(out.exitCode)).")
                    completion(false)
                }
            }
        }
    }

    private func startMLXServer(option: SetupOption, completion: @escaping (Bool) -> Void) {
        guard let label = option.serverLabel, let cmd = option.serverCommand else {
            completion(true)
            return
        }
        currentStep = "Iniciando servidor MLX"
        let logPath = "\(NSHomeDirectory())/.pynkaro-mlx/server.log"
        if services.install(label: label, command: cmd, logPath: logPath) {
            log("✅ Servidor MLX registrado (LaunchAgent \(label)). Log: \(logPath)")
            completion(true)
        } else {
            log("❌ Falha ao registrar o LaunchAgent do MLX.")
            completion(false)
        }
    }

    // MARK: - Kokoro

    private func prepareKokoro(completion: @escaping (Bool) -> Void) {
        currentStep = "Instalando Kokoro"
        let venvPython = "\(NSHomeDirectory())/.pynkaro-tts/bin/python3"
        let scriptPath = "\(NSHomeDirectory())/.pynkaro-tts/kokoro_local_server.py"
        if fm.fileExists(atPath: venvPython) && fm.fileExists(atPath: scriptPath) {
            log("✅ Kokoro já instalado.")
            startKokoroServer(completion: completion)
        } else {
            log("📦 Criando venv e instalando kokoro-onnx (pode demorar)...")
            let python = resolvePython()
            log("🐍 Usando \(python) (\(runner.runSync("\(python) --version").text.trimmingCharacters(in: .whitespacesAndNewlines)))")
            runner.run("\(python) -m venv ~/.pynkaro-tts && ~/.pynkaro-tts/bin/pip install -U kokoro-onnx soundfile fastapi uvicorn numpy",
                       onLine: { self.log($0) }) { out in
                guard out.exitCode == 0 else {
                    self.log("❌ Falha ao instalar Kokoro (exit \(out.exitCode)).")
                    completion(false)
                    return
                }
                self.copyKokoroScript(to: scriptPath)
                self.startKokoroServer(completion: completion)
            }
        }
    }

    private func copyKokoroScript(to destination: String) {
        // Procura no bundle (make_app.sh copia p/ Resources) ou em tools/.
        var source: String? = Bundle.main.resourceURL?
            .appendingPathComponent("kokoro_local_server.py").path
        if let s = source, !fm.fileExists(atPath: s) {
            source = fm.currentDirectoryPath + "/tools/kokoro_local_server.py"
        }
        if let s = source, fm.fileExists(atPath: s) {
            try? fm.copyItem(atPath: s, toPath: destination)
            log("📄 Script do servidor Kokoro copiado.")
        } else {
            log("⚠️ Script kokoro_local_server.py não encontrado no bundle nem em tools/.")
        }
    }

    private func startKokoroServer(completion: @escaping (Bool) -> Void) {
        currentStep = "Iniciando servidor Kokoro"
        let python = "\(NSHomeDirectory())/.pynkaro-tts/bin/python3"
        let script = "\(NSHomeDirectory())/.pynkaro-tts/kokoro_local_server.py"
        let logPath = "\(NSHomeDirectory())/.pynkaro-tts/server.log"
        if services.install(label: kokoroLabel,
                            command: [python, script],
                            logPath: logPath) {
            log("✅ Servidor Kokoro registrado (LaunchAgent \(kokoroLabel)). Log: \(logPath)")
            completion(true)
        } else {
            log("❌ Falha ao registrar o LaunchAgent do Kokoro.")
            completion(false)
        }
    }

    private func log(_ line: String) {
        DispatchQueue.main.async { self.logLines.append(line) }
    }
}
