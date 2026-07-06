import AppKit
import AVFoundation
import Foundation

@MainActor
final class AppModel: ObservableObject {
    enum RunState: Equatable {
        case idle
        case recording(Date)
        case transcribing
        case failed(String)
    }

    struct LanguageChoice: Identifiable {
        let id: String
        let label: String
    }

    private enum DefaultsKey {
        static let whisperPath = "whisperPath"
        static let modelName = "modelName"
        static let taskName = "taskName"
        static let languageCode = "languageCode"
        static let pasteAfterTranscription = "pasteAfterTranscription"
    }

    private let defaults = UserDefaults.standard
    private let recorder = AudioRecorderService()
    private let hotKey = GlobalHotKey()
    private let inserter = TextInserter()

    @Published private(set) var state: RunState = .idle
    @Published private(set) var statusText = "Ready"
    @Published private(set) var lastTranscript = ""

    @Published var whisperPath = WhisperLocator.defaultWhisperExecutable() {
        didSet { defaults.set(whisperPath, forKey: DefaultsKey.whisperPath) }
    }

    @Published var modelName = "base.en" {
        didSet { defaults.set(modelName, forKey: DefaultsKey.modelName) }
    }

    @Published var taskName = WhisperTask.transcribe.rawValue {
        didSet {
            if taskName == WhisperTask.translate.rawValue && (modelName.hasSuffix(".en") || modelName == "turbo") {
                modelName = "small"
            }
            defaults.set(taskName, forKey: DefaultsKey.taskName)
        }
    }

    @Published var languageCode = "en" {
        didSet { defaults.set(languageCode, forKey: DefaultsKey.languageCode) }
    }

    @Published var pasteAfterTranscription = true {
        didSet { defaults.set(pasteAfterTranscription, forKey: DefaultsKey.pasteAfterTranscription) }
    }

    let modelChoices = [
        "tiny.en",
        "base.en",
        "small.en",
        "base",
        "small",
        "medium",
        "turbo"
    ]

    let languageChoices = [
        LanguageChoice(id: "auto", label: "Auto"),
        LanguageChoice(id: "en", label: "English"),
        LanguageChoice(id: "tl", label: "Tagalog"),
        LanguageChoice(id: "es", label: "Spanish"),
        LanguageChoice(id: "ja", label: "Japanese"),
        LanguageChoice(id: "ko", label: "Korean"),
        LanguageChoice(id: "zh", label: "Chinese"),
        LanguageChoice(id: "fr", label: "French"),
        LanguageChoice(id: "de", label: "German")
    ]

    var menuBarIconName: String {
        switch state {
        case .idle:
            return "mic"
        case .recording:
            return "mic.circle.fill"
        case .transcribing:
            return "waveform"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    var primaryActionTitle: String {
        switch state {
        case .idle, .failed:
            return "Start Recording"
        case .recording:
            return "Stop and Transcribe"
        case .transcribing:
            return "Transcribing"
        }
    }

    var primaryActionIconName: String {
        switch state {
        case .idle, .failed:
            return "record.circle"
        case .recording:
            return "stop.circle"
        case .transcribing:
            return "hourglass"
        }
    }

    init() {
        whisperPath = defaults.string(forKey: DefaultsKey.whisperPath) ?? WhisperLocator.defaultWhisperExecutable()
        modelName = defaults.string(forKey: DefaultsKey.modelName) ?? "base.en"
        taskName = defaults.string(forKey: DefaultsKey.taskName) ?? WhisperTask.transcribe.rawValue
        languageCode = defaults.string(forKey: DefaultsKey.languageCode) ?? "en"

        if defaults.object(forKey: DefaultsKey.pasteAfterTranscription) == nil {
            pasteAfterTranscription = true
        } else {
            pasteAfterTranscription = defaults.bool(forKey: DefaultsKey.pasteAfterTranscription)
        }

        registerHotKey()
    }

    func toggleRecording() {
        switch state {
        case .idle, .failed:
            requestMicrophonePermissionThenStart()
        case .recording:
            stopRecordingAndTranscribe()
        case .transcribing:
            statusText = "Transcription is still running"
        }
    }

    func copyLastTranscript() {
        guard !lastTranscript.isEmpty else { return }
        inserter.copyToClipboard(lastTranscript)
        statusText = "Copied last transcript"
    }

    func useDetectedWhisperPath() {
        whisperPath = WhisperLocator.defaultWhisperExecutable()
        statusText = "Using \(whisperPath)"
    }

    func requestMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            statusText = "Microphone is allowed"
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    self?.statusText = granted ? "Microphone is allowed" : "Microphone permission was denied"
                }
            }
        case .denied, .restricted:
            statusText = "Enable microphone access in System Settings"
        @unknown default:
            statusText = "Microphone permission state is unknown"
        }
    }

    func requestAccessibilityPermission() {
        inserter.requestAccessibilityPermission()
        statusText = "Accessibility prompt requested"
    }

    private func registerHotKey() {
        do {
            try hotKey.registerDefault { [weak self] in
                Task { @MainActor in
                    self?.toggleRecording()
                }
            }
            statusText = "Ready"
        } catch {
            state = .failed(error.localizedDescription)
            statusText = error.localizedDescription
        }
    }

    private func requestMicrophonePermissionThenStart() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startRecording()
        case .notDetermined:
            statusText = "Waiting for microphone permission"
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    if granted {
                        self?.startRecording()
                    } else {
                        self?.state = .failed("Microphone permission was denied")
                        self?.statusText = "Microphone permission was denied"
                    }
                }
            }
        case .denied, .restricted:
            state = .failed("Microphone access is off")
            statusText = "Enable microphone access in System Settings"
        @unknown default:
            state = .failed("Microphone permission state is unknown")
            statusText = "Microphone permission state is unknown"
        }
    }

    private func startRecording() {
        do {
            _ = try recorder.start()
            state = .recording(Date())
            statusText = "Recording"
        } catch {
            state = .failed(error.localizedDescription)
            statusText = error.localizedDescription
        }
    }

    private func stopRecordingAndTranscribe() {
        guard let audioURL = recorder.stop() else {
            state = .idle
            statusText = "No active recording"
            return
        }

        let transcriber = WhisperTranscriber(executablePath: whisperPath)
        let task = WhisperTask(rawValue: taskName) ?? .transcribe
        let language = languageCode == "auto" ? nil : languageCode
        let options = WhisperOptions(
            model: modelName,
            task: task,
            language: language,
            searchPath: WhisperLocator.defaultSearchPath
        )

        state = .transcribing
        statusText = "Transcribing with \(modelName)"

        Task {
            do {
                let transcript = try await transcriber.transcribe(audioURL: audioURL, options: options)
                await MainActor.run {
                    finishTranscription(transcript)
                }
            } catch {
                await MainActor.run {
                    state = .failed(error.localizedDescription)
                    statusText = error.localizedDescription
                }
            }
        }
    }

    private func finishTranscription(_ transcript: String) {
        let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else {
            state = .idle
            statusText = "No speech detected"
            return
        }

        lastTranscript = cleaned

        if pasteAfterTranscription {
            let inserted = inserter.insert(cleaned)
            statusText = inserted ? "Pasted transcript" : "Copied transcript; Accessibility is needed to paste"
        } else {
            inserter.copyToClipboard(cleaned)
            statusText = "Copied transcript"
        }

        state = .idle
    }
}
