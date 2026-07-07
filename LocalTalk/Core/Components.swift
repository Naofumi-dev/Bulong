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
            .foregroundStyle(Theme.accentText)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusControl)
                    .fill(Theme.ink2)
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusControl)
                        .stroke(pulsing && pulse ? Theme.accent : Theme.hairlineStrong, lineWidth: 1))
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
            Text(title.uppercased())
                .font(Theme.Fonts.mono(10, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.radiusCard).fill(Theme.ink1))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).stroke(Theme.hairline, lineWidth: 1))
            if let footer {
                Text(footer).font(Theme.Fonts.caption)
                    .foregroundStyle(footerIsError ? Theme.failure : Theme.textTertiary)
                    .padding(.leading, 4)
            }
        }
    }
}

/// Quiet text button that gains an ink2 pill on hover.
struct HoverButtonStyle: ButtonStyle {
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.body)
            .foregroundStyle(hovering ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: Theme.radiusControl)
                .fill(hovering ? Theme.ink2 : .clear))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .onHover { hovering = $0 }
            .animation(Theme.easeFast, value: hovering)
    }
}

/// Small live level bars (shared by popover + settings preview).
struct LevelBars: View {
    let level: Float
    let active: Bool
    private let heights: [CGFloat] = [0.4, 0.75, 1.0, 0.65, 0.45]

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(active ? Theme.accent : Theme.waveInactive)
                    .frame(width: 3, height: max(3, heights[i] * 16 * (active ? CGFloat(0.3 + 0.7 * level) : 0.3)))
            }
        }
        .animation(Theme.easeFast, value: level)
    }
}

/// Onboarding step indicator.
struct StepDots: View {
    let count: Int
    let index: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Theme.accent : Theme.hairlineStrong)
                    .frame(width: i == index ? 18 : 6, height: 6)
            }
        }
        .animation(Theme.spring, value: index)
    }
}
