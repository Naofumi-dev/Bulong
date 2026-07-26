import Foundation
@preconcurrency import AVFoundation
@testable import Bulong

private struct UncheckedAudioStream: @unchecked Sendable {
    let stream: AsyncStream<AVAudioPCMBuffer>
}

final class FakeEngine: TranscriptionEngine, @unchecked Sendable {
    let id: EngineID = .parakeet
    var scriptedUpdates: [TranscriptionUpdate] = [
        .partial("hel"),
        .partial("hello"),
        .final("hello world"),
    ]
    var scriptedError: Error?
    /// Throw WITHOUT consuming the audio stream first — reproduces an engine
    /// that fails while the mic is still live (corrupt model, CoreML load
    /// failure), which is the path that used to leave the tap installed.
    var throwsBeforeConsumingAudio = false
    var ready = true
    /// When > 0, isReady suspends this long first — reproduces the cold-launch
    /// window where a second trigger can race the first start.
    var readyDelayMs: UInt64 = 0
    private(set) var cancelCalled = false
    private(set) var buffersReceived = 0

    func isReady(for options: TranscriptionOptions) async -> Bool {
        if readyDelayMs > 0 {
            try? await Task.sleep(for: .milliseconds(readyDelayMs))
        }
        return ready
    }

    func prepare(
        options: TranscriptionOptions,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        progress(1.0)
        ready = true
    }

    func transcribe(
        audio: AsyncStream<AVAudioPCMBuffer>,
        options: TranscriptionOptions
    ) -> AsyncThrowingStream<TranscriptionUpdate, Error> {
        let uncheckedAudio = UncheckedAudioStream(stream: audio)
        return AsyncThrowingStream<TranscriptionUpdate, Error> { continuation in
            Task {
                if self.throwsBeforeConsumingAudio {
                    continuation.finish(throwing: self.scriptedError ?? EngineError.engineFailure("boom"))
                    return
                }

                for await _ in uncheckedAudio.stream {
                    self.buffersReceived += 1
                }

                if let scriptedError = self.scriptedError {
                    continuation.finish(throwing: scriptedError)
                    return
                }

                for update in self.scriptedUpdates {
                    continuation.yield(update)
                }

                continuation.finish()
            }
        }
    }

    func cancel() async {
        cancelCalled = true
    }
}
