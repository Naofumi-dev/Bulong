import Foundation
import Observation
import os.log
@preconcurrency import AVFoundation

private struct UncheckedAudioStream: @unchecked Sendable {
    let stream: AsyncStream<AVAudioPCMBuffer>
}

@MainActor @Observable
final class AppModel {
    /// Pipeline diagnostics. State labels and failure reasons only —
    /// transcript text is NEVER logged.
    private static let log = Logger(subsystem: "com.armageddonvivas.Bulong", category: "dictation")

    private(set) var state: DictationState = .idle {
        didSet {
            Self.log.info("state → \(self.state.logLabel, privacy: .public)")
            onStateChange?(state)
        }
    }
    private(set) var lastPartial: String = ""
    private(set) var lastTranscript: String = ""
    private(set) var statusDetail: String = ""
    var onPartial: ((String) -> Void)?
    var onStateChange: ((DictationState) -> Void)?

    let settings: SettingsStore
    let history: HistoryStore

    private let engineProvider: (EngineRoute) -> any TranscriptionEngine
    private let audioStart: @MainActor () throws -> AsyncStream<AVAudioPCMBuffer>
    private let audioStop: @MainActor () -> Void
    private let captureTarget: @MainActor () -> Void
    private let insertText: @MainActor (String) async -> InsertionResult
    private let copyText: @MainActor (String) -> Void
    private let frontmostAppName: @MainActor () -> String
    private let canDictate: @MainActor () -> Bool
    private let onDictationBlocked: @MainActor () -> Void
    private let minimumDuration: TimeInterval
    private let watchdogSeconds: TimeInterval

    private var activeEngine: (any TranscriptionEngine)?
    private var dictationTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var recordingStarted: Date?
    private var isStarting = false
    private var clipboardOnlyRun = false
    private var targetAppName: String = ""
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        settings: SettingsStore,
        history: HistoryStore,
        engineProvider: @escaping (EngineRoute) -> any TranscriptionEngine,
        audioStart: @escaping @MainActor () throws -> AsyncStream<AVAudioPCMBuffer>,
        audioStop: @escaping @MainActor () -> Void,
        captureTarget: @escaping @MainActor () -> Void = {},
        insertText: @escaping @MainActor (String) async -> InsertionResult,
        copyText: @escaping @MainActor (String) -> Void = { _ in },
        frontmostAppName: @escaping @MainActor () -> String,
        canDictate: @escaping @MainActor () -> Bool = { true },
        onDictationBlocked: @escaping @MainActor () -> Void = {},
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
        self.canDictate = canDictate
        self.onDictationBlocked = onDictationBlocked
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
        // Reentrancy guard: `state` stays .idle across the engine.isReady
        // suspension below, so a second trigger arriving in that window would
        // pass toggleDictation's state check and start a second audio tap —
        // installTap on a bus that already has one is an uncatchable crash.
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        guard canDictate() else {
            onDictationBlocked()
            return
        }

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

        // Start capture BEFORE claiming to record: a mic-permission problem
        // must surface as a clear failure, never as a silent empty recording.
        let stream: AsyncStream<AVAudioPCMBuffer>
        do {
            stream = try audioStart()
        } catch {
            Self.log.error("audio start failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(message: error.localizedDescription)
            return
        }

        activeEngine = engine
        targetAppName = frontmostAppName()
        recordingStarted = Date()
        lastPartial = ""
        statusDetail = ""
        state = .recording(started: recordingStarted!)

        let audio = UncheckedAudioStream(stream: stream)
        let options = currentOptions()
        dictationTask = Task { [weak self, audio] in
            await self?.runPipeline(engine: engine, audio: audio.stream, options: options)
        }

        // Warm the model WHILE the user speaks so stop → transcript is fast
        // even on a cold launch. Idempotent per engine; never downloads here
        // (isReady guarded above). Progress feeds the HUD's detail line so a
        // cold load reads as loading, not as a hang.
        Task { @MainActor [weak self] in
            guard let self else { return }
            let handleProgress: @Sendable (Double) -> Void = { [weak self] fraction in
                Task { @MainActor in
                    self?.noteModelLoadProgress(fraction)
                }
            }
            try? await engine.prepare(options: options, progress: handleProgress)
            self.clearStaleModelLoadStatus()
        }
    }

    private static let modelLoadPrefix = "Loading speech model"

    private func noteModelLoadProgress(_ fraction: Double) {
        guard fraction < 1 else {
            clearStaleModelLoadStatus()
            return
        }
        switch state {
        case .recording, .transcribing:
            statusDetail = "\(Self.modelLoadPrefix)… \(Int(fraction * 100))%"
        default:
            break
        }
    }

    private func clearStaleModelLoadStatus() {
        if statusDetail.hasPrefix(Self.modelLoadPrefix) {
            statusDetail = ""
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
        startWatchdog(recordedSeconds: Date().timeIntervalSince(started))
    }

    func cancelDictation(reason: String = "") async {
        statusDetail = ""
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

            // Cancelling this task makes the update stream's `next()` return
            // nil — it does NOT throw CancellationError — so a cancelled run
            // falls out of the loop with no final text. cancelDictation has
            // already set the intended state (.idle, or .failed with its own
            // reason); bail before the empty-transcript guard clobbers it
            // with a spurious "No speech detected."
            if Task.isCancelled { return }

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
            Self.log.info("insertion: \(Self.describe(result), privacy: .public)")
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
            Self.log.error("pipeline error: \(error.localizedDescription, privacy: .public)")
            finish(.failed(message: error.localizedDescription))
        }
    }

    private func finish(_ newState: DictationState) {
        watchdogTask?.cancel()
        watchdogTask = nil
        if case .failed = newState { statusDetail = "" }
        state = newState
        lastPartial = ""
        activeEngine = nil
        dictationTask = nil
        resumeIdleWaiters()
    }

    private func startWatchdog(recordedSeconds: TimeInterval) {
        let deadline = Self.watchdogDeadline(base: watchdogSeconds, recordedSeconds: recordedSeconds)
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(deadline))
            guard !Task.isCancelled else { return }
            await self?.cancelIfStillTranscribing()
        }
    }

    /// A fixed watchdog kills legitimate long recordings: a 60s+ dictation on
    /// a cold model load can genuinely need more than 60s of processing. Scale
    /// the deadline with what was recorded; the base stays the floor.
    static func watchdogDeadline(base: TimeInterval, recordedSeconds: TimeInterval) -> TimeInterval {
        max(base, 20 + recordedSeconds * 1.5)
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
