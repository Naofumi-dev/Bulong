import AppKit
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
            MenuBarView(model: appModel)
        }

        Window("LocalTalk", id: "main") {
            MainWindowView(model: appModel, modelManager: AppComposition.modelManager)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 760, height: 500)
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

}

@MainActor
enum AppComposition {
    static let audio = AudioService()
    static let hotkey = HotkeyService()
    static let hud = HUDPanelController()
    static let modelManager = ModelManager()
    static let paste = PasteService()
    static let whisperEngine = WhisperKitEngine()
    static var onboardingWindow: NSWindow?

    static var hotkeyDisplay: String {
        SettingsStore().hotkey.displayString
    }

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
        showOnboardingIfNeeded(for: model)

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

    private static func showOnboardingIfNeeded(for model: AppModel) {
        guard !model.settings.hasCompletedOnboarding else { return }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !model.settings.hasCompletedOnboarding, onboardingWindow == nil else { return }

            let host = NSHostingController(
                rootView: OnboardingWindowView(model: model, modelManager: modelManager)
            )
            let window = NSWindow(contentViewController: host)
            window.title = "Welcome to LocalTalk"
            window.styleMask = [.titled, .closable]
            window.center()
            window.isReleasedWhenClosed = false
            onboardingWindow = window
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
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
