import AppKit
import FluidAudio
import SwiftUI

struct SettingsView: View {
    var model: AppModel
    var modelManager: ModelManager
    @State private var recordingHotkey = false

    private let languages: [(code: String, name: String)] = [
        ("en", "English"),
        ("tl", "Filipino (Tagalog)"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("zh", "Chinese"),
    ]

    var body: some View {
        Form {
            Section("Dictation") {
                Picker("Language", selection: languageBinding) {
                    ForEach(languages, id: \.code) { language in
                        Text(language.name).tag(language.code)
                    }
                }

                Picker("Mode", selection: taskBinding) {
                    Text("Transcribe").tag(DictationTask.transcribe)
                    Text("Translate to English").tag(DictationTask.translate)
                }

                Toggle("Paste into the focused app", isOn: pasteBinding)
                Toggle("Play sounds", isOn: soundsBinding)
            }

            Section("Hotkey") {
                LabeledContent("Shortcut") {
                    Button(recordingHotkey ? "Press keys..." : model.settings.hotkey.displayString) {
                        recordingHotkey = true
                    }
                    .background(
                        HotkeyRecorder(isRecording: $recordingHotkey) { spec in
                            model.settings.hotkey = spec
                            AppComposition.hotkey.register(spec)
                        }
                    )
                }

                Picker("Behavior", selection: hotkeyModeBinding) {
                    Text("Toggle: press to start, press to stop").tag(HotkeyMode.toggle)
                    Text("Push to talk: hold while speaking").tag(HotkeyMode.pushToTalk)
                }

                if let error = AppComposition.hotkey.registrationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Theme.failure)
                }
            }

            Section("Models") {
                modelRow("Parakeet: fast English", state: modelManager.parakeetV2) {
                    Task { await modelManager.downloadParakeet(.v2) }
                }
                modelRow("Parakeet: European languages", state: modelManager.parakeetV3) {
                    Task { await modelManager.downloadParakeet(.v3) }
                }
                modelRow("Whisper: all languages and translate", state: modelManager.whisperLargeTurbo) {
                    Task { await modelManager.downloadWhisper() }
                }
            }

            Section("Permissions") {
                LabeledContent("Microphone") {
                    Button("Request") {
                        Task { _ = await AudioService.requestMicPermission() }
                    }
                }

                LabeledContent("Accessibility for auto-paste") {
                    Button(PasteService.isAccessibilityTrusted ? "Granted" : "Request") {
                        PasteService.requestAccessibility()
                    }
                    .disabled(PasteService.isAccessibilityTrusted)
                }
            }

            Section {
                Text("Includes NVIDIA Parakeet, © NVIDIA, CC-BY-4.0. Transcription runs entirely on this Mac; the only network use is downloading models above.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.root)
        .navigationTitle("Settings")
        .onAppear {
            modelManager.refresh()
        }
    }

    private func modelRow(
        _ title: String,
        state: ModelManager.DownloadState,
        download: @escaping () -> Void
    ) -> some View {
        LabeledContent(title) {
            switch state {
            case .ready:
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .notDownloaded:
                Button("Download", action: download)
            case .downloading(let progress):
                ProgressView(value: progress)
                    .frame(width: 120)
            case .failed(let message):
                Button("Retry: \(message)", action: download)
                    .foregroundStyle(Theme.failure)
            }
        }
    }

    private var languageBinding: Binding<String> {
        Binding(
            get: { model.settings.language },
            set: { model.settings.language = $0 }
        )
    }

    private var taskBinding: Binding<DictationTask> {
        Binding(
            get: { model.settings.task },
            set: { model.settings.task = $0 }
        )
    }

    private var pasteBinding: Binding<Bool> {
        Binding(
            get: { model.settings.pasteAfterTranscription },
            set: { model.settings.pasteAfterTranscription = $0 }
        )
    }

    private var soundsBinding: Binding<Bool> {
        Binding(
            get: { model.settings.playSounds },
            set: { model.settings.playSounds = $0 }
        )
    }

    private var hotkeyModeBinding: Binding<HotkeyMode> {
        Binding(
            get: { model.settings.hotkeyMode },
            set: { model.settings.hotkeyMode = $0 }
        )
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

    static func carbonFlags(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= 0x0100 }
        if flags.contains(.shift) { carbon |= 0x0200 }
        if flags.contains(.option) { carbon |= 0x0800 }
        if flags.contains(.control) { carbon |= 0x1000 }
        return carbon
    }
}
