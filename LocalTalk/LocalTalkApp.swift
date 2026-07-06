import SwiftUI
@preconcurrency import AVFoundation

@main
struct LocalTalkApp: App {
    @State private var appModel = AppComposition.makeAppModel()

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
                    ParakeetEngine(version: .v2)
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
            insertText: { text in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                return .clipboardOnly(reason: "PasteService arrives in Task 10")
            },
            frontmostAppName: {
                NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
            }
        )
    }
}
