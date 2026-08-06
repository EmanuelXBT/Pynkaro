import AppKit

/// Janela de leitura para respostas longas do assistente.
///
/// O Pynkaro fala respostas curtas (1 frase, ~40 palavras). Quando o LLM
/// devolve uma resposta ampla (acima do limite de fala), esta janela exibe
/// o texto completo em fonte legível — o usuário lê enquanto ouve o resumo
/// falado, ou lê no próprio ritmo.
final class AnswerWindow {

    static let shared = AnswerWindow()

    private var window: NSWindow?
    private var textView: NSTextView?

    private init() {}

    /// Mostra a resposta completa em uma janela redimensionável.
    /// Não sobrepõe o avatar (fica no canto oposto).
    func show(_ text: String) {
        DispatchQueue.main.async {
            if self.window == nil {
                self.buildWindow()
            }
            self.textView?.string = text
            self.textView?.scrollToBeginningOfDocument(nil)
            self.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Esconde a janela (quando a fala termina ou nova pergunta começa).
    func hide() {
        DispatchQueue.main.async {
            self.window?.orderOut(nil)
        }
    }

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 360),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "Pynkaro — Resposta"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 380, height: 240)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 560, height: 360))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false
        text.isSelectable = true
        text.font = NSFont.systemFont(ofSize: 15)
        text.textContainerInset = NSSize(width: 12, height: 12)
        text.autoresizingMask = [.width]
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.textContainer?.widthTracksTextView = true
        scroll.documentView = text

        window.contentView = scroll
        // Canto superior direito (o avatar fica no inferior direito).
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            window.setFrameOrigin(NSPoint(
                x: frame.maxX - 560 - 16,
                y: frame.maxY - 360 - 16))
        }

        self.window = window
        self.textView = text
    }
}
