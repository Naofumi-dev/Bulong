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
    private var cancelled = false

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
        if models == nil {
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
        cancelled = false

        if manager == nil {
            try await prepare(options: TranscriptionOptions(language: "en", task: .transcribe)) { _ in }
        }

        guard let manager else {
            throw EngineError.modelNotDownloaded(.parakeet)
        }
        // Consume the prepared manager: it is single-use per streaming session,
        // so the next dictation must build a fresh one (from the cached models).
        self.manager = nil

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

        for await buffer in audio {
            if cancelled { break }
            await manager.streamAudio(buffer)
        }
        updatesTask.cancel()

        if cancelled {
            await manager.cancel()
            try? await manager.reset()
            continuation.finish(throwing: EngineError.cancelled)
            return
        }

        let text = try await manager.finish()
        try? await manager.reset()
        continuation.yield(.final(text))
        continuation.finish()
    }

    func cancel() async {
        cancelled = true
    }
}
