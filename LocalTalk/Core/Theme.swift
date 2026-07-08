import SwiftUI

/// Bulong design tokens. HARD RULE: no `Color(red:...)`, no system green, no ad-hoc
/// font sizes outside this file. Depth on dark = surface ladder + hairlines;
/// drop shadows only on floating panels (HUD, popover).
enum Theme {
    // Surface ladder (window -> raised -> overlay)
    static let ink0 = Color(red: 7/255, green: 9/255, blue: 11/255)
    static let ink1 = Color(red: 16/255, green: 18/255, blue: 20/255)
    static let ink2 = Color(red: 22/255, green: 24/255, blue: 26/255)

    // Hairlines
    static let hairline = Color.white.opacity(0.08)
    static let hairlineStrong = Color.white.opacity(0.12)

    // Text
    static let textPrimary = Color(red: 240/255, green: 242/255, blue: 242/255)
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.40)

    // Accent — three jobs only: live states, primary action, focus.
    static let accent = Color(red: 43/255, green: 222/255, blue: 177/255)
    static let accentText = Color(red: 176/255, green: 249/255, blue: 226/255)
    static let accentDim = accent.opacity(0.42)   // 42% alpha — composites over the surface behind it
    static let failure = Color(red: 255/255, green: 118/255, blue: 112/255)

    // HUD shell (previously hard-coded in HUDView)
    static let hudShellTop = Color(red: 10/255, green: 18/255, blue: 18/255)
    static let hudShellBottom = ink0
    static let hudRim = Color(red: 60/255, green: 104/255, blue: 96/255).opacity(0.95)
    static let waveInactive = Color(red: 86/255, green: 102/255, blue: 116/255)

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
