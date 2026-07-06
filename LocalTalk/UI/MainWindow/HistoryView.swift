import AppKit
import SwiftUI

struct HistoryView: View {
    var history: HistoryStore
    @State private var query = ""
    @State private var confirmClear = false

    private var results: [HistoryEntry] {
        history.search(query)
    }

    var body: some View {
        List(results) { entry in
            HistoryRow(entry: entry)
                .padding(.vertical, 5)
                .contextMenu {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.text, forType: .string)
                    }
                }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Theme.root)
        .searchable(text: $query, prompt: "Search transcripts")
        .overlay {
            if results.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "No transcripts yet" : "No matches",
                    systemImage: "waveform",
                    description: Text(emptyDescription)
                )
            }
        }
        .toolbar {
            Button("Export") {
                export()
            }
            .disabled(history.entries.isEmpty)

            Button("Clear", role: .destructive) {
                confirmClear = true
            }
            .disabled(history.entries.isEmpty)
        }
        .confirmationDialog("Delete all transcripts?", isPresented: $confirmClear) {
            Button("Delete All", role: .destructive) {
                try? history.clear()
            }
        }
        .navigationTitle("History")
    }

    private var emptyDescription: String {
        if query.isEmpty {
            return "Press \(AppComposition.hotkeyDisplay) in any app to dictate."
        }
        return "Try a different word or phrase."
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Bulong-transcripts.txt"
        if panel.runModal() == .OK, let url = panel.url {
            try? history.exportPlainText().write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

private struct HistoryRow: View {
    var entry: HistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(entry.text)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white)
                .lineLimit(3)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                Text(entry.appName)
                Text(entry.date, style: .time)
                    .monospacedDigit()
                Text(entry.engine.rawValue)
                    .foregroundStyle(Theme.accentText)
                Text(entry.language.uppercased())
                    .foregroundStyle(Theme.textSecondary)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 2)
    }
}
