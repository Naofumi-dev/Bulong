import Foundation
@preconcurrency import AVFoundation

struct TranscriptionOptions: Sendable, Equatable {
    var language: String
    var task: DictationTask
}

enum EngineError: LocalizedError {
    case modelNotDownloaded(EngineID)
    case cancelled
    case timedOut
    case engineFailure(String)

    var errorDescription: String? {
        switch self {
        case .modelNotDownloaded(let id):
            return "The \(id.rawValue) model isn't downloaded yet. Open Settings -> Models."
        case .cancelled:
            return "Cancelled."
        case .timedOut:
            return "Transcription took too long and was stopped."
        case .engineFailure(let message):
            return message
        }
    }
}

protocol TranscriptionEngine: Sendable {
    var id: EngineID { get }

    func isReady(for options: TranscriptionOptions) async -> Bool

    func prepare(
        options: TranscriptionOptions,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws

    func transcribe(
        audio: AsyncStream<AVAudioPCMBuffer>,
        options: TranscriptionOptions
    ) -> AsyncThrowingStream<TranscriptionUpdate, Error>

    func cancel() async
}
