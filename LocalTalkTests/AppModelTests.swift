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
            audioStart: { audio.start() },
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
            audioStart: { audio.start() },
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
            audioStart: { audio.start() },
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
}

@MainActor
final class AudioStub {
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?

    func start() -> AsyncStream<AVAudioPCMBuffer> {
        AsyncStream { self.continuation = $0 }
    }

    func stop() {
        continuation?.finish()
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
