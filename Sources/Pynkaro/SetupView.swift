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

    /// Opções compatíveis com a RAM deste Mac. As que exigem mais memória
    /// (ex.: 27B num M4 de 16 GB) ficam ocultas — são impraticáveis.
    private var compatibleOptions: [SetupOption] {
        SetupOption.compatible(ramGB: ram)
    }

    private var blockedOptions: [SetupOption] {
        SetupOption.all.filter { $0.minRAMGB > ram }
    }

    @State private var selectedOptionID: String
    @StateObject private var orchestrator = SetupOrchestrator()
    @State private var copiedInstall = false
    @State private var copiedTTS = false
    @State private var copiedTTSRun = false

    private var selectedOption: SetupOption {
        compatibleOptions.first { $0.id == selectedOptionID } ?? compatibleOptions[0]
    }

    private let mlxSetupCommand = "python3 -m venv ~/.pynkaro-mlx && ~/.pynkaro-mlx/bin/pip install mlx-lm==0.31.3"
    private let ttsInstallCommand = "python3 -m venv ~/.pynkaro-tts && ~/.pynkaro-tts/bin/pip install kokoro-onnx==0.5.0 soundfile==0.14.0 fastapi==0.141.1 uvicorn==0.52.1 numpy==2.5.1"
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
                        ForEach(compatibleOptions) { option in
                            Text(option.label).tag(option.id)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    Text("RAM: \(selectedOption.ramNote). \(selectedOption.needsMLX ? "Requer o servidor MLX (LaunchAgent)." : "Usa o Ollama (app de menu bar).")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !blockedOptions.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("⚠️ Ocultas — RAM insuficiente para este Mac (\(ram) GB):")
                                .font(.caption).bold()
                                .foregroundStyle(.orange)
                            ForEach(blockedOptions) { option in
                                Text("• \(option.label): \(option.ramNote)")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.08))
                        .cornerRadius(6)
                    }
                    Divider()
                    commandRow("Comando de instalação do modelo",
                               selectedOption.needsMLX ? mlxSetupCommand : (selectedOption.pullCommand ?? ""),
                               isCopied: $copiedInstall)
                }
            }

            // 2. Kokoro
            GroupBox("2. Voz Kokoro local") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Instalado automaticamente pelo orquestrador (venv + modelo baixado na 1ª execução). Os comandos manuais abaixo são apenas o fallback:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    commandRow("Instalação da voz (venv + pacotes)",
                               ttsInstallCommand,
                               isCopied: $copiedTTS)
                    Divider()
                    commandRow("Execução do servidor Kokoro",
                               ttsRunCommand,
                               isCopied: $copiedTTSRun)
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
        // Tamanho mínimo nas duas dimensões: sem ele o NSHostingView tenta
        // animar a janela ao tamanho do conteúdo e estoura o ciclo de
        // constraints (crash "Update Constraints in Window pass").
        // O usuário pode redimensionar a janela (maxWidth/.infinity deixam
        // o conteúdo crescer e caber textos longos e o log de instalação).
        .frame(minWidth: 600, minHeight: 620)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func apply(_ option: SetupOption) {
        Config.saveUmbrelOptions(
            mode: .mac,
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

    /// Linha padrão de comando (design system): rótulo descritivo, caixa
    /// monoespaçada com fundo sutil e botão copiar alinhado à direita.
    private func commandRow(_ title: String,
                            _ command: String,
                            isCopied: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(command)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.black.opacity(0.06))
                    .cornerRadius(6)
                Button(isCopied.wrappedValue ? "Copiado ✓" : "Copiar") {
                    copyToPasteboard(command)
                    isCopied.wrappedValue = true
                }
            }
        }
    }

    /// Relança o app (via LaunchServices para .app, ou o binário direto
    /// no caso de `swift run`) e encerra a instância atual.
    /// Relança o app (helper compartilhadocom as Configurações).
    private func restartApp() {
        AppRestart.relaunch()
    }
}
