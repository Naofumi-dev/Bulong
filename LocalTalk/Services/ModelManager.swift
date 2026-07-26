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
        parakeetV2 = Self.nextState(current: parakeetV2, isComplete: Self.parakeetExists(.v2))
        parakeetV3 = Self.nextState(current: parakeetV3, isComplete: Self.parakeetExists(.v3))
        whisperLargeTurbo = Self.nextState(current: whisperLargeTurbo,
                                           isComplete: Self.whisperModelIsComplete())
    }

    /// What a poll may and may not overwrite. `refresh()` runs every ~2s while
    /// the main window is open, and it used to flatten `.failed` back to
    /// `.notDownloaded` — so a download error and its Retry button vanished
    /// about a second after appearing and the user never learned why it broke.
    /// A failure now survives until the model is actually present or the user
    /// retries. Pure so the policy is testable.
    nonisolated static func nextState(current: DownloadState, isComplete: Bool) -> DownloadState {
        if case .downloading = current { return current }
        if isComplete { return .ready }
        if case .failed = current { return current }
        return .notDownloaded
    }

    /// Whether the Whisper download actually finished. Readiness used to be a
    /// bare `fileExists` on the FOLDER, so a download killed by quit, sleep or
    /// a dropped connection left a partial tree that reported "Ready" forever
    /// with no way to repair it from inside the app — and every dictation
    /// after that failed. This matters most for Tagalog, which routes to
    /// Whisper. Checks the compiled CoreML bundles rather than the wrapper.
    nonisolated static func whisperModelIsComplete(
        at folder: URL = whisperModelFolder,
        fileManager: FileManager = .default
    ) -> Bool {
        let required = ["AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc"]
        for bundle in required {
            let directory = folder.appendingPathComponent(bundle, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  // The compiled-model marker: present only once the bundle is whole.
                  fileManager.fileExists(atPath: directory.appendingPathComponent("coremldata.bin").path),
                  let weights = try? fileManager.contentsOfDirectory(
                      atPath: directory.appendingPathComponent("weights", isDirectory: true).path),
                  !weights.isEmpty
            else { return false }
        }
        return true
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
