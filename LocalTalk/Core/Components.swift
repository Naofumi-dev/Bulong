import SwiftUI

/// Shared UI state that outlives individual scenes (e.g. which main-window
/// pane is selected, so the popover can deep-link into History or Settings).
/// Live AppKit blur (`.behindWindow` samples whatever is UNDER the window —
/// wallpaper, other apps) — the smoked-glass base every dashboard surface
/// tints over. AppKit manages the transparency; no window config needed.
/// The whisper mark with the site hero's gentle float — slow bob and tilt,
/// a soft teal glow. The brand's "premium" motion beat; still under Reduce
/// Motion. Size is the mark's frame; the float stays within ~4pt of it.
struct FloatingMark: View {
    var size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floating = false

    var body: some View {
        Image("WhisperMark")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .shadow(color: Theme.accent.opacity(0.35), radius: size * 0.16, y: size * 0.06)
            .rotationEffect(.degrees(floating ? 1.2 : -1.2))
            .offset(y: floating ? -4 : 2)
            .animation(reduceMotion ? nil : .easeInOut(duration: 3.4).repeatForever(autoreverses: true),
                       value: floating)
            .onAppear { if !reduceMotion { floating = true } }
    }
}

/// The site's paper-aurora wash: blue glow from the top, a teal whisper
/// below it, fading out by mid-window. Pure decoration — never hit-testable.
struct AuroraWash: View {
    var body: some View {
        LinearGradient(colors: [Theme.auroraBlue, Theme.auroraTeal, .clear],
                       startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.7))
            .allowsHitTesting(false)
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

enum SettingsTab: Hashable { case setup, advanced }

@MainActor
@Observable
final class UIState {
    var mainSection: MainSection = .history
    /// Shared so the trial-expired path can deep-link straight to the
    /// Advanced tab, where the License card (and its Buy button) lives.
    var settingsTab: SettingsTab = .setup
}

/// Keycap-styled hotkey chip, mono type. The brand's rendering of a shortcut.
struct HotkeyChip: View {
    let text: String
    var pulsing = false
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(text)
            .font(Theme.Fonts.mono(11, weight: .medium))
            .tracking(0.5)
            .foregroundStyle(Theme.accentText)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusControl)
                    .fill(Theme.ink2)
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusControl)
                        .stroke(pulsing && (pulse || reduceMotion) ? Theme.accent : Theme.hairlineStrong, lineWidth: 1))
            )
            .onAppear { startPulseIfNeeded() }
            .onChange(of: pulsing) { _, isPulsing in
                if isPulsing {
                    startPulseIfNeeded()
                } else {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { pulse = false }
                }
            }
    }

    private func startPulseIfNeeded() {
        guard pulsing, !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.7).repeatForever()) { pulse = true }
    }
}

/// Section container: caption title above an ink1 card with a hairline.
struct SectionCard<Content: View>: View {
    let title: String
    var footer: String? = nil
    var footerIsError: Bool = false
    var accentStroke: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Caption sits on the card's inner label rail (= card padding).
            Text(title.uppercased())
                .font(Theme.Fonts.mono(10, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.leading, 14)
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.radiusCard).fill(Theme.ink1))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).stroke(accentStroke ? Theme.accent : Theme.hairline, lineWidth: 1))
            if let footer {
                Text(footer).font(Theme.Fonts.caption)
                    .foregroundStyle(footerIsError ? Theme.failure : Theme.textTertiary)
                    .padding(.leading, 14)
            }
        }
    }
}

/// Quiet text button that gains an ink2 pill on hover.
struct HoverButtonStyle: ButtonStyle {
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.body)
            .foregroundStyle(hovering ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: Theme.radiusControl)
                .fill(hovering ? Theme.ink2 : .clear))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .onHover { hovering = $0 }
            .animation(Theme.easeFast, value: hovering)
    }
}

/// Tactile press feedback for buttons that draw their own label/background
/// (the primary CTAs and custom controls that otherwise use `.plain`). A press
/// scale is the highest-value micro-interaction — it acknowledges every tap.
/// Gated on Reduce Motion to keep the app's motion posture airtight.
struct TactilePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(Theme.easeFast, value: configuration.isPressed)
    }
}

/// Small live level bars (shared by popover + settings preview).
struct LevelBars: View {
    let level: Float
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let heights: [CGFloat] = [0.4, 0.75, 1.0, 0.65, 0.45]

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(active ? Theme.accent : Theme.waveInactive)
                    .frame(width: 3, height: max(3, heights[i] * 16 * (active ? CGFloat(0.3 + 0.7 * level) : 0.3)))
            }
        }
        // Waveform motion: still tracks the level under Reduce Motion, but
        // snaps instead of animating.
        .animation(reduceMotion ? nil : Theme.easeFast, value: level)
    }
}

/// Onboarding step indicator.
struct StepDots: View {
    let count: Int
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Theme.accent : Theme.hairlineStrong)
                    .frame(width: i == index ? 18 : 6, height: 6)
            }
        }
        // The active dot stretches and its neighbors shift — a spring mover.
        .animation(reduceMotion ? nil : Theme.spring, value: index)
    }
}

/// Segmented choice as text buttons in a hairline capsule — replaces the stock
/// NSSegmentedControl, which ignores tint and reads system-gray amid the ink UI.
struct SegmentedChoice<Value: Hashable>: View {
    let options: [(label: String, value: Value)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(Theme.Fonts.body)
                        .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(selected ? Theme.ink2 : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(TactilePressStyle())
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(Capsule().stroke(Theme.hairlineStrong, lineWidth: 1))
    }
}

/// Checkbox toggle on brand: mint fill + ink0 checkmark when on,
/// hairlineStrong ring when off. Replaces the accent-colored system checkbox.
struct MintToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack {
                configuration.label
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(configuration.isOn ? Theme.accent : .clear)
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(configuration.isOn ? Theme.accent : Theme.hairlineStrong, lineWidth: 1)
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(Theme.Fonts.mono(9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 16, height: 16)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(TactilePressStyle())
    }
}

/// Pop-up picker with a designed collapsed label (current value + chevrons in a
/// hairline control). The opened menu is intentionally the stock system menu.
struct MenuPicker<Value: Hashable>: View {
    let options: [(label: String, value: Value)]
    @Binding var selection: Value

    private var currentLabel: String {
        options.first(where: { $0.value == selection })?.label ?? ""
    }

    var body: some View {
        Menu {
            ForEach(options, id: \.value) { option in
                Button(option.label) { selection = option.value }
            }
        } label: {
            HStack(spacing: 6) {
                Text(currentLabel)
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(Theme.Fonts.mono(9, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.ink1))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusControl)
                .stroke(Theme.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}

/// Minimal bordered affordance for card actions (Grant/Download/Retry).
/// Quiet text buttons (Export/Clear) stay HoverButtonStyle.
struct BorderedActionButtonStyle: ButtonStyle {
    var emphasized = false
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.action)
            .foregroundStyle(isEnabled ? (emphasized ? Theme.accentText : Theme.textPrimary) : Theme.textTertiary)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: Theme.radiusControl)
                .fill(isEnabled && hovering ? Theme.ink2 : .clear))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusControl)
                .stroke(Theme.hairlineStrong, lineWidth: 1))
            .scaleEffect(isEnabled && configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .onHover { hovering = $0 }
            .animation(Theme.easeFast, value: hovering)
    }
}
