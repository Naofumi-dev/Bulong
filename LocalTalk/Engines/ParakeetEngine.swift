import Foundation
@preconcurrency import AVFoundation
import FluidAudio

private struct UncheckedAudioStream: @unchecked Sendable {
    let stream: AsyncStream<AVAudioPCMBuffer>
}

actor ParakeetEngine: TranscriptionEngine {
    nonisolated let id: EngineID = .parakeet

    private nonisolated let version: AsrModelVersion
    /// CoreML models are loaded ONCE per app run and cached here. A
    /// `SlidingWindowAsrManager` is single-use per streaming session
    /// (its input stream can't be restarted after `finish()`), so each
    /// dictation gets a fresh manager attached to these cached models —
    /// that attach is cheap, the model load is the expensive part.
    private var models: AsrModels?
    private var manager: SlidingWindowAsrManager?
    /// Per-run token instead of a shared `cancelled` flag. The flag was reset
    /// at the top of every run, so starting a new dictation silently
    /// UN-cancelled a previous one that was still grinding away — and nothing
    /// checked it after `manager.finish()`, the expensive part. Cancelled work
    /// therefore kept burning CPU and Neural Engine time, and several orphans
    /// could stack up until the whole app crawled.
    private var generation: UInt64 = 0
    /// The manager belonging to the run in flight, kept so cancel() can reach
    /// in and stop the underlying work rather than just setting a flag.
    private var activeManager: SlidingWindowAsrManager?

    private var isPrepareInFlight = false

    init(version: ParakeetVersion) {
        self.version = version == .v2 ? .v2 : .v3
    }

    nonisolated func isReady(for options: TranscriptionOptions) async -> Bool {
        ModelManager.parakeetExists(version)
    }

    func prepare(
        options: TranscriptionOptions,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        // `models == nil` is checked BEFORE an await, so two callers (the
        // launch prewarm and the user's first dictation) both saw nil and both
        // paid the multi-second CoreML load — doubling the slowest moment in
        // the app. Coalesce: the second caller waits for the first.
        while isPrepareInFlight {
            try await Task.sleep(for: .milliseconds(50))
        }
        if models == nil {
            isPrepareInFlight = true
            defer { isPrepareInFlight = false }
            models = try await AsrModels.downloadAndLoad(version: version) { progressState in
                progress(progressState.fractionCompleted)
            }
        }
        guard let models else { return }
        progress(0.9)
        let manager = SlidingWindowAsrManager(config: .streaming)
        try await manager.loadModels(models)
        self.manager = manager
        progress(1)
    }

    nonisolated func transcribe(
        audio: AsyncStream<AVAudioPCMBuffer>,
        options: TranscriptionOptions
    ) -> AsyncThrowingStream<TranscriptionUpdate, Error> {
        let audio = UncheckedAudioStream(stream: audio)
        return AsyncThrowingStream<TranscriptionUpdate, Error> { continuation in
            Task {
                do {
                    try await self.run(audio: audio.stream, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func run(
        audio: AsyncStream<AVAudioPCMBuffer>,
        continuation: AsyncThrowingStream<TranscriptionUpdate, Error>.Continuation
    ) async throws {
        generation &+= 1
        let myGeneration = generation

        if manager == nil {
            try await prepare(options: TranscriptionOptions(language: "en", task: .transcribe)) { _ in }
        }

        guard let manager else {
            throw EngineError.modelNotDownloaded(.parakeet)
        }
        // Consume the prepared manager: it is single-use per streaming session,
        // so the next dictation must build a fresh one (from the cached models).
        self.manager = nil
        activeManager = manager
        defer { if generation == myGeneration { activeManager = nil } }

        try await manager.startStreaming(source: .microphone)

        let updatesTask = Task {
            var confirmed = ""
            for await update in await manager.transcriptionUpdates {
                if update.isConfirmed {
                    confirmed += update.text
                }

                let display = (confirmed + (update.isConfirmed ? "" : " " + update.text))
                    .trimmingCharacters(in: .whitespaces)
                continuation.yield(.partial(display))
            }
        }
        defer { updatesTask.cancel() }

        for await buffer in audio {
            if generation != myGeneration { break }
            await manager.streamAudio(buffer)
        }
        updatesTask.cancel()

        if generation != myGeneration {
            await manager.cancel()
            try? await manager.reset()
            continuation.finish(throwing: EngineError.cancelled)
            return
        }

        let text = try await manager.finish()
        try? await manager.reset()

        // finish() is the long pole and cannot be interrupted from outside, so
        // re-check after it: a run cancelled mid-transcription must discard its
        // result instead of emitting into a continuation nobody is reading (or,
        // worse, one that now belongs to a newer dictation).
        guard generation == myGeneration else {
            continuation.finish(throwing: EngineError.cancelled)
            return
        }

        continuation.yield(.final(text))
        continuation.finish()
    }

    func cancel() async {
        // Invalidate every in-flight run, then stop the underlying work rather
        // than only marking a flag.
        generation &+= 1
        if let activeManager {
            self.activeManager = nil
            await activeManager.cancel()
            try? await activeManager.reset()
        }
    }
}
