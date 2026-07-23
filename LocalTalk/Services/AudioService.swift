import Foundation
import Observation
@preconcurrency import AVFoundation

@MainActor @Observable
final class AudioService {
    private(set) var level: Float = 0
    private(set) var isRunning = false

    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?

    enum AudioError: LocalizedError {
        case micPermissionDenied
        case micPermissionPending
        case engineStartFailed(String)

        var errorDescription: String? {
            switch self {
            case .micPermissionDenied:
                return "Microphone access is denied. Enable it in System Settings > Privacy & Security > Microphone."
            case .micPermissionPending:
                return "macOS is asking for microphone access — click Allow, then dictate again."
            case .engineStartFailed(let message):
                return "Couldn't start audio input: \(message)"
            }
        }
    }

    static func requestMicPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    func start() throws -> AsyncStream<AVAudioPCMBuffer> {
        // A second installTap on a bus that already has one raises an
        // uncatchable ObjC exception — refuse loudly instead of crashing.
        guard !isRunning else {
            throw AudioError.engineStartFailed("a recording is already in progress")
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            // Fire the one-time system consent prompt so a dictation attempt
            // is never a silent no-op; the user allows once and retries.
            Task { _ = await AVCaptureDevice.requestAccess(for: .audio) }
            throw AudioError.micPermissionPending
        default:
            throw AudioError.micPermissionDenied
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let (stream, continuation) = AsyncStream.makeStream(
            of: AVAudioPCMBuffer.self,
            bufferingPolicy: .unbounded
        )
        self.continuation = continuation

        // The tap block runs on a real-time AUDIO thread, not the main actor.
        // It MUST be `@Sendable` / non-isolated: a MainActor-isolated closure
        // here traps at runtime (swift_task_isCurrentExecutor / dispatch_assert_queue)
        // the instant AVFoundation invokes it off the main actor. The `@Sendable`
        // annotation is compiler-enforced, so it's also the regression guard.
        // Touch `self` only inside the MainActor hop for the UI level update.
        let tap: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void = { buffer, _ in
            continuation.yield(buffer)
            let rms = Self.rms(of: buffer)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.level = max(rms, self.level * 0.7)
            }
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: format, block: tap)

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            self.continuation = nil
            throw AudioError.engineStartFailed(error.localizedDescription)
        }

        isRunning = true
        return stream
    }

    func stop() {
        guard isRunning else {
            continuation?.finish()
            continuation = nil
            return
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
        isRunning = false
        level = 0
    }

    private nonisolated static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }

        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) {
            sum += data[index] * data[index]
        }

        let rms = sqrt(sum / Float(buffer.frameLength))
        let db = 20 * log10(max(rms, 1e-7))
        return min(1, max(0, (db + 58) / 58))
    }
}
