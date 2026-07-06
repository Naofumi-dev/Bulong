import Foundation
@preconcurrency import AVFoundation
@preconcurrency import WhisperKit

private struct UncheckedAudioStream: @unchecked Sendable {
    let stream: AsyncStream<AVAudioPCMBuffer>
}

actor WhisperKitEngine: TranscriptionEngine {
    nonisolated let id: EngineID = .whisperKit

    private var pipeline: WhisperKit?
    private var cancelled = false

    nonisolated func isReady(for options: TranscriptionOptions) async -> Bool {
        FileManager.default.fileExists(atPath: ModelManager.whisperModelFolder.path)
    }

    func prepare(
        options: TranscriptionOptions,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        if pipeline != nil {
            progress(1)
            return
        }

        let folder: URL
        if FileManager.default.fileExists(atPath: ModelManager.whisperModelFolder.path) {
            folder = ModelManager.whisperModelFolder
        } else {
            folder = try await WhisperKit.download(
                variant: ModelManager.whisperModelName,
                downloadBase: ModelManager.whisperDownloadBase,
                progressCallback: { downloadProgress in
                    progress(downloadProgress.fractionCompleted * 0.8)
                }
            )
        }

        let pipe = try await WhisperKit(
            WhisperKitConfig(prewarm: false, load: false, download: false)
        )
        pipe.modelFolder = folder
        try await pipe.prewarmModels()
        progress(0.9)
        try await pipe.loadModels()
        progress(1)
        pipeline = pipe
    }

    nonisolated func transcribe(
        audio: AsyncStream<AVAudioPCMBuffer>,
        options: TranscriptionOptions
    ) -> AsyncThrowingStream<TranscriptionUpdate, Error> {
        let audio = UncheckedAudioStream(stream: audio)
        return AsyncThrowingStream<TranscriptionUpdate, Error> { continuation in
            Task {
                do {
                    try await self.run(
                        audio: audio.stream,
                        options: options,
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func run(
        audio: AsyncStream<AVAudioPCMBuffer>,
        options: TranscriptionOptions,
        continuation: AsyncThrowingStream<TranscriptionUpdate, Error>.Continuation
    ) async throws {
        cancelled = false

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("localtalk-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }

        var file: AVAudioFile?
        for await buffer in audio {
            if cancelled { break }
            if file == nil {
                file = try AVAudioFile(forWriting: url, settings: buffer.format.settings)
            }
            try file?.write(from: buffer)
        }
        file = nil

        if cancelled {
            continuation.finish(throwing: EngineError.cancelled)
            return
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            continuation.finish(throwing: EngineError.engineFailure("No audio was recorded."))
            return
        }

        if pipeline == nil {
            try await prepare(options: options) { _ in }
        }
        guard let pipeline else {
            throw EngineError.modelNotDownloaded(.whisperKit)
        }

        let decodeOptions = DecodingOptions(
            task: options.task == .translate ? .translate : .transcribe,
            language: options.language,
            temperature: 0,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            chunkingStrategy: .vad
        )
        let results = try await pipeline.transcribe(
            audioPath: url.path,
            decodeOptions: decodeOptions
        )

        if cancelled {
            continuation.finish(throwing: EngineError.cancelled)
            return
        }

        let text = results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        continuation.yield(.final(text))
        continuation.finish()
    }

    func cancel() async {
        cancelled = true
    }
}
