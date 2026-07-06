import Foundation
import Observation
import FluidAudio
@preconcurrency import WhisperKit

@MainActor @Observable
final class ModelManager {
    enum DownloadState: Equatable {
        case notDownloaded
        case downloading(Double)
        case ready
        case failed(String)
    }

    private(set) var parakeetV2: DownloadState = .notDownloaded
    private(set) var parakeetV3: DownloadState = .notDownloaded
    private(set) var whisperLargeTurbo: DownloadState = .notDownloaded

    nonisolated static let whisperModelName = "large-v3-v20240930_turbo"

    nonisolated static var whisperDownloadBase: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Bulong/Models/whisperkit", isDirectory: true)
    }

    nonisolated static var whisperModelFolder: URL {
        whisperDownloadBase.appendingPathComponent(
            "models/argmaxinc/whisperkit-coreml/openai_whisper-\(whisperModelName)"
        )
    }

    func refresh() {
        parakeetV2 = Self.parakeetExists(.v2) ? .ready : .notDownloaded
        parakeetV3 = Self.parakeetExists(.v3) ? .ready : .notDownloaded
        whisperLargeTurbo = FileManager.default.fileExists(atPath: Self.whisperModelFolder.path)
            ? .ready
            : .notDownloaded
    }

    nonisolated static func parakeetExists(_ version: AsrModelVersion) -> Bool {
        let directory = AsrModels.defaultCacheDirectory(for: version)
        return AsrModels.modelsExist(at: directory, version: version, encoderPrecision: .int8)
    }

    func downloadParakeet(_ version: AsrModelVersion) async {
        setParakeet(version, .downloading(0))
        do {
            _ = try await AsrModels.download(version: version) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.setParakeet(version, .downloading(progress.fractionCompleted))
                }
            }
            setParakeet(version, .ready)
        } catch {
            setParakeet(version, .failed(error.localizedDescription))
        }
    }

    func downloadWhisper() async {
        whisperLargeTurbo = .downloading(0)
        do {
            _ = try await WhisperKit.download(
                variant: Self.whisperModelName,
                downloadBase: Self.whisperDownloadBase,
                progressCallback: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.whisperLargeTurbo = .downloading(progress.fractionCompleted)
                    }
                }
            )
            whisperLargeTurbo = .ready
        } catch {
            whisperLargeTurbo = .failed(error.localizedDescription)
        }
    }

    private func setParakeet(_ version: AsrModelVersion, _ state: DownloadState) {
        switch version {
        case .v2:
            parakeetV2 = state
        default:
            parakeetV3 = state
        }
    }
}
