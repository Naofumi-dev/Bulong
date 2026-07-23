import SwiftUI

/// Bulong design tokens. HARD RULE: no `Color(red:...)`, no system green, no ad-hoc
/// font sizes outside this file. Depth on dark = surface ladder + hairlines;
/// drop shadows only on floating panels (HUD, popover).
enum Theme {
    // LIGHT-GLASS window chrome, matching bulong.app: paper-aurora over a
    // live light blur, navy type, teal accents. Surfaces are white-glass
    // fills that brighten over the blur. The HUD pill alone stays dark
    // smoked glass (hud* tokens below) — exactly like the site's hero pill.
    static let inkSolid = Color(red: 9/255, green: 20/255, blue: 32/255)      // opaque navy (dark surfaces only)
    static let paperSolid = Color(red: 243/255, green: 247/255, blue: 250/255) // opaque paper (plain NSWindows)
    static let ink0 = Color.white.opacity(0.34)   // window smoke over the blur
    static let ink1 = Color.white.opacity(0.58)   // glass card
    static let ink2 = Color.white.opacity(0.85)   // raised surface / hover
    // Aurora wash (the site's hero gradient, whispered onto the window)
    static let auroraBlue = Color(red: 67/255, green: 148/255, blue: 216/255).opacity(0.10)
    static let auroraTeal = Color(red: 63/255, green: 195/255, blue: 172/255).opacity(0.06)

    // Hairlines — navy-based, like the site
    static let hairline = Color(red: 18/255, green: 58/255, blue: 87/255).opacity(0.12)
    static let hairlineStrong = Color(red: 18/255, green: 58/255, blue: 87/255).opacity(0.22)

    // Text — the site's navy ladder
    static let textPrimary = Color(red: 19/255, green: 50/255, blue: 75/255)     // #13324B
    static let textSecondary = Color(red: 62/255, green: 94/255, blue: 119/255)  // #3E5E77
    static let textTertiary = Color(red: 108/255, green: 135/255, blue: 155/255) // #6C879B

    // Accent — three jobs only: live states, primary action, focus.
    // Deep teal (#178F7C) for contrast on light; the HUD keeps the bright
    // reference teal via hudAccent.
    static let accent = Color(red: 23/255, green: 143/255, blue: 124/255)
    static let accentText = Color(red: 15/255, green: 110/255, blue: 95/255)     // #0F6E5F
    static let accentDim = accent.opacity(0.42)   // 42% alpha — composites over the surface behind it
    static let failure = Color(red: 216/255, green: 73/255, blue: 60/255)        // site coral

    // HUD — dark smoked glass over a LIVE blur (the user's reference art):
    // translucent navy tint on ultraThinMaterial, glossy rim, light text,
    // whisper-mark tile, glowing teal wave. Tokens are HUD-local; neither the
    // dark window chrome nor the light site palette belongs on this surface.
    static let hudAccent = Color(red: 63/255, green: 195/255, blue: 172/255)     // bright reference teal
    static let hudTintTop = Color(red: 24/255, green: 40/255, blue: 52/255).opacity(0.30)
    static let hudTintBottom = Color(red: 7/255, green: 14/255, blue: 20/255).opacity(0.52)
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
