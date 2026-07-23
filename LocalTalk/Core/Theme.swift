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

    // HUD shell — light glass, matching the site/video pill. The HUD floats
    // over the USER'S content (usually light apps), not over Bulong's dark
    // chrome, so it carries its own light-surface text/hairline tokens and
    // must never borrow the dark-window text colors.
    static let hudShellTop = Color.white
    static let hudShellBottom = Color(red: 226/255, green: 238/255, blue: 245/255)  // #E2EEF5
    static let hudRim = Color(red: 18/255, green: 58/255, blue: 87/255).opacity(0.16)
    static let hudTitle = Color(red: 19/255, green: 50/255, blue: 75/255)           // #13324B
    static let hudDetail = Color(red: 62/255, green: 94/255, blue: 119/255)         // #3E5E77
    static let hudTertiary = Color(red: 108/255, green: 135/255, blue: 155/255)     // #6C879B
    static let hudHairline = Color(red: 18/255, green: 58/255, blue: 87/255).opacity(0.22)
    static let hudWaveInactive = Color(red: 18/255, green: 58/255, blue: 87/255).opacity(0.20)
    static let hudShadow = Color(red: 18/255, green: 58/255, blue: 87/255).opacity(0.32)
    static let hudAccentDeep = Color(red: 67/255, green: 148/255, blue: 216/255)    // #4394D8, gradient tail
    // In-window (dark chrome) inactive-wave tone — used by the HUD position
    // preview in Settings, NOT by the HUD itself.
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
