import AppKit
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Button {
            model.toggleRecording()
        } label: {
            Label(model.primaryActionTitle, systemImage: model.primaryActionIconName)
        }
        .disabled(isTranscribing)
        .keyboardShortcut(.space, modifiers: [.control, .option])

        Text(model.statusText)
            .font(.caption)
            .foregroundStyle(.secondary)

        Divider()

        Picker("Mode", selection: $model.taskName) {
            Text("Transcribe").tag(WhisperTask.transcribe.rawValue)
            Text("Translate to English").tag(WhisperTask.translate.rawValue)
        }

        Picker("Model", selection: $model.modelName) {
            ForEach(model.modelChoices, id: \.self) { modelName in
                Text(modelName).tag(modelName)
            }
        }

        Picker("Language", selection: $model.languageCode) {
            ForEach(model.languageChoices) { language in
                Text(language.label).tag(language.id)
            }
        }

        Toggle("Paste Result", isOn: $model.pasteAfterTranscription)

        Divider()

        Button {
            model.copyLastTranscript()
        } label: {
            Label("Copy Last Transcript", systemImage: "doc.on.doc")
        }
        .disabled(model.lastTranscript.isEmpty)

        Button {
            model.requestAccessibilityPermission()
        } label: {
            Label("Accessibility Permission", systemImage: "hand.raised")
        }

        SettingsLink {
            Label("Settings", systemImage: "gearshape")
        }

        Divider()

        Button {
            NSApp.terminate(nil)
        } label: {
            Label("Quit LocalTalk", systemImage: "power")
        }
    }

    private var isTranscribing: Bool {
        if case .transcribing = model.state {
            return true
        }
        return false
    }
}
