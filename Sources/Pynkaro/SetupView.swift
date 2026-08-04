import SwiftUI
import AppKit

/// Janela de instalação do modo 100% local no Mac (Ollama/MLX + Kokoro).
/// Oferece instalação automática (orquestrador com log streaming) e os
/// comandos manuais como fallback.
struct SetupView: View {
    var onDone: (() -> Void)?

    private static func ramGB() -> Int {
        Int(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
    }

    private let ram = Self.ramGB()

    @State private var selectedOptionID: String
    @StateObject private var orchestrator = SetupOrchestrator()
    @State private var copiedInstall = false
    @State private var copiedTTS = false

    private var selectedOption: SetupOption {
        SetupOption.all.first { $0.id == selectedOptionID } ?? SetupOption.all[0]
    }

    private let mlxSetupCommand = "python3 -m venv ~/.pynkaro-mlx && ~/.pynkaro-mlx/bin/pip install -U mlx-lm"
    private let ttsInstallCommand = "python3 -m venv ~/.pynkaro-tts && ~/.pynkaro-tts/bin/pip install -U kokoro-onnx soundfile fastapi uvicorn numpy"
    private let ttsRunCommand = "~/.pynkaro-tts/bin/python3 tools/kokoro_local_server.py"

    init(onDone: (() -> Void)? = nil) {
        self.onDone = onDone
        _selectedOptionID = State(initialValue: SetupOption.recommendedID(ramGB: Self.ramGB()))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Instalação local no Mac 🦊")
                .font(.title2).bold()
            Text("Seu Mac tem \(ram) GB de RAM. Escolha o modelo e clique em \"Instalar e configurar\" — o app executa a sequência completa e reinicia com a configuração aplicada.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // 1. Modelo
            GroupBox("1. Modelo (LLM)") {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("", selection: $selectedOptionID) {
                        ForEach(SetupOption.all) { option in
                            Text(option.label).tag(option.id)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    Text("RAM: \(selectedOption.ramNote). \(selectedOption.needsMLX ? "Requer o servidor MLX (LaunchAgent)." : "Usa o Ollama (app de menu bar).")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(selectedOption.needsMLX ? mlxSetupCommand : (selectedOption.pullCommand ?? ""))
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button(copiedInstall ? "Copiado ✓" : "Copiar") {
                            copyToPasteboard(selectedOption.needsMLX ? mlxSetupCommand : (selectedOption.pullCommand ?? ""))
                            copiedInstall = true
                        }
                    }
                }
            }

            // 2. Kokoro
            GroupBox("2. Voz Kokoro local") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Instalado automaticamente (venv + modelo baixado na 1ª execução). Comando manual: ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(ttsInstallCommand)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button(copiedTTS ? "Copiado ✓" : "Copiar") {
                            copyToPasteboard(ttsInstallCommand)
                            copiedTTS = true
                        }
                    }
                    HStack {
                        Text(ttsRunCommand)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button("Copiar") { copyToPasteboard(ttsRunCommand) }
                    }
                }
            }

            // Ações
            HStack(spacing: 12) {
                if orchestrator.isRunning {
                    ProgressView().controlSize(.small)
                    Text(orchestrator.currentStep).font(.caption)
                }
                Spacer()
                Button("Usar API paga…") { onDone?() }
                    .disabled(orchestrator.isRunning)
                Button(orchestrator.isRunning ? "Instalando…" : "Instalar e configurar") {
                    orchestrator.install(option: selectedOption) { option in
                        apply(option)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(orchestrator.isRunning)
            }

            // Log de instalação
            if !orchestrator.logLines.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(orchestrator.logLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 180)
                .background(Color.black.opacity(0.06))
                .cornerRadius(6)
            }
        }
        .padding(20)
        // Tamanho fixo nas duas dimensões: sem ele o NSHostingView tenta
        // animar a janela ao tamanho do conteúdo e estoura o ciclo de
        // constraints (crash "Update Constraints in Window pass").
        .frame(width: 640, height: 660)
    }

    private func apply(_ option: SetupOption) {
        Config.saveUmbrelOptions(
            ollamaUrl: option.ollamaUrl,
            kokoroUrl: "http://localhost:8888",
            searxngUrl: Config.searxngBaseURL,
            llmModel: option.modelName,
            kokoroVoice: "pm_alex",
            wakeWords: Config.wakeWords)
        restartApp()
    }

    private func copyToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// Relança o app (via LaunchServices para .app, ou o binário direto
    /// no caso de `swift run`) e encerra a instância atual.
    private func restartApp() {
        let task = Process()
        if Bundle.main.bundleURL.pathExtension == "app" {
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = [Bundle.main.bundleURL.path]
        } else {
            task.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        }
        try? task.run()
        NSApp.terminate(nil)
    }
}
