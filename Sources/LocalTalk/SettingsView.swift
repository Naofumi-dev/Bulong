import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Transcription") {
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
            }

            Section("Whisper") {
                TextField("Executable", text: $model.whisperPath)
                    .textFieldStyle(.roundedBorder)

                Button("Use Detected Executable") {
                    model.useDetectedWhisperPath()
                }
            }

            Section("Permissions") {
                Button("Microphone") {
                    model.requestMicrophonePermission()
                }

                Button("Accessibility") {
                    model.requestAccessibilityPermission()
                }
            }

            if !model.lastTranscript.isEmpty {
                Section("Last Transcript") {
                    ScrollView {
                        Text(model.lastTranscript)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 80, maxHeight: 160)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 520)
    }
}
