import AppKit
import AVFoundation
import SwiftUI
import FluidAudio

struct SettingsView: View {
    var model: AppModel
    var modelManager: ModelManager
    @State private var recordingHotkey = false
    @State private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var axTrusted = PasteService.isAccessibilityTrusted

    private let languages: [(code: String, name: String)] = [
        ("en", "English"), ("tl", "Filipino (Tagalog)"), ("es", "Spanish"), ("fr", "French"),
        ("de", "German"), ("it", "Italian"), ("pt", "Portuguese"), ("ja", "Japanese"),
        ("ko", "Korean"), ("zh", "Chinese"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionCard(title: "Dictation") {
                    row("Language") {
                        Picker("", selection: bind(\.language)) {
                            ForEach(languages, id: \.code) { Text($0.name).tag($0.code) }
                        }.labelsHidden().frame(width: 190)
                    }
                    divider
                    row("Mode") {
                        Picker("", selection: bind(\.task)) {
                            Text("Transcribe").tag(DictationTask.transcribe)
                            Text("Translate to English").tag(DictationTask.translate)
                        }.labelsHidden().frame(width: 190)
                    }
                    divider
                    row("Paste into the focused app") { Toggle("", isOn: bind(\.pasteAfterTranscription)).labelsHidden() }
                    divider
                    row("Play sounds") { Toggle("", isOn: bind(\.playSounds)).labelsHidden() }
                }

                SectionCard(title: "Hotkey",
                            footer: AppComposition.hotkey.registrationError,
                            footerIsError: AppComposition.hotkey.registrationError != nil) {
                    row("Shortcut") {
                        Button { recordingHotkey = true } label: {
                            HotkeyChip(text: recordingHotkey ? "Press keys…" : model.settings.hotkey.displayString,
                                       pulsing: recordingHotkey)
                        }
                        .buttonStyle(.plain)
                        .background(HotkeyRecorder(isRecording: $recordingHotkey) { spec in
                            model.settings.hotkey = spec
                            AppComposition.hotkey.register(spec)
                        })
                    }
                    if recordingHotkey {
                        Text("Use ⌘ ⌥ ⌃ ⇧ + a key · Esc cancels")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.top, 4)
                    }
                    divider
                    row("Behavior") {
                        Picker("", selection: bind(\.hotkeyMode)) {
                            Text("Toggle").tag(HotkeyMode.toggle)
                            Text("Push to talk").tag(HotkeyMode.pushToTalk)
                        }.pickerStyle(.segmented).labelsHidden().frame(width: 190)
                    }
                }

                SectionCard(title: "Dictation bar") {
                    HStack(spacing: 10) {
                        ForEach(HUDPosition.allCases, id: \.self) { pos in
                            HUDPositionPreview(position: pos, selected: model.settings.hudPosition == pos)
                                .onTapGesture {
                                    model.settings.hudPosition = pos
                                    AppComposition.hud.clearSavedPositions()
                                }
                        }
                    }
                }

                SectionCard(title: "Models") {
                    modelRow("Parakeet — fast English", state: modelManager.parakeetV2) {
                        Task { await modelManager.downloadParakeet(.v2) }
                    }
                    divider
                    modelRow("Parakeet — European languages", state: modelManager.parakeetV3) {
                        Task { await modelManager.downloadParakeet(.v3) }
                    }
                    divider
                    modelRow("Whisper — all languages + translate", state: modelManager.whisperLargeTurbo) {
                        Task { await modelManager.downloadWhisper() }
                    }
                }

                SectionCard(title: "Permissions") {
                    permissionRow("Microphone",
                                  granted: micGranted,
                                  grantedHint: "Connected ✓",
                                  pendingHint: "Bulong needs your mic to hear you") {
                        Task { micGranted = await AudioService.requestMicPermission() }
                    }
                    divider
                    permissionRow("Accessibility",
                                  granted: axTrusted,
                                  grantedHint: "Granted ✓ — pastes into any app",
                                  pendingHint: "Lets Bulong type the result where you're working") {
                        PasteService.requestAccessibility()
                    }
                }

                Text("Bulong — Tagalog for “whisper.” Transcription runs entirely on this Mac; the only network use is downloading models above. Includes NVIDIA Parakeet, © NVIDIA, CC-BY-4.0.")
                    .font(Theme.Fonts.caption).foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 4)
            }
            .padding(20)
        }
        .background(Theme.ink0)
        .onAppear { modelManager.refresh() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
                axTrusted = PasteService.isAccessibilityTrusted
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1).padding(.vertical, 8)
    }

    private func row(_ title: String, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            Text(title).font(Theme.Fonts.body).foregroundStyle(Theme.textPrimary)
            Spacer()
            control().accessibilityLabel(title)
        }
    }

    private func modelRow(_ title: String, state: ModelManager.DownloadState,
                          download: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(Theme.Fonts.body).foregroundStyle(Theme.textPrimary).layoutPriority(1)
            Spacer()
            switch state {
            case .ready:
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .font(Theme.Fonts.caption).foregroundStyle(Theme.accent)
            case .notDownloaded:
                Button("Download", action: download).buttonStyle(HoverButtonStyle())
            case .downloading(let p):
                HStack(spacing: 8) {
                    ProgressView(value: p).frame(width: 90)
                    Text("\(Int(p * 100))%").font(Theme.Fonts.mono(10.5)).foregroundStyle(Theme.textSecondary)
                }
            case .failed(let msg):
                VStack(alignment: .trailing, spacing: 2) {
                    Text(msg).font(Theme.Fonts.caption).foregroundStyle(Theme.failure).lineLimit(1)
                        .help(msg)
                    Button("Retry", action: download).buttonStyle(HoverButtonStyle())
                }
            }
        }
    }

    private func permissionRow(_ title: String, granted: Bool, grantedHint: String,
                               pendingHint: String, request: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Fonts.body).foregroundStyle(Theme.textPrimary)
                Text(granted ? grantedHint : pendingHint)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(granted ? Theme.accent : Theme.textTertiary)
            }
            Spacer()
            if !granted { Button("Grant", action: request).buttonStyle(HoverButtonStyle()) }
        }
    }

    private func bind<T>(_ keyPath: ReferenceWritableKeyPath<SettingsStore, T>) -> Binding<T> {
        Binding(get: { model.settings[keyPath: keyPath] }, set: { model.settings[keyPath: keyPath] = $0 })
    }
}

/// Miniature screen showing where the HUD pill sits for a preset.
struct HUDPositionPreview: View {
    let position: HUDPosition
    let selected: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: alignment) {
                RoundedRectangle(cornerRadius: 6).fill(Theme.ink2)
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(selected ? Theme.accent : Theme.hairlineStrong, lineWidth: selected ? 1.5 : 1))
                Capsule().fill(selected ? Theme.accent : Theme.waveInactive)
                    .frame(width: 26, height: 7)
                    .padding(6)
            }
            .frame(width: 92, height: 58)
            Text(position.label)
                .font(Theme.Fonts.caption)
                .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
        }
        .contentShape(Rectangle())
        .animation(Theme.easeFast, value: selected)
    }

    private var alignment: Alignment {
        switch position {
        case .bottomCenter: .bottom
        case .topRight: .topTrailing
        case .nearNotch: .top
        }
    }
}

struct HotkeyRecorder: NSViewRepresentable {
    @Binding var isRecording: Bool
    var onCapture: (HotkeySpec) -> Void

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        if isRecording && context.coordinator.monitor == nil {
            context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let carbonMods = Self.carbonFlags(from: event.modifierFlags)
                if carbonMods != 0 || event.keyCode == 53 {
                    if event.keyCode != 53 {
                        onCapture(HotkeySpec(keyCode: UInt32(event.keyCode), carbonModifiers: carbonMods))
                    }
                    Task { @MainActor in
                        isRecording = false
                    }
                    context.coordinator.stop()
                    return nil
                }
                return event
            }
        } else if !isRecording {
            context.coordinator.stop()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        var monitor: Any?

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    static func carbonFlags(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= 0x0100 }
        if flags.contains(.shift) { carbon |= 0x0200 }
        if flags.contains(.option) { carbon |= 0x0800 }
        if flags.contains(.control) { carbon |= 0x1000 }
        return carbon
    }
}
