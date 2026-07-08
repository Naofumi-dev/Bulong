import SwiftUI

/// Shared UI state that outlives individual scenes (e.g. which main-window
/// pane is selected, so the popover can deep-link into History or Settings).
@MainActor
@Observable
final class UIState {
    var mainSection: MainSection = .history
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
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Caption sits on the card's inner label rail (= card padding).
            Text(title.uppercased())
                .font(Theme.Fonts.mono(10, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .padding(.leading, 14)
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.radiusCard).fill(Theme.ink1))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).stroke(Theme.hairline, lineWidth: 1))
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
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(configuration.isOn ? Theme.accent : .clear)
                RoundedRectangle(cornerRadius: 4)
                    .stroke(configuration.isOn ? Theme.accent : Theme.hairlineStrong, lineWidth: 1)
                if configuration.isOn {
                    Image(systemName: "checkmark")
                        .font(Theme.Fonts.mono(9, weight: .bold))
                        .foregroundStyle(Theme.ink0)
                }
            }
            .frame(width: 16, height: 16)
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

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.action)
            .foregroundStyle(emphasized ? Theme.accentText : Theme.textPrimary)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: Theme.radiusControl)
                .fill(hovering ? Theme.ink2 : .clear))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusControl)
                .stroke(Theme.hairlineStrong, lineWidth: 1))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .onHover { hovering = $0 }
            .animation(Theme.easeFast, value: hovering)
    }
}
