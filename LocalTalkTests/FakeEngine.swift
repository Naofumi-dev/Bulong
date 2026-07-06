import Foundation
@preconcurrency import AVFoundation
@testable import LocalTalk

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
    var ready = true
    private(set) var cancelCalled = false
    private(set) var buffersReceived = 0

    func isReady(for options: TranscriptionOptions) async -> Bool {
        ready
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
