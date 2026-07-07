import Foundation
import Observation
@preconcurrency import AVFoundation

private struct UncheckedAudioStream: @unchecked Sendable {
    let stream: AsyncStream<AVAudioPCMBuffer>
}

@MainActor @Observable
final class AppModel {
    private(set) var state: DictationState = .idle {
        didSet { onStateChange?(state) }
    }
    private(set) var lastPartial: String = ""
    private(set) var lastTranscript: String = ""
    private(set) var statusDetail: String = ""
    var onPartial: ((String) -> Void)?
    var onStateChange: ((DictationState) -> Void)?

    let settings: SettingsStore
    let history: HistoryStore

    private let engineProvider: (EngineRoute) -> any TranscriptionEngine
    private let audioStart: @MainActor () -> AsyncStream<AVAudioPCMBuffer>
    private let audioStop: @MainActor () -> Void
    private let captureTarget: @MainActor () -> Void
    private let insertText: @MainActor (String) async -> InsertionResult
    private let copyText: @MainActor (String) -> Void
    private let frontmostAppName: @MainActor () -> String
    private let minimumDuration: TimeInterval
    private let watchdogSeconds: TimeInterval

    private var activeEngine: (any TranscriptionEngine)?
    private var dictationTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var recordingStarted: Date?
    private var clipboardOnlyRun = false
    private var targetAppName: String = ""
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        settings: SettingsStore,
        history: HistoryStore,
        engineProvider: @escaping (EngineRoute) -> any TranscriptionEngine,
        audioStart: @escaping @MainActor () -> AsyncStream<AVAudioPCMBuffer>,
        audioStop: @escaping @MainActor () -> Void,
        captureTarget: @escaping @MainActor () -> Void = {},
        insertText: @escaping @MainActor (String) async -> InsertionResult,
        copyText: @escaping @MainActor (String) -> Void = { _ in },
        frontmostAppName: @escaping @MainActor () -> String,
        minimumDuration: TimeInterval = 0.4,
        watchdogSeconds: TimeInterval = 60
    ) {
        self.settings = settings
        self.history = history
        self.engineProvider = engineProvider
        self.audioStart = audioStart
        self.audioStop = audioStop
        self.captureTarget = captureTarget
        self.insertText = insertText
        self.copyText = copyText
        self.frontmostAppName = frontmostAppName
        self.minimumDuration = minimumDuration
        self.watchdogSeconds = watchdogSeconds
    }

    func toggleDictation(clipboardOnly: Bool = false) async {
        switch state {
        case .idle, .failed:
            clipboardOnlyRun = clipboardOnly
            await startDictation()
        case .recording:
            stopRecording()
        case .transcribing, .inserting:
            break
        }
    }

    private func startDictation() async {
        captureTarget()

        let route = EngineSelector.route(
            language: settings.language,
            task: settings.task,
            override: settings.engineOverride
        )
        let engine = engineProvider(route)

        guard await engine.isReady(for: currentOptions()) else {
            state = .failed(message: EngineError.modelNotDownloaded(engine.id).localizedDescription)
            return
        }

        activeEngine = engine
        targetAppName = frontmostAppName()
        recordingStarted = Date()
        lastPartial = ""
        state = .recording(started: recordingStarted!)

        let audio = UncheckedAudioStream(stream: audioStart())
        let options = currentOptions()
        dictationTask = Task { [weak self, audio] in
            await self?.runPipeline(engine: engine, audio: audio.stream, options: options)
        }
    }

    private func stopRecording() {
        guard case .recording(let started) = state else { return }

        if Date().timeIntervalSince(started) < minimumDuration {
            Task { await cancelDictation(reason: "Too short. Hold the hotkey while you speak.") }
            return
        }

        state = .transcribing
        audioStop()
        startWatchdog()
    }

    func cancelDictation(reason: String = "") async {
        audioStop()
        await activeEngine?.cancel()
        watchdogTask?.cancel()
        watchdogTask = nil
        dictationTask?.cancel()
        dictationTask = nil
        activeEngine = nil
        state = reason.isEmpty ? .idle : .failed(message: reason)
        lastPartial = ""
        resumeIdleWaiters()
    }

    private func runPipeline(
        engine: any TranscriptionEngine,
        audio: AsyncStream<AVAudioPCMBuffer>,
        options: TranscriptionOptions
    ) async {
        do {
            var finalText: String?
            let updates = engine.transcribe(audio: audio, options: options)
            for try await update in updates {
                switch update {
                case .partial(let text):
                    lastPartial = text
                    onPartial?(text)
                case .final(let text):
                    finalText = text
                }
            }

            guard let text = finalText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                finish(.failed(message: "No speech detected."))
                return
            }

            state = .inserting
            let result: InsertionResult
            if clipboardOnlyRun {
                copyText(text)
                result = .clipboardOnly(reason: "test run saved to History")
            } else if settings.pasteAfterTranscription {
                result = await insertText(text)
            } else {
                copyText(text)
                result = .clipboardOnly(reason: "Auto-paste is off")
            }

            lastTranscript = text
            statusDetail = Self.describe(result)
            try? history.append(HistoryEntry(
                id: UUID(),
                text: text,
                date: Date(),
                appName: targetAppName,
                engine: engine.id,
                language: options.language,
                durationSeconds: recordingStarted.map { Date().timeIntervalSince($0) } ?? 0
            ))
            finish(.idle)
        } catch is CancellationError {
            finish(.idle)
        } catch {
            finish(.failed(message: error.localizedDescription))
        }
    }

    private func finish(_ newState: DictationState) {
        watchdogTask?.cancel()
        watchdogTask = nil
        state = newState
        lastPartial = ""
        activeEngine = nil
        dictationTask = nil
        resumeIdleWaiters()
    }

    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self, watchdogSeconds] in
            try? await Task.sleep(for: .seconds(watchdogSeconds))
            guard !Task.isCancelled else { return }
            await self?.cancelIfStillTranscribing()
        }
    }

    private func cancelIfStillTranscribing() async {
        guard case .transcribing = state else { return }
        await cancelDictation(reason: EngineError.timedOut.localizedDescription)
    }

    private func currentOptions() -> TranscriptionOptions {
        TranscriptionOptions(language: settings.language, task: settings.task)
    }

    static func describe(_ result: InsertionResult) -> String {
        switch result {
        case .insertedDirectly:
            return "Inserted."
        case .pastedViaCmdV:
            return "Pasted via Cmd-V."
        case .clipboardOnly(let reason):
            return "Copied to clipboard: \(reason)."
        }
    }

    func waitForIdle() async {
        if dictationTask == nil { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    private func resumeIdleWaiters() {
        idleWaiters.forEach { $0.resume() }
        idleWaiters = []
    }
}
