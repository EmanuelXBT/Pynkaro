import SwiftUI
import AppKit
import Combine

/// App de menu bar. A UI do status item é feita com NSStatusItem (AppKit),
/// mais confiável que o MenuBarExtra do SwiftUI no macOS 13.
@main
struct PynkaroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Cena mínima exigida pelo ciclo de vida SwiftUI; a interface real
        // é o NSStatusItem criado no AppDelegate.
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var statusLabelItem: NSMenuItem!
    private var pauseItem: NSMenuItem!
    private var screenMenuItems: [NSMenuItem] = []
    // ── Janela dos sugestores de notícias (desativada) ──
    /*
    private var suggestersWindow: NSWindow?
    */
    private var settingsWindow: NSWindow?
    private var cancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Sem ícone no Dock; o app vive na menu bar.
        NSApp.setActivationPolicy(.accessory)
        print("🤖 Pynkaro — assistente de voz local para macOS")

        buildStatusItem()

        // Ícone e rótulos acompanham o estado do assistente.
        cancellable = AssistantController.shared.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                self.statusItem?.button?.image = NSImage(
                    systemSymbolName: status.symbolName,
                    accessibilityDescription: status.label
                )
                self.statusLabelItem.title = status.label
                self.pauseItem.title = (status == .paused) ? "Retomar escuta" : "Pausar escuta"
            }

        // Primeira execução: se há chave da Anthropic, direto ao trabalho.
        // Modo Umbrel (Ollama/Kokoro locais) dispensa qualquer chave paga.
        if Config.anthropicKey == nil && Config.ollamaBaseURL == nil {
            openSettings(onboarding: true)
        } else {
            AssistantController.shared.start()
        }
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: AssistantStatus.starting.symbolName,
            accessibilityDescription: "Pynkaro"
        )

        let menu = NSMenu()
        menu.autoenablesItems = false

        statusLabelItem = NSMenuItem(title: AssistantStatus.starting.label,
                                     action: nil, keyEquivalent: "")
        statusLabelItem.isEnabled = false
        menu.addItem(statusLabelItem)
        menu.addItem(.separator())

        pauseItem = NSMenuItem(title: "Pausar escuta",
                               action: #selector(togglePause), keyEquivalent: "p")
        pauseItem.target = self
        menu.addItem(pauseItem)

        // ── Item "Sugestores de notícias" (desativado) ──
        /*
        let suggestersItem = NSMenuItem(title: "Sugestores de notícias…",
                                        action: #selector(openSuggesters), keyEquivalent: "")
        suggestersItem.target = self
        menu.addItem(suggestersItem)
        */

        // Em qual monitor o avatar aparece.
        let screenMenu = NSMenu()
        screenMenu.autoenablesItems = false
        screenMenuItems = NSScreen.screens.enumerated().map { index, screen in
            let item = NSMenuItem(title: screen.localizedName,
                                  action: #selector(selectScreen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            screenMenu.addItem(item)
            return item
        }
        let screenItem = NSMenuItem(title: "Tela do avatar", action: nil, keyEquivalent: "")
        menu.addItem(screenItem)
        menu.setSubmenu(screenMenu, for: screenItem)
        updateScreenChecks()

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Configurações…",
                                      action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Sair do Pynkaro",
                                  action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    @objc private func togglePause() {
        AssistantController.shared.togglePause()
    }

    @objc private func selectScreen(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.tag, forKey: "avatarScreenIndex")
        updateScreenChecks()
    }

    private func updateScreenChecks() {
        let selected = UserDefaults.standard.integer(forKey: "avatarScreenIndex")
        for item in screenMenuItems {
            item.state = (item.tag == selected) ? .on : .off
        }
    }

    // ── Abertura da janela de sugestores (desativada) ──
    /*
    @objc private func openSuggesters() {
        if suggestersWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SuggestersView()))
            window.title = "Sugestores de notícias"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            suggestersWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        suggestersWindow?.makeKeyAndOrderFront(nil)
    }
    */

    // MARK: - Configurações / onboarding

    @objc private func openSettingsFromMenu() {
        openSettings(onboarding: false)
    }

    private func openSettings(onboarding: Bool) {
        let view = SettingsView(isOnboarding: onboarding) { [weak self] in
            self?.settingsWindow?.close()
            AssistantController.shared.start()
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = onboarding ? "Bem-vindo ao Pynkaro" : "Configurações do Pynkaro"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Janela de configurações (chaves de API)

/// Usada no onboarding (primeira execução sem chaves) e no menu Configurações.
/// As chaves são salvas no Keychain do macOS.
struct SettingsView: View {
    let isOnboarding: Bool
    var onSaved: (() -> Void)?

    @State private var mode: Int
    @State private var anthropicKey: String
    @State private var elevenLabsKey: String
    @State private var ollamaUrl: String
    @State private var kokoroUrl: String
    @State private var searxngUrl: String
    @State private var llmModel: String
    @State private var kokoroVoice: String
    @State private var wakeWordsText: String
    @State private var ollamaModels: [String] = []
    @State private var kokoroVoices: [String] = []
    @State private var showAllVoices = false

    init(isOnboarding: Bool, onSaved: (() -> Void)? = nil) {
        self.isOnboarding = isOnboarding
        self.onSaved = onSaved
        _mode = State(initialValue: Config.ollamaBaseURL == nil ? 1 : 0)
        _anthropicKey = State(initialValue: Config.anthropicKey ?? "")
        _elevenLabsKey = State(initialValue: Config.elevenLabsKey ?? "")
        _ollamaUrl = State(initialValue: Config.ollamaBaseURL ?? "")
        _kokoroUrl = State(initialValue: Config.kokoroBaseURL ?? "")
        _searxngUrl = State(initialValue: Config.searxngBaseURL ?? "")
        _llmModel = State(initialValue: Config.ollamaModel)
        _kokoroVoice = State(initialValue: Config.kokoroVoice)
        _wakeWordsText = State(initialValue: (Config.wakeWords ?? []).joined(separator: ", "))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isOnboarding {
                Text("Bem-vindo ao Pynkaro! 🦊")
                    .font(.title2).bold()
                Text("Configure como o Pynkaro deve funcionar. As chaves de API ficam no Keychain do seu Mac e nunca saem dele.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Configurações do Pynkaro").font(.headline)
            }

            // Modo de operação
            VStack(alignment: .leading, spacing: 4) {
                Text("Modo de operação").font(.subheadline).bold()
                Picker("", selection: $mode) {
                    Text("Servidor local (Umbrel)").tag(0)
                    Text("API paga (Anthropic + ElevenLabs)").tag(1)
                }
                .pickerStyle(.segmented)
                Text(mode == 0
                     ? "LLM e voz rodam na sua Umbrel (Ollama, Kokoro, SearXNG). Nenhuma chave é necessária."
                     : "LLM via Anthropic e voz via ElevenLabs. Requer chaves de API.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if mode == 0 {
                // Opções do servidor local
                VStack(alignment: .leading, spacing: 6) {
                    Text("Servidor local (Umbrel)").font(.subheadline).bold()
                    field("Ollama URL", text: $ollamaUrl, placeholder: "http://192.168.0.189:11434/v1")
                    field("Kokoro URL", text: $kokoroUrl, placeholder: "http://192.168.0.189:8880")
                    field("SearXNG URL", text: $searxngUrl, placeholder: "http://192.168.0.189:8080")
                    // Modelo — dropdown com os modelos instalados no Ollama
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Modelo").font(.caption).foregroundStyle(.secondary)
                        if ollamaModels.isEmpty {
                            TextField("qwen2.5:3b", text: $llmModel)
                        } else {
                            Picker("", selection: $llmModel) {
                                if !ollamaModels.contains(llmModel) && !llmModel.isEmpty {
                                    Text("Personalizado: \(llmModel)").tag(llmModel)
                                }
                                ForEach(ollamaModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                    }

                    // Voz Kokoro — dropdown com as vozes disponíveis (pt-BR por padrão)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Voz Kokoro").font(.caption).foregroundStyle(.secondary)
                        if kokoroVoices.isEmpty {
                            TextField("pm_alex", text: $kokoroVoice)
                        } else {
                            Picker("", selection: $kokoroVoice) {
                                if !allVoiceIds.contains(kokoroVoice) && !kokoroVoice.isEmpty {
                                    Text("Personalizado: \(kokoroVoice)").tag(kokoroVoice)
                                }
                                if showAllVoices {
                                    ForEach(organizedVoices) { voice in
                                        Text(voice.label).tag(voice.id)
                                    }
                                } else {
                                    ForEach(ptVoices, id: \.self) { voice in
                                        Text(voice).tag(voice)
                                    }
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            Toggle("Mostrar todas as vozes", isOn: $showAllVoices)
                                .font(.caption)
                                .toggleStyle(.checkbox)
                        }
                    }
                    field("Wake words (separadas por vírgula)", text: $wakeWordsText, placeholder: "pincaro, jupiter")
                }
            } else {
                // Chaves de API
                VStack(alignment: .leading, spacing: 4) {
                    Text("Chave da Anthropic (obrigatória)")
                        .font(.subheadline).bold()
                    TextField("sk-ant-...", text: $anthropicKey)
                    Link("Criar chave em console.anthropic.com",
                         destination: URL(string: "https://console.anthropic.com")!)
                        .font(.caption)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Chave da ElevenLabs (opcional)")
                        .font(.subheadline).bold()
                    TextField("Sem ela, o app usa a voz do sistema", text: $elevenLabsKey)
                    Link("Criar chave em elevenlabs.io",
                         destination: URL(string: "https://elevenlabs.io/app/settings/api-keys")!)
                        .font(.caption)
                }
            }

            Text("Chaves são salvas no Keychain; opções de servidor no config.json. Reinicie o app para aplicar.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button(isOnboarding ? "Salvar e começar" : "Salvar") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(mode == 1 && anthropicKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(20)
        .frame(width: 480)
        .onAppear { loadDynamicOptions() }
    }

    // MARK: - Opções dinâmicas (Ollama / Kokoro)

    private struct VoiceOption: Identifiable {
        let id: String
        let label: String
    }

    private var allVoiceIds: [String] { kokoroVoices }

    /// Vozes em português (prefixos pf_/pm_ do Kokoro).
    private var ptVoices: [String] {
        kokoroVoices.filter { $0.hasPrefix("pf_") || $0.hasPrefix("pm_") }
    }

    /// Todas as vozes com rótulo de idioma, pt-BR primeiro.
    private var organizedVoices: [VoiceOption] {
        kokoroVoices.map { VoiceOption(id: $0, label: voiceLabel($0)) }
            .sorted { a, b in
                let aPT = a.id.hasPrefix("p")
                let bPT = b.id.hasPrefix("p")
                if aPT != bPT { return aPT }
                return a.label < b.label
            }
    }

    private func voiceLabel(_ id: String) -> String {
        let lang: String
        switch id.prefix(2) {
        case "af", "am": lang = "Inglês (EUA)"
        case "bf", "bm": lang = "Inglês (RU)"
        case "ef", "em": lang = "Espanhol"
        case "ff": lang = "Francês"
        case "hf", "hm": lang = "Hindi"
        case "if", "im": lang = "Italiano"
        case "jf", "jm": lang = "Japonês"
        case "pf", "pm": lang = "Português (BR)"
        case "zf", "zm": lang = "Chinês"
        default: lang = "Outro"
        }
        return "\(lang) — \(id)"
    }

    private func loadDynamicOptions() {
        loadOllamaModels()
        loadKokoroVoices()
    }

    /// Lista os modelos instalados no Ollama (GET /api/tags).
    private func loadOllamaModels() {
        guard !ollamaUrl.isEmpty,
              let url = URL(string: ollamaTagsURL(ollamaUrl)) else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else { return }
            let names = models.compactMap { $0["name"] as? String }
            DispatchQueue.main.async { self.ollamaModels = names }
        }.resume()
    }

    /// Lista as vozes do Kokoro (GET /v1/audio/voices).
    private func loadKokoroVoices() {
        guard !kokoroUrl.isEmpty,
              let url = URL(string: kokoroVoicesURL(kokoroUrl)) else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let voices = json["voices"] as? [[String: Any]] else { return }
            let ids = voices.compactMap { $0["id"] as? String }
            DispatchQueue.main.async { self.kokoroVoices = ids }
        }.resume()
    }

    private func ollamaTagsURL(_ base: String) -> String {
        base.hasSuffix("/v1") ? String(base.dropLast(3)) + "/api/tags" : base + "/api/tags"
    }

    private func kokoroVoicesURL(_ base: String) -> String {
        base.hasSuffix("/v1") ? base + "/audio/voices" : base + "/v1/audio/voices"
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(placeholder, text: text)
        }
    }

    private func save() {
        // Chaves de API sempre para o Keychain (nunca em texto plano).
        Config.setAnthropicKey(anthropicKey)
        Config.setElevenLabsKey(elevenLabsKey)

        if mode == 0 {
            Config.saveUmbrelOptions(
                ollamaUrl: ollamaUrl, kokoroUrl: kokoroUrl,
                searxngUrl: searxngUrl, llmModel: llmModel,
                kokoroVoice: kokoroVoice,
                wakeWords: wakeWordsText.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty })
        } else {
            // Modo API: remove as opções locais (sem ollama_url = modo API).
            Config.saveUmbrelOptions(ollamaUrl: nil, kokoroUrl: nil,
                                     searxngUrl: nil, llmModel: nil,
                                     kokoroVoice: nil, wakeWords: nil)
        }
        onSaved?()
        // Reinicia o app para recarregar o Config (opções valem no start).
        restartApp()
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

// ── Janela dos sugestores de notícias (projeto original — desativada) ──
/*
// MARK: - Janela dos sugestores de notícias

/// Os nomes ficam em UserDefaults e o ClaudeClient os lê a cada pergunta.
struct SuggestersView: View {
    @AppStorage("newsSuggester1") private var name1 = ""
    @AppStorage("newsSuggester2") private var name2 = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quem sugeriu as notícias de hoje?")
                .font(.headline)
            TextField("Primeiro nome", text: $name1)
            TextField("Segundo nome", text: $name2)
            Text("Usados quando alguém pergunta \"quem sugeriu essas notícias?\". As mudanças valem já na próxima pergunta.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .textFieldStyle(.roundedBorder)
        .padding(20)
        .frame(width: 340)
    }
}
*/
