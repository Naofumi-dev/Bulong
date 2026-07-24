import AppKit
import SwiftUI

struct MenuPopoverView: View {
    var model: AppModel
    var license: LicenseService
    @Environment(\.openWindow) private var openWindow
    @State private var copied = false
    @State private var copyResetTask: Task<Void, Never>?

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
        .frame(width: 324)
        .background(VisualEffectBackground(material: .popover).overlay(Theme.ink0))
        .preferredColorScheme(.light)
        .tint(Theme.accent)
        // Re-derive so the "Trial ended" status line is accurate on open, not
        // stale until the first hotkey press.
        .onAppear { license.refresh() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isLive ? Theme.accent : Theme.textTertiary)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text("Bulong").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(stateText).font(Theme.Fonts.mono(12))
                .foregroundStyle(isFailed || trialEnded ? Theme.failure : Theme.textSecondary)
                .lineLimit(1)
                .help(stateText)
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
                if !isRecording {
                    // The chip is the teachable moment — it must never truncate.
                    HotkeyChip(text: model.settings.activeTriggerLabel)
                        .fixedSize()
                        .layoutPriority(1)
                }
            }
            // Fixed content height: the chip is taller than bare text, and the
            // primary button must not change size between states.
            .frame(height: 22)
            .foregroundStyle(isRecording ? Theme.textPrimary : .white)
            .padding(.horizontal, 12).padding(.vertical, 8)
            // Standalone primary CTA = capsule (see Theme shape grammar).
            .background(Capsule().fill(isRecording ? Theme.ink2 : Theme.accent))
            .overlay(Capsule().stroke(isRecording ? Theme.accentDim : .clear, lineWidth: 1))
        }
        .buttonStyle(TactilePressStyle())
    }

    private func recordingStrip(started: Date) -> some View {
        HStack(spacing: 8) {
            LevelBars(level: AppComposition.audio.level, active: true)
                .accessibilityHidden(true)
            TimelineView(.periodic(from: started, by: 0.5)) { context in
                Text(elapsed(from: started, now: context.date))
                    .font(Theme.Fonts.mono(12)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            // No trailing inset: ends on the card's right rail with the
            // header status text and Quit.
            Text("Esc to cancel").font(Theme.Fonts.caption).foregroundStyle(Theme.textTertiary)
        }
        .padding(.leading, 4)
    }

    private var transcriptCard: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(model.lastTranscript, forType: .string)
            copied = true
            copyResetTask?.cancel()
            copyResetTask = Task {
                try? await Task.sleep(for: .seconds(1.2))
                if !Task.isCancelled { copied = false }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.lastTranscript)
                    .font(Theme.Fonts.mono(12.5)).foregroundStyle(Theme.textSecondary)
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
            Button("History") { openMain(.history) }.buttonStyle(HoverButtonStyle())
            Button("Settings") { openMain(.settings) }.buttonStyle(HoverButtonStyle())
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(HoverButtonStyle())
                .keyboardShortcut("q")
        }
        // Cancel the hover-pill insets so History's and Quit's *text* sit on
        // the card rails; the pills overhang into the popover padding.
        .padding(.horizontal, -8)
    }

    private func openMain(_ section: MainSection) {
        AppComposition.uiState.mainSection = section
        openWindow(id: "main")
        NSApp.activate()
        if !NSApp.isActive {
            NSRunningApplication.current.activate()
        }
    }

    private var isRecording: Bool { if case .recording = model.state { true } else { false } }
    private var isFailed: Bool { if case .failed = model.state { true } else { false } }
    /// Idle + gated: the trial has ended. Status line only — Buy lives in Settings.
    private var trialEnded: Bool {
        if case .idle = model.state { return !license.canDictate }
        return false
    }
    private var isLive: Bool {
        switch model.state { case .recording, .transcribing, .inserting: true; default: false }
    }
    private var stateText: String {
        switch model.state {
        case .idle: trialEnded ? "Trial ended — buy to continue" : "\(model.settings.language.uppercased()) · on-device"
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
