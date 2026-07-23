import AppKit
import SwiftUI

struct HistoryView: View {
    var model: AppModel
    @State private var query = ""
    @State private var confirmClear = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let results = model.history.search(query)
        VStack(spacing: 0) {
            toolbar
            if results.isEmpty {
                Spacer()
                if query.isEmpty { EmptyHistoryView(model: model) } else { noMatches }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(results) { entry in HistoryCard(entry: entry) }
                    }
                    .padding(16)
                    // Filtering slides the surviving cards into place — a mover,
                    // so it goes instant under Reduce Motion.
                    .animation(reduceMotion ? nil : Theme.easeFast, value: results.map(\.id))
                }
            }
        }
        .confirmationDialog("Delete all transcripts?", isPresented: $confirmClear) {
            Button("Delete All", role: .destructive) { try? model.history.clear() }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
                TextField("Search transcripts", text: $query)
                    .textFieldStyle(.plain)
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Theme.radiusControl + 2).fill(Theme.ink1))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusControl + 2).stroke(Theme.hairline, lineWidth: 1))

            // Counter and actions only exist once there is something to count.
            if !model.history.entries.isEmpty {
                Text("\(model.history.entries.count) transcripts · \(totalWords) words")
                    .font(Theme.Fonts.mono(11)).foregroundStyle(Theme.textTertiary)
                    .fixedSize()
                Button("Export") { export() }.buttonStyle(HoverButtonStyle())
                Button("Clear") { confirmClear = true }.buttonStyle(HoverButtonStyle())
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Theme.ink0)
        .overlay(Rectangle().fill(Theme.hairline).frame(height: 1), alignment: .bottom)
    }

    private var totalWords: Int {
        model.history.entries.reduce(0) {
            $0 + $1.text.split(whereSeparator: \.isWhitespace).count
        }
    }

    private var noMatches: some View {
        Text("No matches for “\(query)”")
            .font(Theme.Fonts.body).foregroundStyle(Theme.textTertiary)
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Bulong-transcripts.txt"
        if panel.runModal() == .OK, let url = panel.url {
            try? model.history.exportPlainText().write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

private struct HistoryCard: View {
    let entry: HistoryEntry
    @State private var hovering = false
    @State private var copied = false
    @State private var copyResetTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.text)
                .font(Theme.Fonts.mono(12.5))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(3)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                Text(entry.appName)
                Text(entry.date, format: timestampFormat)
                Text(entry.engine.displayName).foregroundStyle(Theme.accentText)
                Text(entry.language.uppercased())
                Spacer()
                Button(copied ? "Copied ✓" : "Copy") { copyEntry() }
                    .buttonStyle(.plain)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(copied ? Theme.accent : Theme.textSecondary)
                    .opacity(hovering ? 1 : 0)
            }
            .font(Theme.Fonts.mono(10.5))
            .foregroundStyle(Theme.textTertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.radiusCard).fill(hovering ? Theme.ink2 : Theme.ink1))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard)
            .stroke(hovering ? Theme.hairlineStrong : Theme.hairline, lineWidth: 1))
        .onHover { hovering = $0 }
        .animation(Theme.easeFast, value: hovering)
        .animation(Theme.easeFast, value: copied)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Copy") { copyEntry() }
    }

    private var timestampFormat: Date.FormatStyle {
        Calendar.current.isDateInToday(entry.date)
            ? .dateTime.hour().minute()
            : .dateTime.day().month().hour().minute()
    }

    private func copyEntry() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        copied = true
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            if !Task.isCancelled { copied = false }
        }
    }
}

private struct EmptyHistoryView: View {
    var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 3) {
                ForEach(0..<7, id: \.self) { i in
                    Capsule().fill(Theme.accentDim)
                        .frame(width: 3.5, height: [10, 18, 28, 22, 30, 16, 9][i])
                }
            }
            .accessibilityHidden(true)
            Text("Your transcripts will appear here")
                .font(Theme.Fonts.title).foregroundStyle(Theme.textPrimary)
            HStack(spacing: 6) {
                Text("Press").font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary)
                HotkeyChip(text: model.settings.activeTriggerLabel)
                Text("in any app to dictate").font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary)
            }
            Button {
                Task { await model.toggleDictation(clipboardOnly: true) }
            } label: {
                Text("Try it now")
                    .font(Theme.Fonts.action).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(Theme.accent))
            }
            .buttonStyle(TactilePressStyle())
        }
    }
}
