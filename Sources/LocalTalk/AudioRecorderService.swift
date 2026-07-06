import AVFoundation
import Foundation

final class AudioRecorderService: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private var currentURL: URL?

    func start() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalTalk/Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent("clip-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true

        guard recorder.prepareToRecord() else {
            throw AudioRecorderError.unableToPrepare
        }

        guard recorder.record() else {
            throw AudioRecorderError.unableToStart
        }

        self.recorder = recorder
        currentURL = url
        return url
    }

    func stop() -> URL? {
        guard let recorder else { return nil }
        recorder.stop()
        self.recorder = nil

        let url = currentURL
        currentURL = nil
        return url
    }
}

enum AudioRecorderError: LocalizedError {
    case unableToPrepare
    case unableToStart

    var errorDescription: String? {
        switch self {
        case .unableToPrepare:
            return "Could not prepare the microphone recorder"
        case .unableToStart:
            return "Could not start microphone recording"
        }
    }
}
