import SwiftUI
@preconcurrency import AVFoundation

@main
struct LocalTalkApp: App {
    @State private var appModel: AppModel

    init() {
        let model = AppComposition.makeAppModel()
        _appModel = State(initialValue: model)
        AppComposition.wireHotkey(to: model)
    }

    var body: some Scene {
        MenuBarExtra("LocalTalk", systemImage: menuIcon) {
            Text(statusLine)

            if !appModel.lastPartial.isEmpty {
                Text(appModel.lastPartial)
                    .font(.caption)
            }

            Divider()

            Button(buttonTitle) {
                Task { await appModel.toggleDictation() }
            }

            Button("Copy Last Transcript") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(appModel.lastTranscript, forType: .string)
            }
            .disabled(appModel.lastTranscript.isEmpty)

            Divider()

            Button("Quit LocalTalk") {
                NSApp.terminate(nil)
            }
                .keyboardShortcut("q")
        }
    }

    private var menuIcon: String {
        switch appModel.state {
        case .idle:
            "waveform"
        case .recording:
            "mic.circle.fill"
        case .transcribing, .inserting:
            "ellipsis.circle"
        case .failed:
            "exclamationmark.circle"
        }
    }

    private var statusLine: String {
        switch appModel.state {
        case .idle:
            "Ready"
        case .recording:
            "Listening..."
        case .transcribing:
            "Transcribing..."
        case .inserting:
            "Inserting..."
        case .failed(let message):
            message
        }
    }

    private var buttonTitle: String {
        if case .recording = appModel.state {
            return "Stop and Transcribe"
        }
        return "Start Dictation"
    }
}

@MainActor
enum AppComposition {
    static let audio = AudioService()
    static let hotkey = HotkeyService()
    static let hud = HUDPanelController()
    static let paste = PasteService()
    static let whisperEngine = WhisperKitEngine()

    static func makeAppModel() -> AppModel {
        let settings = SettingsStore()
        return AppModel(
            settings: settings,
            history: HistoryStore(),
            engineProvider: { route in
                switch route.engine {
                case .parakeet:
                    ParakeetEngine(version: route.parakeetVersion ?? .v2)
                case .whisperKit:
                    whisperEngine
                }
            },
            audioStart: {
                (try? audio.start()) ?? AsyncStream { continuation in
                    continuation.finish()
                }
            },
            audioStop: {
                audio.stop()
            },
            captureTarget: {
                paste.captureTarget()
            },
            insertText: { text in
                await paste.insert(text, alsoCopy: true)
            },
            frontmostAppName: {
                paste.targetAppName
            }
        )
    }

    static func wireHotkey(to model: AppModel) {
        model.onStateChange = { [weak model] state in
            guard let model else { return }
            switch state {
            case .recording, .transcribing:
                hotkey.registerEscape {
                    Task { @MainActor [weak model] in
                        await model?.cancelDictation()
                    }
                }
                hud.show {
                    HUDStateView(model: model)
                }
            case .inserting:
                hotkey.unregisterEscape()
                hud.show {
                    HUDStateView(model: model)
                }
            case .failed:
                hotkey.unregisterEscape()
                hud.show {
                    HUDStateView(model: model)
                }
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    await MainActor.run {
                        if case .failed = model.state {
                            hud.hide()
                        }
                    }
                }
            case .idle:
                hotkey.unregisterEscape()
                Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    await MainActor.run {
                        if case .idle = model.state {
                            hud.hide()
                        }
                    }
                }
            }
        }

        hotkey.onPressed = { [weak model] in
            guard let model else { return }
            Task { @MainActor in
                switch model.settings.hotkeyMode {
                case .toggle:
                    await model.toggleDictation()
                case .pushToTalk:
                    if case .idle = model.state {
                        await model.toggleDictation()
                    } else if case .failed = model.state {
                        await model.toggleDictation()
                    }
                }
            }
        }
        hotkey.onReleased = { [weak model] in
            guard let model else { return }
            Task { @MainActor in
                guard model.settings.hotkeyMode == .pushToTalk else { return }
                if case .recording = model.state {
                    await model.toggleDictation()
                }
            }
        }
        hotkey.register(model.settings.hotkey)
    }
}

struct HUDStateView: View {
    var model: AppModel

    var body: some View {
        HUDView(
            state: model.state,
            level: AppComposition.audio.level,
            partial: model.lastPartial,
            language: model.settings.language,
            onCancel: { Task { await model.cancelDictation() } },
            onDragChanged: { AppComposition.hud.drag(to: $0) },
            onDragEnded: { AppComposition.hud.finishDrag() }
        )
    }
}
