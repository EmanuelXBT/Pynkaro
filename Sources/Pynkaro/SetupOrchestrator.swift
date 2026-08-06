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
    /// RAM mínima do Mac para a opção ser viável (GB). Opções acima da RAM
    /// instalada são bloqueadas no seletor — ex.: 27B é impraticável num
    /// M4 Air de 16 GB (não responde; o load/swap estoura).
    let minRAMGB: Int
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
                    serverCommand: nil,
                    minRAMGB: 4),
        SetupOption(id: "qwen7b",
                    label: "qwen2.5:7b (equilíbrio)",
                    ollamaUrl: "http://localhost:11434/v1",
                    modelName: "qwen2.5:7b",
                    needsMLX: false,
                    ramNote: "~6 GB de RAM",
                    pullCommand: "ollama pull qwen2.5:7b",
                    serverLabel: nil,
                    serverCommand: nil,
                    minRAMGB: 8),
        SetupOption(id: "qwen14b",
                    label: "qwen2.5:14b (qualidade, 24 GB+)",
                    ollamaUrl: "http://localhost:11434/v1",
                    modelName: "qwen2.5:14b",
                    needsMLX: false,
                    ramNote: "~11 GB de RAM",
                    pullCommand: "ollama pull qwen2.5:14b",
                    serverLabel: nil,
                    serverCommand: nil,
                    minRAMGB: 16),
        SetupOption(id: "bonsaiQ1",
                    label: "Bonsai-27B Q1_0 via Ollama (27B em ~4 GB)",
                    ollamaUrl: "http://localhost:11434/v1",
                    modelName: "hf.co/prism-ml/Bonsai-27B-gguf:Q1_0",
                    needsMLX: false,
                    ramNote: "~4-5 GB de RAM, mas 27B exige 32 GB+ p/ ser viável",
                    pullCommand: "ollama pull hf.co/prism-ml/Bonsai-27B-gguf:Q1_0",
                    serverLabel: nil,
                    serverCommand: nil,
                    minRAMGB: 32),
        SetupOption(id: "bonsaiMlx1",
                    label: "Bonsai-27B 1-bit via MLX (mais rápido no M4)",
                    ollamaUrl: "http://localhost:11435/v1",
                    modelName: "prism-ml/Bonsai-27B-mlx-1bit",
                    needsMLX: true,
                    ramNote: "~4-6 GB de RAM, mas 27B exige 32 GB+ p/ ser viável",
                    pullCommand: nil,
                    serverLabel: "com.pynkaro.mlx1",
                    serverCommand: ["\(NSHomeDirectory())/.pynkaro-mlx/bin/mlx_lm.server",
                                    "--model", "prism-ml/Bonsai-27B-mlx-1bit",
                                    // Bind explícito em loopback: o default do
                                    // mlx_lm.server já é 127.0.0.1 (verificado
                                    // no cli oficial do mlx-lm), mas o pin
                                    // protege contra mudança de default futuro.
                                    "--host", "127.0.0.1",
                                    "--port", "11435"],
                    minRAMGB: 32),
        SetupOption(id: "bonsaiMlxTer",
                    label: "Bonsai-27B Ternary 2-bit via MLX (qualidade 95% do FP16)",
                    ollamaUrl: "http://localhost:11435/v1",
                    modelName: "prism-ml/Ternary-Bonsai-27B-mlx-2bit",
                    needsMLX: true,
                    ramNote: "~8-9 GB de RAM, mas 27B exige 32 GB+ p/ ser viável",
                    pullCommand: nil,
                    serverLabel: "com.pynkaro.mlx2",
                    serverCommand: ["\(NSHomeDirectory())/.pynkaro-mlx/bin/mlx_lm.server",
                                    "--model", "prism-ml/Ternary-Bonsai-27B-mlx-2bit",
                                    "--host", "127.0.0.1",
                                    "--port", "11435"],
                    minRAMGB: 32),
    ]

    /// Opções compatíveis com a RAM do Mac atual (usado pelo seletor).
    static func compatible(ramGB: Int) -> [SetupOption] {
        all.filter { $0.minRAMGB <= ramGB }
    }

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
        log("⚠️ Nenhum Python >= 3.10 encontrado. Instale com: brew install python@3.12")
        return "python3"
    }

    func install(option: SetupOption, onApply: @escaping (SetupOption) -> Void) {
        guard !isRunning else { return }
        // Bloqueio de hardware: opção que exige mais RAM que o Mac tem não
        // deve nem tentar instalar (27B num M4 de 16 GB fica em swap e não
        // responde). O seletor já oculta essas opções; isto é defesa em
        // profundidade caso a opção chegue por outro caminho.
        let ram = Int(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
        guard option.minRAMGB <= ram else {
            log("❌ \(option.label) exige \(option.minRAMGB) GB de RAM; este Mac tem \(ram) GB.")
            log("   Escolha um modelo compatível (ex.: qwen2.5:7b).")
            return
        }
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
            // Versões pinadas (==) para reprodutibilidade e segurança: sem -U,
            // uma versão nova não muda comportamento nem quebra o servidor
            // silenciosamente. Para atualizar: rode
            //   ~/.pynkaro-mlx/bin/pip index versions mlx-lm
            // e ajuste o == abaixo.
            runner.run("\(python) -m venv ~/.pynkaro-mlx && ~/.pynkaro-mlx/bin/pip install mlx-lm==0.31.3",
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
        if fm.fileExists(atPath: venvPython) && fm.fileExists(atPath: scriptPath)
            && isKokoroVenvUsable() {
            log("✅ Kokoro já instalado.")
            startKokoroServer(completion: completion)
        } else {
            // Venv existe mas está quebrado (ex.: criado com python3.9 do CLT
            // antes do resolvePython, sem numpy) → recria do zero.
            if fm.fileExists(atPath: venvPython) {
                log("♻️ Venv do Kokoro inválido (Python < 3.10 ou numpy ausente). Recriando...")
                _ = runner.runSync("rm -rf ~/.pynkaro-tts")
            }
            log("📦 Criando venv e instalando kokoro-onnx (pode demorar)...")
            let python = resolvePython()
            log("🐍 Usando \(python) (\(runner.runSync("\(python) --version").text.trimmingCharacters(in: .whitespacesAndNewlines)))")
            // Versões pinadas (==) — mesmo critério do MLX acima: reprodutível e
            // imune a regressões silenciosas de versões novas. Para atualizar:
            //   ~/.pynkaro-tts/bin/pip index versions kokoro-onnx
            runner.run("\(python) -m venv ~/.pynkaro-tts && ~/.pynkaro-tts/bin/pip install kokoro-onnx==0.5.0 soundfile==0.14.0 fastapi==0.141.1 uvicorn==0.52.1 numpy==2.5.1",
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

    /// Valida que o venv do Kokoro é utilizável: Python >= 3.10 (kokoro-onnx
    /// exige) e numpy instalado (o servidor importa numpy no boot). Um venv
    /// criado com o python3.9 do Command Line Tools existe mas quebra no
    /// runtime — por isso a validação vai além do fileExists.
    private func isKokoroVenvUsable() -> Bool {
        let python = "\(NSHomeDirectory())/.pynkaro-tts/bin/python3"
        let ver = runner.runSync("\"\(python)\" -c 'import sys; print(sys.version_info >= (3, 10))'").text
        guard ver.contains("True") else { return false }
        let numpy = runner.runSync("\"\(python)\" -c 'import numpy'")
        return numpy.exitCode == 0
    }

    private func copyKokoroScript(to destination: String) {
        // Procura no bundle (make_app.sh copia p/ Resources) ou em tools/.
        var source: String? = Bundle.main.resourceURL?
            .appendingPathComponent("kokoro_local_server.py").path
        if let s = source, !fm.fileExists(atPath: s) {
            source = fm.currentDirectoryPath + "/tools/kokoro_local_server.py"
        }
        if let s = source, fm.fileExists(atPath: s) {
            // copyItem NÃO sobrescreve: uma cópia antiga instalada fica sem
            // rotas novas (ex.: /v1/audio/voices) e o dropdown de vozes fica
            // vazio. Remove o destino antes de copiar (sempre atualiza).
            if fm.fileExists(atPath: destination) {
                try? fm.removeItem(atPath: destination)
            }
            do {
                try fm.copyItem(atPath: s, toPath: destination)
                log("📄 Script do servidor Kokoro copiado (atualizado).")
            } catch {
                log("⚠️ Falha ao copiar o script do Kokoro: \(error.localizedDescription)")
            }
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
