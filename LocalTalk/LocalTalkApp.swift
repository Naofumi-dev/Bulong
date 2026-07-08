import AppKit
import SwiftUI
@preconcurrency import AVFoundation

@main
struct LocalTalkApp: App {
    @State private var appModel: AppModel

    init() {
        MigrationService.migrateIfNeeded()
        let model = AppComposition.makeAppModel()
        _appModel = State(initialValue: model)
        AppComposition.wireHotkey(to: model)
    }

    var body: some Scene {
        MenuBarExtra("Bulong", systemImage: menuIcon) {
            MenuPopoverView(model: appModel, license: AppComposition.license)
        }
        .menuBarExtraStyle(.window)

        Window("Bulong", id: "main") {
            MainWindowView(model: appModel,
                           modelManager: AppComposition.modelManager,
                           license: AppComposition.license)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 760, height: 500)
    }

    private var menuIcon: String {
        switch appModel.state {
        case .idle:
            // Trial expired: a lock reads "buy to unlock" — always-visible feedback
            // right where a menu-bar app lives. Flips via @Observable on state change.
            AppComposition.license.canDictate ? "waveform" : "lock.circle"
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
    static let license = LicenseService()
    static let modelManager = ModelManager()
    static let paste = PasteService()
    static let settings = SettingsStore()
    static let uiState = UIState()
    static let whisperEngine = WhisperKitEngine()
    static var onboardingWindow: NSWindow?
    private static var onboardingCloseObserver: NSObjectProtocol?

    static func makeAppModel() -> AppModel {
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
            copyText: { text in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            },
            frontmostAppName: {
                paste.targetAppName
            },
            canDictate: {
                // Refresh first so a trial that expires mid-session gates live.
                license.refresh()
                return license.canDictate
            },
            onDictationBlocked: {
                // Surface the License section. The global hotkey has no SwiftUI
                // window/environment context to reach `openWindow`, so we set the
                // section (the main window lands on License if/when it opens) and
                // let the popover's "Trial ended" status line prompt the user —
                // per the plan, no brittle AppKit window plumbing.
                uiState.mainSection = .settings
            }
        )
    }

    static func wireHotkey(to model: AppModel) {
        paste.isOnboardingActive = { onboardingWindow?.isVisible == true }
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
                hotkey.resetSingleKey()   // resync the trigger after a failure/watchdog
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
                hotkey.resetSingleKey()   // cancel/stop landed us idle — clear any half-open tap
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
        applyTrigger(for: model)
    }

    /// Registers whichever trigger the user picked. Combo → the Carbon hotkey
    /// (and the single-key monitor is stopped); Single key → the combo is
    /// unregistered and the NSEvent monitor drives dictation via a start/stop
    /// pulse, watching the device-mask for the user's chosen key. Escape
    /// (registered per state change) stays live in both modes. Re-run by the
    /// Settings pickers when `triggerKind` or `singleKeyChoice` changes.
    static func applyTrigger(for model: AppModel) {
        switch model.settings.triggerKind {
        case .combo:
            hotkey.stopSingleKeyMonitor()
            hotkey.register(model.settings.hotkey)
        case .singleKey:
            hotkey.unregisterPrimaryCombo()
            hotkey.singleKeyMask = model.settings.singleKeyChoice.deviceMask
            hotkey.onSingleKeyAction = { [weak model] action in
                guard let model else { return }
                Task { @MainActor in
                    switch action {
                    case .start, .stop:
                        // start pulse: idle→record; stop pulse: record→stop
                        await model.toggleDictation()
                    case .none:
                        break
                    }
                }
            }
            hotkey.startSingleKeyMonitor()
        }
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
            window.title = "Welcome to Bulong"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.backgroundColor = NSColor(Theme.ink0)
            window.center()
            window.isReleasedWhenClosed = false
            onboardingWindow = window
            // Any close path (Finish or the close button) releases the window
            // reference here, which also tears down the hosting view and its
            // 1.5s permission poll.
            onboardingCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    onboardingWindow = nil
                    if let token = onboardingCloseObserver {
                        NotificationCenter.default.removeObserver(token)
                        onboardingCloseObserver = nil
                    }
                }
            }
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
            onDragChanged: { _ in AppComposition.hud.dragChanged() },
            onDragEnded: { AppComposition.hud.finishDrag() }
        )
    }
}
