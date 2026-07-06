import AppKit
import SwiftUI

struct MenuBarView: View {
    var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(primaryTitle) {
            Task { await model.toggleDictation() }
        }

        Text(statusLine)

        if !model.lastPartial.isEmpty {
            Text(model.lastPartial)
                .font(.caption)
        }

        Divider()

        Button("Open Bulong") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("0")

        Button("Copy Last Transcript") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(model.lastTranscript, forType: .string)
        }
        .disabled(model.lastTranscript.isEmpty)

        Divider()

        Button("Quit Bulong") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var primaryTitle: String {
        if case .recording = model.state {
            return "Stop and Transcribe"
        }
        return "Start Dictation  \(model.settings.hotkey.displayString)"
    }

    private var statusLine: String {
        switch model.state {
        case .idle:
            return "Ready: \(model.settings.language.uppercased()) on-device"
        case .recording:
            return "Listening"
        case .transcribing:
            return "Transcribing"
        case .inserting:
            return "Inserting"
        case .failed(let message):
            return message
        }
    }
}
