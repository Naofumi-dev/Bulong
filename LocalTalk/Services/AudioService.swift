import Foundation
import Observation
@preconcurrency import AVFoundation

@MainActor @Observable
final class AudioService {
    private(set) var level: Float = 0
    private(set) var isRunning = false

    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    // Adaptive gain for the level METER (never the recorded audio): the dB
    // floor of a "quiet room" varies wildly by mic and gain, so a fixed gate
    // can't separate voice from room everywhere. Track the floor and the
    // speech peak live and normalize between them.
    private var noiseFloor: Float = 0.45
    private var speechPeak: Float = 0.7

    /// Fires when the hardware configuration changes mid-recording (AirPods
    /// connect, headphones unplug, input switched in System Settings). macOS
    /// stops the engine and drops the tap, so the recording is over whether we
    /// like it or not — the caller must end it visibly instead of leaving a
    /// live-looking HUD over a dead tap.
    var onInterrupted: (@MainActor (String) -> Void)?
    private var configObserver: NSObjectProtocol?

    enum AudioError: LocalizedError {
        case micPermissionDenied
        case micPermissionPending
        case noInputDevice
        case engineStartFailed(String)

        var errorDescription: String? {
            switch self {
            case .micPermissionDenied:
                return "Microphone access is denied. Enable it in System Settings > Privacy & Security > Microphone."
            case .micPermissionPending:
                return "macOS is asking for microphone access — click Allow, then dictate again."
            case .noInputDevice:
                return "No microphone found. Connect one (or wake your audio interface) and try again."
            case .engineStartFailed(let message):
                return "Couldn't start audio input: \(message)"
            }
        }
    }

    /// A usable capture format. A missing/asleep input device reports 0 Hz and
    /// 0 channels, and `installTap` with that format raises an UNCATCHABLE
    /// ObjC exception — so this must be checked before the tap goes on.
    /// Pure so it is unit-testable without hardware.
    nonisolated static func isUsableInputFormat(sampleRate: Double, channelCount: UInt32) -> Bool {
        sampleRate > 0 && channelCount > 0
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
        guard Self.isUsableInputFormat(sampleRate: format.sampleRate,
                                       channelCount: format.channelCount) else {
            throw AudioError.noInputDevice
        }
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
        noiseFloor = 0.45
        speechPeak = 0.7
        level = 0
        let tap: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void = { buffer, _ in
            continuation.yield(buffer)
            let rms = Self.rms(of: buffer)
            Task { @MainActor [weak self] in
                // Hops enqueued before stop() run after it, so without this
                // guard a late buffer resurrects `level` and freezes the HUD
                // glow at speech brightness through the whole transcription.
                guard let self, self.isRunning else { return }
                var floor = self.noiseFloor
                var peak = self.speechPeak
                let norm = Self.adaptiveNormalize(raw: rms, floor: &floor, peak: &peak)
                self.noiseFloor = floor
                self.speechPeak = peak
                self.level = max(norm, self.level * 0.7)
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

        // A device change tears down the tap underneath us. Watch for it only
        // while recording so an idle app isn't reacting to every route change.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isRunning else { return }
                self.stop()
                self.onInterrupted?("The audio device changed — dictation stopped.")
            }
        }

        isRunning = true
        return stream
    }

    func stop() {
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
            self.configObserver = nil
        }
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

    /// Maps a raw dB-scaled level onto 0…1 between the LEARNED noise floor and
    /// speech peak. Floor falls fast (adapts to any quiet room in <1s) and
    /// rises very slowly (speech can't drag it up); the peak follows loud
    /// speech instantly and decays gently. Pure so it's unit-testable.
    nonisolated static func adaptiveNormalize(raw: Float, floor: inout Float, peak: inout Float) -> Float {
        if raw < floor {
            floor += (raw - floor) * 0.25
        } else {
            // Must be slow enough that SUSTAINED speech can't teach the floor
            // to swallow itself. At ~11.7 buffers/s, 0.02 flatlined the meter
            // to 0.00 within ~10s of continuous talking (bursty speech hid it,
            // because word gaps pull the floor back down). 0.005 holds speech
            // at ~0.78 through 8s and still absorbs a genuinely louder room
            // (settling a no-speech noisy room to ~0.01 within 20s).
            floor += (raw - floor) * 0.005
        }
        // Decay fast enough that one transient doesn't deaden the meter: a
        // cough spikes the peak, and at 0.995 (~12s half-life) every following
        // word read ~35% for 9s+. 0.98 recovers in about two seconds.
        peak = max(raw, max(peak * 0.98, floor + 0.18))
        let span = max(peak - floor, 0.18)
        return max(0, min(1, (raw - floor - 0.05) / span))
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
