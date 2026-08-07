import SwiftUI
import AppKit

/// Painel de logs (aba "Logs" das Configurações): buffer em memória,
/// botões Copiar / Abrir pasta / Limpar.
struct LogsPanel: View {
    @ObservedObject private var store = LogStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(L10n.logsButton)
                    .font(.subheadline).bold()
                Text("(erros sempre; detalhes só em modo dev)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L10n.logsCopy) { copyLogs() }
                    .disabled(store.entries.isEmpty)
                Button(L10n.logsOpenFolder) { openLogsFolder() }
                Button(L10n.logsClear) { store.clear() }
                    .disabled(store.entries.isEmpty)
            }

            if store.entries.isEmpty {
                Text(L10n.logsEmpty)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(store.entries.reversed()) { entry in
                            Text(formatted(entry))
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Text("Arquivo persistente: \(LogStore.shared.logFileURL.path)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func formatted(_ entry: LogStore.Entry) -> String {
        let time = LogStore.timeString(entry.date)
        let tag = entry.level == .error ? "ERRO" : "INFO"
        return "\(time) [\(tag)] \(entry.message)"
    }

    private func copyLogs() {
        let text = store.entries
            .map(formatted)
            .joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func openLogsFolder() {
        let dir = LogStore.shared.logsDirectoryURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }
}

/// Acesso ao formatter de horário do LogStore (evita duplicar DateFormatter).
extension LogStore {
    static func timeString(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }
}
