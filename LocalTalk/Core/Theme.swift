import SwiftUI

/// Bulong design tokens. HARD RULE: no `Color(red:...)`, no system green, no ad-hoc
/// font sizes outside this file. Depth on dark = surface ladder + hairlines;
/// drop shadows only on floating panels (HUD, popover).
enum Theme {
    // Surface ladder (window -> raised -> overlay). The window itself is a
    // live blur (VisualEffectBackground); ink0 is the navy smoke tinting it,
    // ink1/ink2 are glass fills that BRIGHTEN over the blur — same smoked-
    // glass language as the HUD pill and the reference art.
    static let inkSolid = Color(red: 9/255, green: 20/255, blue: 32/255)  // opaque base (plain NSWindows)
    static let ink0 = Color(red: 9/255, green: 20/255, blue: 32/255).opacity(0.52)
    static let ink1 = Color.white.opacity(0.06)
    static let ink2 = Color.white.opacity(0.115)

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

    // HUD — dark smoked glass over a LIVE blur (the user's reference art):
    // translucent navy tint on ultraThinMaterial, glossy rim, light text,
    // whisper-mark tile, glowing teal wave. Tokens are HUD-local; neither the
    // dark window chrome nor the light site palette belongs on this surface.
    static let hudTintTop = Color(red: 24/255, green: 40/255, blue: 52/255).opacity(0.42)
    static let hudTintBottom = Color(red: 7/255, green: 14/255, blue: 20/255).opacity(0.66)
    static let hudRim = Color.white.opacity(0.28)
    static let hudRimGlow = Color(red: 63/255, green: 195/255, blue: 172/255).opacity(0.5)
    static let hudTitle = Color.white.opacity(0.94)
    static let hudDetail = Color(red: 173/255, green: 199/255, blue: 212/255)
    static let hudTertiary = Color(red: 150/255, green: 178/255, blue: 192/255).opacity(0.85)
    static let hudHairline = Color.white.opacity(0.22)
    static let hudWaveInactive = Color.white.opacity(0.20)
    static let hudShadow = Color.black.opacity(0.5)
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
