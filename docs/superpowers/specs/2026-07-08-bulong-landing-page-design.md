# Bulong Landing Page — Design

Date: 2026-07-08
Status: approved by Armageddon (structure, aesthetic, $29 framing)
Phase 3 sub-project 1 of 4 (landing/privacy site). Siblings, not covered here: notarized distribution, licensing/trial, pricing finalization.

## Context and decisions (locked)

- Build the **bulong.app** marketing site: one long-scroll **landing page** + a dedicated **privacy page**.
- **Hand-built static HTML/CSS/JS**, no framework, no build step. Deploys to the user's **Hostinger** hosting.
- Direction **A + verifiability**: the page feels like the app — ink surfaces, single mint accent, mono type accents, restrained and honest. Leads with *provable* privacy (the post-Wispr-scandal wedge no competitor markets).
- Download and checkout CTAs are **placeholders wired later** to the real notarized DMG and the Lemon Squeezy checkout. Nothing here is blocked on paid accounts.
- Working price: **$29 one-time, single Mac** (between VoiceInk $25 and BetterDictation $39). Adjustable — the site keeps the price in one place so a change is one edit.

## Goals / non-goals

**Goals:** communicate the product in five seconds; establish provable-privacy trust; show the app is beautiful using our real renders; state the price honestly; drive a download. Fast (no web fonts, no framework), responsive, WCAG 2.1 AA, works with JS disabled except the mobile-nav toggle.

**Non-goals:** analytics/tracking (ironic for a privacy product — none, or a privacy-respecting count-only tool deferred), blog, changelog, account/login, a CMS, e-commerce beyond a single outbound checkout link.

## Site structure

```
site/
  index.html          landing (long scroll)
  privacy.html        the deep privacy page
  styles.css          Bulong tokens + layout (one shared sheet)
  main.js             mobile-nav toggle + smooth-scroll only
  assets/
    icon.png          the rendered app icon (favicon + logo)
    og.png            social share image (1200x630, ink + wordmark + orb)
    hud-*.png, popover.png, history.png, settings.png   app renders
```

No inline styles in markup beyond trivial one-offs; all theme values are CSS custom properties in `:root` so a price/color change is one place.

## Landing page — sections and copy

Copy voice matches the app's microcopy: plain, honest, sentence case, no hype words ("simply", "seamless", "unlock"). Draft copy below is the shipping copy unless noted.

1. **Nav** — mono `bulong` wordmark + mint square glyph; links: Features · Privacy · Pricing; a small "Download" button. Sticky, ink with a hairline bottom border. Mobile: hamburger toggling a full-width menu.

2. **Hero** — badge "100% on-device · nothing uploaded, ever"; H1 "Your voice never leaves your **Mac**." (Mac in mint); sub "Press a hotkey in any app, speak, and the words appear. Fast, accurate dictation that runs entirely on your Mac — no cloud, no account, no telemetry."; primary "Download for macOS" + mono "Free to try · $29 once"; the HUD pill visual (breathing orb, waveform, ON-DEVICE badge — CSS recreation, animated with `prefers-reduced-motion` respected). Sub-line: "Apple Silicon · macOS 14+".

3. **Provably private** — headline "Private by architecture, not by promise." Three short columns: (a) *No cloud* — transcription runs on-device with NVIDIA Parakeet and Whisper; (b) *No account* — no sign-up, no email, no license server; (c) *No telemetry* — the app makes exactly one kind of network request: downloading a speech model, once. Then the killer line in a bordered callout: **"Turn off your Wi-Fi and dictate. It still works. That's the whole point."** with a small "See exactly what's handled →" link to privacy.html.

4. **How it works** — "Three keys and your voice." Steps: 1 Press your hotkey (⌃⌥Space, remappable) · 2 Speak naturally · 3 The text appears where your cursor is. Each with a small mono-numbered card.

5. **See it** — "Designed to disappear." A showcase of real app surfaces (History window, the menu-bar popover, Settings) as framed screenshots on the ink background, one short caption each. These come from the session renders.

6. **Features** — "Everything you need, nothing you don't." Restrained grid (2×3 or 3×2): On-device Parakeet + Whisper · Works in every app · Push-to-talk or toggle · Custom hotkey · Local searchable history · 25+ languages incl. Filipino (Tagalog) · Translate to English · Your clipboard is preserved. Icons via a tiny inline-SVG set or an SF-Symbol-style set embedded as SVG (no icon web-font).

7. **Bulong vs. the cloud** — "Why on-device wins." A compact honest table, three columns: Bulong / typical cloud dictation / Apple's built-in. Rows (only claims Bulong actually ships today): where audio goes (this Mac / their servers / this Mac), price (one-time / monthly / free), account required (no / yes / no), works offline (yes / no / yes), history you can read and export (plaintext file / their database / none). No competitor names in the header — "typical cloud dictation app." Every "Bulong" cell must be literally true of the shipping app; no aspirational features.

8. **Pricing** — "One price. No subscription, ever." One card: **$29** once · one Mac · free trial · lifetime updates for 1.0 · 14-day refund. Price rendered from a single source (a `data-price` span read once) so it's one edit. Single license for v1 — no speculative tiers on the page.

9. **FAQ** — accordion (details/summary, works without JS): Is it really offline? · Which Macs? (Apple Silicon, macOS 14+) · Do I need to install anything else? (no — models download in-app) · How big is the download? (~600 MB English model, one time) · Can I use it in [Slack/VS Code/…]? (any app with a text field) · Refunds? (14 days) · Updates? (auto, via Sparkle) · Why "Bulong"? (Tagalog for "whisper").

10. **Footer CTA + footer** — repeat "Download for macOS" + price; footer with wordmark, Privacy link, contact email, the required "Includes NVIDIA Parakeet, © NVIDIA, CC-BY-4.0", copyright.

## Privacy page (privacy.html)

Own page, same chrome. Headline "How Bulong handles your voice." Plain-language, specific, verifiable:

- **What is captured** — audio only while you hold/toggle recording; written to a temporary file on your Mac and deleted after transcription.
- **Where transcription happens** — entirely on-device (Parakeet/Whisper via CoreML); your audio and text never touch a network.
- **What is stored** — transcripts in a plaintext file in Application Support you can open, search, export, or delete; settings in macOS preferences. Nothing else.
- **What leaves your Mac** — exactly one thing: downloading a speech model from Hugging Face the first time you use it. After that, nothing — no analytics, no crash reporting, no license check.
- **How to verify it yourself** — turn off Wi-Fi and dictate; or watch with Little Snitch / macOS firewall and see no traffic after models are present.
- **Permissions and why** — Microphone (to hear you), Accessibility (to type into the focused app); both are macOS-gated and revocable.
- **Contact** — email for privacy questions. Last-updated date.

This page is deliberately a selling point, linked from the hero's privacy section and the footer.

## Visual system

- Tokens mirror the app (`styles.css` `:root`): `--ink0 #07090B`, `--ink1 #101214`, `--ink2 #16181A`, `--mint #2BDEB1`, `--mint-text #B0F9E2`, `--hairline rgba(255,255,255,.08)`, `--text #F0F2F2`, `--text-2 rgba(255,255,255,.62)`, `--text-3 rgba(255,255,255,.40)`, `--radius-card 12px`, `--radius-pill 999px`.
- Type: system stack `-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif`; mono stack `ui-monospace, "SF Mono", Menlo, monospace` for the wordmark, badges, price, timers, and stat/mono accents (the brand voice). No web fonts.
- Depth = surface ladder + hairlines; shadows only on floating elements (the hero HUD, pricing card). One accent (mint), three jobs (primary CTA, the live/hero moment, links/focus).
- `-webkit-font-smoothing: antialiased`; images get a hairline inset outline; `text-wrap: balance` on headings, `pretty` on short body; `tabular-nums` on the price.
- Motion: CSS transitions only; the hero orb/waveform is a subtle keyframe that fully stops under `prefers-reduced-motion: reduce`. Enter animations optional and reduced-motion-gated. Press/hover states on all buttons and the FAQ.

## Assets

- **Icon** → `assets/icon.png` (from `LocalTalk/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512.png`), used as favicon and nav logo.
- **App surfaces** → copy the best session renders (`.../scratchpad/renders2/`): `history_with_entries.png`, `popover_idle.png`, `settings_full_page.png`, and a HUD state for the "See it" section. Present them framed (subtle window chrome or a hairline card) so they read as product shots.
- **OG image** (`assets/og.png`, 1200×630) — ink background, mono `bulong` wordmark, the orb, tagline. Generated once by a small CoreGraphics script mirroring `script/render_icon.swift` and committed as a static asset (no build-time generation).
- The HUD hero visual is a **CSS/HTML recreation** (not a PNG) so it's crisp and can animate.

## Deployment

- Static files; deployable by uploading `site/` to Hostinger's `public_html` for bulong.app, or via the Hostinger MCP/hosting tools with the user's authorization. The spec does not automate purchase/DNS — the domain is already registered; pointing it and uploading is a documented step, done with the user.
- A `site/README.md` documents: how to preview locally (`python3 -m http.server` in `site/`), where the download/checkout placeholders live (a single `config`/data-attribute), and the deploy step.

## Accessibility & review

- WCAG 2.1 AA: semantic landmarks (`header/nav/main/section/footer`), one `h1`, ordered headings, `alt` on every image (`alt=""` on decorative), `aria-label` on icon-only controls, visible focus states, ≥4.5:1 contrast (verify mint-on-ink and the muted grays), the mobile nav keyboard-operable, FAQ via native `details/summary`.
- After build, self-review against better-design `get-review-rules` (this is genuine web, so the rules apply directly) and fix every critical/serious issue before presenting.

## Testing / verification

- Preview locally and screenshot desktop + mobile widths (Claude Preview or a local server).
- Responsive check at 375 / 768 / 1280.
- Validate HTML (no broken structure), confirm zero external network requests except the (placeholder) download/checkout links, confirm the page works with JS off (only the mobile nav degrades to always-open).
- A short design-critique pass on the rendered page (same harsh lens used for the app), plus a real-content check that no "TODO"/lorem remains.

## Out of scope (later Phase 3 sub-projects)

Notarized DMG + Sparkle (distribution), offline signed-license validation + trial (licensing), final pricing/tier decision, payment provider account. The download/checkout links stay placeholders until those land. Also deferred: analytics, blog/changelog, additional locales of the site, A/B testing.
