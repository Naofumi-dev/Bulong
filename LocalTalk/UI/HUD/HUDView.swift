import AppKit
import SwiftUI

struct HUDView: View {
    /// Single source of truth for the pill's size — the panel content must match exactly.
    static let hudSize = NSSize(width: 392, height: 74)
    /// Below this level the orb settles and the bars go flat. One constant so the
    /// orb and the waveform can never disagree on what silence is.
    static let silenceThreshold: Float = 0.06

    let state: DictationState
    let level: Float
    let partial: String
    /// Transient pipeline status (e.g. cold model-load progress) — shown while
    /// processing so a slow first transcription reads as loading, not a hang.
    var status: String = ""
    let language: String
    var onCancel: () -> Void
    var onDragChanged: (CGSize) -> Void
    var onDragEnded: () -> Void

    @State private var hovering = false
    @State private var smoother = WaveSmoother()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isFailed: Bool { if case .failed = state { true } else { false } }
    private var isRecording: Bool { if case .recording = state { true } else { false } }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if isDone {
                    DoneBadge(clipboardOnly: doneIsClipboardOnly)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.5).combined(with: .opacity))
                } else {
                    OrbView(level: level, state: state, reduceMotion: reduceMotion)
                }
            }
            .frame(width: 34, height: 34)
            .animation(reduceMotion ? Theme.easeFast : Theme.spring, value: isDone)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Fonts.bodyStrong).foregroundStyle(Theme.hudTitle)
                // Live partials keep the newest words visible (head-truncate,
                // pre-trimmed to a word boundary); static hints must not lose
                // their tail ("…Esc cancels" ≠ hint). Failure messages get two
                // lines and the width freed by the dropped chips — never
                // mid-word-truncate what went wrong.
                Text(detail).font(Theme.Fonts.mono(10.5)).foregroundStyle(Theme.hudDetail)
                    .lineLimit(isFailed ? 2 : 1)
                    .truncationMode(showsLivePartial ? .head : .tail)
            }
            Spacer(minLength: 8)
            SmoothedWaveform(level: level, state: state, smoother: smoother, reduceMotion: reduceMotion)
            // Chips are metadata, not status — they drop out entirely in
            // .failed so the message gets the width.
            if !isFailed {
                badge("ON-DEVICE")
                badge(language.uppercased())
            }
            // Space is always reserved so the chip cluster never slides;
            // visibility is opacity-only. In .failed it doubles as dismiss.
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.hudDetail)
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(Theme.hudHairline, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(TactilePressStyle())
            .opacity(showCancel ? 1 : 0)
            .allowsHitTesting(showCancel)
            .accessibilityLabel(isFailed ? "Dismiss" : "Cancel dictation")
            .accessibilityHidden(!showCancel)
        }
        .padding(.horizontal, 16)
        .frame(width: Self.hudSize.width, height: Self.hudSize.height)
        .background(
            LinearGradient(colors: [Theme.hudShellTop, Theme.hudShellBottom],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .opacity(0.96)
        )
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusHUD, style: .continuous)
            .stroke(isFailed ? Theme.failure.opacity(0.6) : Theme.hudRim, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusHUD, style: .continuous))
        .shadow(color: Theme.hudShadow, radius: 22, y: 12)
        .overlay(ActiveAlwaysHoverTracker { hovering = $0 })
        // Cancel reveal is opacity-only (its space is reserved), so the fade
        // may stay ungated under Reduce Motion.
        .animation(Theme.easeFast, value: hovering)
        .animation(Theme.easeFast, value: showCancel)
        .gesture(DragGesture()
            .onChanged { onDragChanged($0.translation) }
            .onEnded { _ in onDragEnded() })
        .onChange(of: isRecording) { _, isNow in
            // The hosting view lives across dictations now; drop hover state
            // stranded by the panel ordering out mid-hover.
            if isNow { hovering = false }
        }
    }

    private var showCancel: Bool {
        if case .transcribing = state { return true }
        if isFailed { return true }
        return isRecording && hovering
    }

    /// The post-run beat: back to idle with an outcome to show. The panel
    /// lingers briefly (see wireHotkey) so "Done — inserted" registers before
    /// the fade; clipboard fallbacks get their promised subtle notification.
    private var isDone: Bool {
        if case .idle = state { return !status.isEmpty }
        return false
    }

    private var doneIsClipboardOnly: Bool {
        status.hasPrefix("Copied")
    }

    private var title: String {
        switch state {
        case .recording: "Listening"
        case .transcribing: "Transcribing"
        case .inserting: "Inserting"
        case .failed: "Failed"
        case .idle: isDone ? "Done" : "Bulong"
        }
    }

    private var detail: String {
        if case .failed(let m) = state { return m }
        if isDone { return status }
        if !partial.isEmpty { return Self.wordTrimmedTail(partial) }
        if !status.isEmpty, isProcessing { return status }
        if case .recording = state { return "Esc to cancel" }
        return "On-device dictation"
    }

    private var isProcessing: Bool {
        switch state {
        case .transcribing, .inserting: true
        default: false
        }
    }

    private var showsLivePartial: Bool {
        if case .failed = state { return false }
        return !partial.isEmpty
    }

    /// Head-trims a live partial so the visible fragment starts on a word
    /// boundary instead of mid-word (Text's .head truncation cuts anywhere).
    static func wordTrimmedTail(_ text: String, maxChars: Int = 13) -> String {
        guard text.count > maxChars else { return text }
        var tail = text.suffix(maxChars)
        if let space = tail.firstIndex(where: \.isWhitespace) {
            tail = tail[tail.index(after: space)...]
        }
        return "…" + tail
    }

    /// Chips are quiet metadata in every state: tertiary text, hairline ring.
    /// The orb and waveform own all the accent.
    private func badge(_ text: String) -> some View {
        Text(text).font(Theme.Fonts.mono(9, weight: .bold))
            .foregroundStyle(Theme.hudTertiary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().stroke(Theme.hudHairline, lineWidth: 1))
    }
}

/// The success beat: a solid mint sphere-badge with the outcome glyph.
/// Same 3D shading family as the orb so the swap reads as one object landing.
struct DoneBadge: View {
    let clipboardOnly: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Color.white.opacity(0.9), Theme.accent, Theme.accent.opacity(0.55)],
                    center: UnitPoint(x: 0.36, y: 0.3), startRadius: 0, endRadius: 15))
                .frame(width: 24, height: 24)
                .shadow(color: Theme.accent.opacity(0.45), radius: 7, y: 2)
            Circle()
                .stroke(
                    LinearGradient(colors: [Color.white.opacity(0.55), .clear],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
                .frame(width: 24, height: 24)
            Image(systemName: clipboardOnly ? "doc.on.clipboard" : "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.72))
        }
        .accessibilityLabel(clipboardOnly ? "Copied to clipboard" : "Inserted")
    }
}

/// The living orb: a mint radial core whose glow breathes with the live level.
/// Silence reads as silence — below the threshold it settles to a calm minimum.
struct OrbView: View {
    let level: Float
    let state: DictationState
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let energy = energyValue(t: t)
            let bodySize = 16 + 5 * energy
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [color.opacity(0.45 * energy), .clear],
                        center: .center, startRadius: 2, endRadius: 17 + 10 * energy))
                Circle()
                    .fill(RadialGradient(
                        colors: [Color.white.opacity(0.85), color, color.opacity(0.25)],
                        center: UnitPoint(x: 0.38, y: 0.35), startRadius: 0, endRadius: 11))
                    .frame(width: bodySize, height: bodySize)
                    .shadow(color: color.opacity(0.35 * energy), radius: 5, y: 2)
                // Sphere cues: a top-lit rim and a specular catchlight give the
                // flat gradient real volume — the HUD's echo of the 3D app icon.
                Circle()
                    .stroke(
                        LinearGradient(colors: [Color.white.opacity(0.5), .clear],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.8)
                    .frame(width: bodySize, height: bodySize)
                Circle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 3.2, height: 3.2)
                    .offset(x: -bodySize * 0.17, y: -bodySize * 0.2)
                    .blur(radius: 0.4)
            }
            // The orb scaling with the live level is motion; under Reduce
            // Motion it still tracks the level but snaps instead of breathing.
            .animation(reduceMotion ? nil : Theme.easeFast, value: energy)
        }
    }

    private var paused: Bool {
        if reduceMotion { return true }
        switch state { case .idle, .failed: return true; default: return false }
    }

    private var color: Color {
        if case .failed = state { return Theme.failure }
        return Theme.accent
    }

    /// Recording: live level (flat when below threshold). Transcribing/inserting: slow steady pulse.
    private func energyValue(t: TimeInterval) -> CGFloat {
        switch state {
        case .recording:
            let live = level < HUDView.silenceThreshold ? 0 : level
            return CGFloat(0.25 + 0.75 * live)
        case .transcribing, .inserting:
            return reduceMotion ? 0.5 : 0.4 + 0.2 * CGFloat(abs(sin(t * 2.2)))
        case .failed: return 0.2
        case .idle: return 0.3
        }
    }
}

/// Per-bar smoothing state kept outside SwiftUI `@State`: the values advance on
/// every TimelineView frame, and mutating view state during a view update is
/// undefined behavior (the plan's noted fallback). A plain reference type keeps
/// the visual contract — per-bar lag, silence-flat — without touching view state.
final class WaveSmoother {
    var values: [Float] = Array(repeating: 0, count: 7)

    /// The hosting view is reused across dictations, so a new recording must
    /// explicitly start from silence rather than inherit the last session's bars.
    func reset() {
        values = Array(repeating: 0, count: 7)
    }
}

/// Seven bars with per-bar smoothing lag so movement reads organic, not uniform.
struct SmoothedWaveform: View {
    let level: Float
    let state: DictationState
    let smoother: WaveSmoother
    let reduceMotion: Bool

    private let base: [CGFloat] = [0.35, 0.6, 1.0, 0.75, 0.5, 0.8, 0.4]
    private let lag: [Float] = [0.55, 0.4, 0.25, 0.35, 0.5, 0.3, 0.6]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion || !isRecording)) { context in
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barStyle(i))
                        .frame(width: 4, height: height(i, t: context.date.timeIntervalSinceReferenceDate))
                }
            }
        }
        .onChange(of: isRecording) { _, isNow in
            if isNow { smoother.reset() }
        }
    }

    private var isRecording: Bool { if case .recording = state { true } else { false } }

    /// Failure dims the whole strip — status color belongs to the orb and rim,
    /// not to metadata decoration. Active bars carry the brand teal→blue ramp.
    private func barStyle(_ i: Int) -> AnyShapeStyle {
        if case .failed = state { return AnyShapeStyle(Theme.hudWaveInactive.opacity(0.5)) }
        guard i >= 2 && i <= 4 else { return AnyShapeStyle(Theme.hudWaveInactive) }
        return AnyShapeStyle(LinearGradient(colors: [Theme.accent, Theme.hudAccentDeep],
                                            startPoint: .top, endPoint: .bottom))
    }

    private func height(_ i: Int, t: TimeInterval) -> CGFloat {
        let cap = base[i] * 22
        switch state {
        case .recording:
            let target = level < HUDView.silenceThreshold ? 0 : level
            smoother.values[i] += (target - smoother.values[i]) * lag[i]   // per-bar lag
            return max(4, cap * CGFloat(0.2 + 0.8 * smoother.values[i]))
        case .transcribing, .inserting:
            return reduceMotion ? cap * 0.5 : max(4, cap * (0.35 + 0.25 * abs(sin(t * 2 + Double(i) * 0.9))))
        case .failed: return 4
        case .idle: return cap * 0.3
        }
    }
}

/// SwiftUI's `.onHover` only reports while the app is active, but the HUD lives
/// on a non-activating panel and is almost always used while another app is
/// frontmost. An NSTrackingArea with `.activeAlways` reports hover regardless of
/// which app is active. The tracker never intercepts clicks (`hitTest` is nil),
/// so the cancel button and the drag gesture behind it keep working.
private struct ActiveAlwaysHoverTracker: NSViewRepresentable {
    var onChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackerView {
        TrackerView(onChange: onChange)
    }

    func updateNSView(_ view: TrackerView, context: Context) {
        view.onChange = onChange
    }

    final class TrackerView: NSView {
        var onChange: (Bool) -> Void

        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            ))
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func mouseEntered(with event: NSEvent) { onChange(true) }
        override func mouseExited(with event: NSEvent) { onChange(false) }
    }
}
