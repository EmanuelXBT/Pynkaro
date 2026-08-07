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
            Text(L10n.setupWelcome)
                .font(.title2).bold()
            Text(String(format: L10n.setupSubtitle, ram))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // 1. Modelo
            GroupBox(L10n.setupModelGroup) {
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
                        let blockedText = [
                            "Bonsai-27B Q1_0 via Ollama: Ocupa ~4-5 GB de RAM | Qualidade muito reduzida devido à quantização em 1-bit.",
                            "Bonsai-27B 1-bit via MLX (M4): Ocupa ~4-6 GB de RAM | Rápido, mas estoura a memória ao expandir o contexto em Macs de 16 GB.",
                            "Bonsai-27B Ternary 2-bit via MLX: Ocupa ~8-9 GB de RAM | 95% da qualidade do FP16, mas deixa pouca memória livre para o sistema."
                        ]
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.setupRAMWarning + " Modelos de 27B (Requer 32 GB+ de RAM para uso fluido). GPU M4 Pro/Max ou superior recomendado para maior velocidade:")
                                .font(.caption).bold()
                                .foregroundStyle(.orange)
                            ForEach(blockedText, id: \.self) { line in
                                Text(line)
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
            GroupBox(L10n.setupVoiceGroup) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.setupVoiceDesc)
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
                Button(L10n.setupUsePaidApi) { onDone?() }
                    .disabled(orchestrator.isRunning)
                Button(orchestrator.isRunning ? L10n.setupInstalling : L10n.setupInstallBtn) {
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
        // 800px acomoda os textos completos de requisitos das opções ocultas
        // (27B) sem quebra em coluna estreita.
        .frame(minWidth: 800, minHeight: 620)
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
            wakeWords: Config.wakeWords,
            speechLocale: nil,
            uiLanguage: nil)
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
                Button(isCopied.wrappedValue ? L10n.copiedCheck : L10n.copyButton) {
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
