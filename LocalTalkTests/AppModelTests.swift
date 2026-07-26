import XCTest
@preconcurrency import AVFoundation
@testable import Bulong

@MainActor
final class AppModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var tmpHistory: URL!

    override func setUp() {
        defaults = UserDefaults(suiteName: "AppModelTests")!
        defaults.removePersistentDomain(forName: "AppModelTests")
        tmpHistory = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-\(UUID().uuidString).jsonl")
    }

    private func makeModel(engine: FakeEngine) -> (AppModel, AudioStub) {
        let audio = AudioStub()
        let model = AppModel(
            settings: SettingsStore(defaults: defaults),
            history: HistoryStore(fileURL: tmpHistory),
            engineProvider: { _ in engine },
            audioStart: { try audio.start() },
            audioStop: { audio.stop() },
            insertText: { _ in .insertedDirectly },
            frontmostAppName: { "TextEdit" },
            minimumDuration: 0,
            watchdogSeconds: 5
        )
        return (model, audio)
    }

    func testFullDictationFlowAppendsHistoryAndReturnsToIdle() async throws {
        let engine = FakeEngine()
        let (model, audio) = makeModel(engine: engine)

        await model.toggleDictation()
        guard case .recording = model.state else {
            return XCTFail("expected recording, got \(model.state)")
        }

        audio.emitSilence(buffers: 3)
        await model.toggleDictation()
        await model.waitForIdle()

        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(model.history.entries.first?.text, "hello world")
        XCTAssertEqual(model.lastPartial, "")
    }

    func testEngineErrorLandsInFailedStateWithMessage() async throws {
        let engine = FakeEngine()
        engine.scriptedError = EngineError.engineFailure("model exploded")
        let (model, audio) = makeModel(engine: engine)

        await model.toggleDictation()
        audio.emitSilence(buffers: 1)
        await model.toggleDictation()
        await model.waitForIdle()

        guard case .failed(let message) = model.state else {
            return XCTFail("expected failed")
        }

        XCTAssertTrue(message.contains("model exploded"))
        XCTAssertTrue(model.history.entries.isEmpty)
    }

    func testCancelWhileRecordingDiscardsWithoutTranscribing() async throws {
        let engine = FakeEngine()
        let (model, audio) = makeModel(engine: engine)

        await model.toggleDictation()
        audio.emitSilence(buffers: 2)
        await model.cancelDictation()
        await model.waitForIdle()

        XCTAssertEqual(model.state, .idle)
        XCTAssertTrue(model.history.entries.isEmpty)
        XCTAssertTrue(engine.cancelCalled)
    }

    func testPartialUpdatesAreExposed() async throws {
        let engine = FakeEngine()
        let (model, audio) = makeModel(engine: engine)
        var partials: [String] = []
        model.onPartial = { partials.append($0) }

        await model.toggleDictation()
        audio.emitSilence(buffers: 1)
        await model.toggleDictation()
        await model.waitForIdle()

        XCTAssertEqual(partials, ["hel", "hello"])
    }

    func testCaptureTargetRunsBeforeRecordingAndHistoryUsesCapturedApp() async throws {
        let engine = FakeEngine()
        let audio = AudioStub()
        var captured = false
        let model = AppModel(
            settings: SettingsStore(defaults: defaults),
            history: HistoryStore(fileURL: tmpHistory),
            engineProvider: { _ in engine },
            audioStart: { try audio.start() },
            audioStop: { audio.stop() },
            captureTarget: { captured = true },
            insertText: { _ in .insertedDirectly },
            frontmostAppName: { captured ? "Captured App" : "Wrong App" },
            minimumDuration: 0,
            watchdogSeconds: 5
        )

        await model.toggleDictation()
        audio.emitSilence(buffers: 1)
        await model.toggleDictation()
        await model.waitForIdle()

        XCTAssertEqual(model.history.entries.first?.appName, "Captured App")
    }

    func testClipboardOnlyRunSkipsInsertionButAppendsHistory() async throws {
        let engine = FakeEngine()
        let audio = AudioStub()
        var insertions: [String] = []
        var copies: [String] = []
        let model = AppModel(
            settings: SettingsStore(defaults: defaults),
            history: HistoryStore(fileURL: tmpHistory),
            engineProvider: { _ in engine },
            audioStart: { try audio.start() },
            audioStop: { audio.stop() },
            insertText: { text in
                insertions.append(text)
                return .insertedDirectly
            },
            copyText: { copies.append($0) },
            frontmostAppName: { "TextEdit" },
            minimumDuration: 0,
            watchdogSeconds: 5
        )

        await model.toggleDictation(clipboardOnly: true)
        audio.emitSilence(buffers: 1)
        await model.toggleDictation()
        await model.waitForIdle()

        XCTAssertTrue(insertions.isEmpty, "clipboard-only run must not call insertText")
        XCTAssertEqual(copies, ["hello world"], "clipboard-only run must write the clipboard exactly once")
        XCTAssertEqual(model.history.entries.first?.text, "hello world")
        XCTAssertEqual(model.state, .idle)

        // The next normal run must insert again — the flag must not stick.
        await model.toggleDictation()
        audio.emitSilence(buffers: 1)
        await model.toggleDictation()
        await model.waitForIdle()

        XCTAssertEqual(insertions, ["hello world"])
        XCTAssertEqual(copies, ["hello world"], "normal insert path must not call copyText")
    }

    func testFailedStateClearsOnNextStart() async throws {
        let engine = FakeEngine()
        engine.scriptedError = EngineError.engineFailure("boom")
        let (model, audio) = makeModel(engine: engine)

        await model.toggleDictation()
        audio.emitSilence(buffers: 1)
        await model.toggleDictation()
        await model.waitForIdle()

        engine.scriptedError = nil
        await model.toggleDictation()

        guard case .recording = model.state else {
            return XCTFail("failed state must not block a new start")
        }

        await model.cancelDictation()
    }

    func testBlockedWhenCannotDictate() async {
        var blockedCalls = 0
        let engine = FakeEngine()
        let audio = AudioStub()
        let model = AppModel(
            settings: SettingsStore(defaults: defaults),
            history: HistoryStore(fileURL: tmpHistory),
            engineProvider: { _ in engine },
            audioStart: { try audio.start() },
            audioStop: { audio.stop() },
            insertText: { _ in .insertedDirectly },
            frontmostAppName: { "TextEdit" },
            canDictate: { false },
            onDictationBlocked: { blockedCalls += 1 }
        )
        await model.toggleDictation()
        XCTAssertEqual(model.state, .idle)          // never entered recording
        XCTAssertEqual(blockedCalls, 1)
        XCTAssertEqual(audio.startCount, 0)         // no audio captured
    }

    func testAllowedWhenCanDictate() async {
        let engine = FakeEngine()
        let audio = AudioStub()
        let model = AppModel(
            settings: SettingsStore(defaults: defaults),
            history: HistoryStore(fileURL: tmpHistory),
            engineProvider: { _ in engine },
            audioStart: { try audio.start() },
            audioStop: { audio.stop() },
            insertText: { _ in .insertedDirectly },
            frontmostAppName: { "TextEdit" },
            canDictate: { true }
        )
        await model.toggleDictation()
        guard case .recording = model.state else { return XCTFail("expected recording") }
        await model.cancelDictation()
    }

    func testAudioStartFailureLandsInFailedStateNotSilentEmptyRecording() async throws {
        struct MicPending: LocalizedError {
            var errorDescription: String? { "mic permission pending" }
        }
        let model = AppModel(
            settings: SettingsStore(defaults: defaults),
            history: HistoryStore(fileURL: tmpHistory),
            engineProvider: { _ in FakeEngine() },
            audioStart: { throw MicPending() },
            audioStop: {},
            insertText: { _ in .insertedDirectly },
            frontmostAppName: { "TextEdit" },
            minimumDuration: 0
        )

        await model.toggleDictation()

        guard case .failed(let message) = model.state else {
            return XCTFail("expected failed, got \(model.state)")
        }
        XCTAssertTrue(message.contains("mic permission pending"))
        XCTAssertTrue(model.history.entries.isEmpty)
    }

    func testConcurrentTriggersStartExactlyOneRecording() async throws {
        // Two triggers racing across the engine.isReady suspension must not
        // both start audio — a second installTap on the same bus is an
        // uncatchable crash in production.
        let engine = FakeEngine()
        engine.readyDelayMs = 50
        let (model, audio) = makeModel(engine: engine)

        async let first: Void = model.toggleDictation()
        async let second: Void = model.toggleDictation()
        _ = await (first, second)

        XCTAssertEqual(audio.startCount, 1, "exactly one audio capture may start")
        guard case .recording = model.state else {
            return XCTFail("expected recording, got \(model.state)")
        }
        await model.cancelDictation()
    }

    func testCancelDoesNotClobberStateWithSpuriousFailure() async throws {
        // Cancelling the pipeline ends its stream with nil (not
        // CancellationError); the resumed task must NOT re-enter the
        // no-speech failure branch and overwrite the post-cancel state.
        let engine = FakeEngine()
        let (model, audio) = makeModel(engine: engine)

        await model.toggleDictation()
        audio.emitSilence(buffers: 1)
        await model.cancelDictation()

        // Let the cancelled pipeline task resume and (incorrectly) finish.
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(model.state, .idle,
                       "state must stay .idle after cancel, not flip to .failed")
    }

    func testTooShortReasonSurvivesPipelineTeardown() async throws {
        // The too-short cancel sets .failed("Too short…"); the dying pipeline
        // must not replace it with "No speech detected."
        let engine = FakeEngine()
        let audio = AudioStub()
        let model = AppModel(
            settings: SettingsStore(defaults: defaults),
            history: HistoryStore(fileURL: tmpHistory),
            engineProvider: { _ in engine },
            audioStart: { try audio.start() },
            audioStop: { audio.stop() },
            insertText: { _ in .insertedDirectly },
            frontmostAppName: { "TextEdit" },
            minimumDuration: 10,     // guarantees the too-short path
            watchdogSeconds: 5
        )

        await model.toggleDictation()
        await model.toggleDictation()   // instant stop → too short

        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(50))

        guard case .failed(let message) = model.state else {
            return XCTFail("expected failed(too short), got \(model.state)")
        }
        XCTAssertTrue(message.contains("Too short"), "got: \(message)")
    }

    func testEngineErrorWhileRecordingStopsTheMicAndDoesNotBrickDictation() async throws {
        // An engine that fails while the mic is still live (corrupt model,
        // CoreML load failure) must not leave the tap installed: the orange
        // mic indicator would stay lit on a privacy-marketed app, and every
        // later attempt would die on "a recording is already in progress".
        let engine = FakeEngine()
        engine.throwsBeforeConsumingAudio = true
        engine.scriptedError = EngineError.engineFailure("model exploded")
        let (model, audio) = makeModel(engine: engine)

        await model.toggleDictation()
        await model.waitForIdle()

        guard case .failed = model.state else {
            return XCTFail("expected failed, got \(model.state)")
        }
        XCTAssertFalse(audio.isRunning, "the mic must not stay hot after a pipeline error")

        // And the app must still be usable — not soft-locked for the session.
        engine.throwsBeforeConsumingAudio = false
        engine.scriptedError = nil
        await model.toggleDictation()
        guard case .recording = model.state else {
            return XCTFail("dictation bricked after an engine error: \(model.state)")
        }
        await model.cancelDictation()
    }

    func testAudioInterruptionEndsTheRecordingVisibly() async throws {
        // AirPods connect mid-sentence: macOS tears down the tap. The app must
        // NOT keep showing "Listening" over a dead mic.
        let engine = FakeEngine()
        let (model, audio) = makeModel(engine: engine)

        await model.toggleDictation()
        guard case .recording = model.state else { return XCTFail("expected recording") }

        await model.audioInterrupted(reason: "The audio device changed — dictation stopped.")

        guard case .failed(let message) = model.state else {
            return XCTFail("expected a visible failure, got \(model.state)")
        }
        XCTAssertTrue(message.contains("audio device changed"), "got: \(message)")
        XCTAssertFalse(audio.isRunning)
    }

    func testAudioInterruptionDoesNotKillAnInFlightTranscription() async throws {
        // Once capture has stopped, a late device-change notification must not
        // throw away a transcription that is already running.
        let engine = FakeEngine()
        let (model, audio) = makeModel(engine: engine)

        await model.toggleDictation()
        audio.emitSilence(buffers: 1)
        await model.toggleDictation()          // -> .transcribing
        await model.audioInterrupted(reason: "The audio device changed — dictation stopped.")
        await model.waitForIdle()

        XCTAssertEqual(model.history.entries.first?.text, "hello world")
    }

    func testUnusableInputFormatIsRejectedBeforeInstallingATap() {
        // installTap with a 0-channel format is an uncatchable ObjC crash, so
        // this guard is the only thing standing between a sleeping audio
        // interface and a hard crash on the hotkey.
        XCTAssertFalse(AudioService.isUsableInputFormat(sampleRate: 0, channelCount: 0))
        XCTAssertFalse(AudioService.isUsableInputFormat(sampleRate: 48000, channelCount: 0))
        XCTAssertFalse(AudioService.isUsableInputFormat(sampleRate: 0, channelCount: 2))
        XCTAssertTrue(AudioService.isUsableInputFormat(sampleRate: 48000, channelCount: 1))
    }

    func testWatchdogDeadlineScalesWithRecordingLength() {
        // Short recordings keep the base; long ones get proportional headroom
        // so a legitimate 60s+ dictation isn't killed mid-transcription.
        XCTAssertEqual(AppModel.watchdogDeadline(base: 60, recordedSeconds: 5), 60)
        XCTAssertEqual(AppModel.watchdogDeadline(base: 60, recordedSeconds: 60), 110)
        XCTAssertEqual(AppModel.watchdogDeadline(base: 60, recordedSeconds: 300), 470)
    }
}

@MainActor
final class AudioStub {
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private(set) var startCount = 0
    /// Mirrors AudioService: a live tap until stop() runs. The real service
    /// refuses a second start while running, so the stub must too — otherwise
    /// tests can't see the "mic left hot" class of bug at all.
    private(set) var isRunning = false

    struct AlreadyRunning: LocalizedError {
        var errorDescription: String? { "a recording is already in progress" }
    }

    func start() throws -> AsyncStream<AVAudioPCMBuffer> {
        guard !isRunning else { throw AlreadyRunning() }
        startCount += 1
        isRunning = true
        return AsyncStream { self.continuation = $0 }
    }

    func stop() {
        continuation?.finish()
        isRunning = false
    }

    func emitSilence(buffers: Int) {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        for _ in 0..<buffers {
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600)!
            buffer.frameLength = 1600
            continuation?.yield(buffer)
        }
    }
}
