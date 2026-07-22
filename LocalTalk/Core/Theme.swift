import SwiftUI

/// Bulong design tokens. HARD RULE: no `Color(red:...)`, no system green, no ad-hoc
/// font sizes outside this file. Depth on dark = surface ladder + hairlines;
/// drop shadows only on floating panels (HUD, popover).
enum Theme {
    // Surface ladder (window -> raised -> overlay)
    static let ink0 = Color(red: 9/255, green: 20/255, blue: 32/255)
    static let ink1 = Color(red: 15/255, green: 30/255, blue: 46/255)
    static let ink2 = Color(red: 22/255, green: 41/255, blue: 60/255)

    // Hairlines
    static let hairline = Color.white.opacity(0.08)
    static let hairlineStrong = Color.white.opacity(0.12)

    // Text
    static let textPrimary = Color(red: 240/255, green: 242/255, blue: 242/255)
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.40)

    // Accent — three jobs only: live states, primary action, focus.
    static let accent = Color(red: 63/255, green: 195/255, blue: 172/255)
    static let accentText = Color(red: 176/255, green: 233/255, blue: 240/255)
    static let accentDim = accent.opacity(0.42)   // 42% alpha — composites over the surface behind it
    static let failure = Color(red: 255/255, green: 118/255, blue: 112/255)

    // HUD shell (previously hard-coded in HUDView)
    static let hudShellTop = Color(red: 20/255, green: 38/255, blue: 56/255)
    static let hudShellBottom = ink0
    static let hudRim = Color(red: 70/255, green: 120/255, blue: 150/255).opacity(0.95)
    static let waveInactive = Color(red: 96/255, green: 116/255, blue: 134/255)

    // Type scale
    enum Fonts {
        static let display = Font.system(size: 22, weight: .semibold)   // pair with .tracking(-0.4)
        static let title = Font.system(size: 15, weight: .semibold)
        static let body = Font.system(size: 13)
        static let bodyStrong = Font.system(size: 13, weight: .semibold)
        static let action = Font.system(size: 12, weight: .semibold)
        static let caption = Font.system(size: 11)
        /// Brand voice: transcripts, timers, counts, hotkey chips, model names.
        static func mono(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
    }

    // Radii — concentric rule: inner = outer − padding.
    // Shape grammar: standalone primary CTAs are capsules; cards and inline
    // card controls use radiusCard/radiusControl.
    static let radiusCard: CGFloat = 10
    static let radiusControl: CGFloat = 6
    static let radiusHUD: CGFloat = 20

    // Motion
    static let easeFast = Animation.easeOut(duration: 0.16)
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.8)
}
