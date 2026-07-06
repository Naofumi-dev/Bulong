import AppKit
import SwiftUI

struct MenuPopoverView: View {
    var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            primaryAction
            if case .recording(let started) = model.state { recordingStrip(started: started) }
            if !model.lastTranscript.isEmpty { transcriptCard }
            Divider().overlay(Theme.hairline)
            footer
        }
        .padding(14)
        .frame(width: 300)
        .background(Theme.ink0)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isLive ? Theme.accent : Theme.textTertiary)
                .frame(width: 7, height: 7)
            Text("bulong").font(Theme.Fonts.mono(14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(stateText).font(Theme.Fonts.caption)
                .foregroundStyle(isFailed ? Theme.failure : Theme.textSecondary)
                .lineLimit(1)
        }
    }

    private var primaryAction: some View {
        Button {
            Task { await model.toggleDictation() }
        } label: {
            HStack {
                Image(systemName: isRecording ? "stop.fill" : "mic.fill").font(Theme.Fonts.caption)
                Text(isRecording ? "Stop and transcribe" : "Start dictation")
                    .font(Theme.Fonts.bodyStrong)
                Spacer()
                if !isRecording { HotkeyChip(text: model.settings.hotkey.displayString) }
            }
            .foregroundStyle(isRecording ? Theme.textPrimary : Theme.ink0)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: Theme.radiusControl + 2)
                .fill(isRecording ? Theme.ink2 : Theme.accent))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusControl + 2)
                .stroke(isRecording ? Theme.accentDim : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func recordingStrip(started: Date) -> some View {
        HStack(spacing: 8) {
            LevelBars(level: AppComposition.audio.level, active: true)
            TimelineView(.periodic(from: started, by: 0.5)) { context in
                Text(elapsed(from: started, now: context.date))
                    .font(Theme.Fonts.mono(11)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Text("Esc to cancel").font(Theme.Fonts.caption).foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 4)
    }

    private var transcriptCard: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(model.lastTranscript, forType: .string)
            copied = true
            Task { try? await Task.sleep(for: .seconds(1.2)); copied = false }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.lastTranscript)
                    .font(Theme.Fonts.mono(11.5)).foregroundStyle(Theme.textSecondary)
                    .lineLimit(2).multilineTextAlignment(.leading)
                Text(copied ? "Copied ✓" : "Click to copy")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(copied ? Theme.accent : Theme.textTertiary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.radiusControl + 2).fill(Theme.ink1))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusControl + 2).stroke(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .animation(Theme.easeFast, value: copied)
    }

    private var footer: some View {
        HStack(spacing: 2) {
            Button("History") { openMain() }.buttonStyle(HoverButtonStyle())
            Button("Settings") { openMain() }.buttonStyle(HoverButtonStyle())
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }.buttonStyle(HoverButtonStyle())
        }
    }

    private func openMain() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    private var isRecording: Bool { if case .recording = model.state { true } else { false } }
    private var isFailed: Bool { if case .failed = model.state { true } else { false } }
    private var isLive: Bool {
        switch model.state { case .recording, .transcribing, .inserting: true; default: false }
    }
    private var stateText: String {
        switch model.state {
        case .idle: "\(model.settings.language.uppercased()) · on-device"
        case .recording: "Listening"
        case .transcribing: "Transcribing…"
        case .inserting: "Inserting…"
        case .failed(let m): m
        }
    }
    private func elapsed(from start: Date, now: Date) -> String {
        let s = Int(now.timeIntervalSince(start))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
