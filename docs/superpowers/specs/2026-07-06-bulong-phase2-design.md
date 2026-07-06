# Bulong Phase 2 — Identity & Design System

Date: 2026-07-06
Status: approved by Armageddon (direction, name, scope)
Builds on: `2026-07-06-localtalk-foundation-design.md` (foundation v1, complete on branch `foundation-v1`)

## Decisions (locked)

- **Name:** the app becomes **Bulong** (Tagalog: *whisper*). Rationale: owns the category's core metaphor while Superwhisper/MacWhisper/whisper.cpp fight over the English word; only soft collisions (a Filipino song, a tiny secrets web app); bulong.app available at decision time. Tagline: *"Your voice never leaves your Mac."*
- **Direction:** "quiet instrument with a living HUD" — flat ink surfaces, hairline borders, disciplined mint, mono type as the brand voice; theatrical treatment reserved for exactly one moment: the HUD while listening.
- **Grounding:** UI audit found one designed surface (HUD ~90% intentional) and template shells everywhere else (menu dropdown 0% brand, Settings ~5%, History ~15%, onboarding ~20%). Market research: no dictation app owns "beautiful"; premium-dark = surface ladder + hairlines + one-accent discipline + motion quality.

## 1. Identity

**Rename mechanics.** Product/display/menu-bar name, wordmark, and About box become Bulong. Bundle id changes to `com.armageddonvivas.Bulong` (pre-launch, no customers — cleanest moment). First launch migrates: UserDefaults from the old domain (`com.armageddonvivas.LocalTalk`), and `~/Library/Application Support/LocalTalk/` → `.../Bulong/` (history.jsonl + whisperkit models dir). Migration is one-way, idempotent, and silent on absence. TCC permissions (mic, Accessibility) reset with the new bundle id — acceptable now; onboarding already handles re-granting. The Xcode target, scheme, and `project.yml` rename to Bulong; repo directory name stays as-is.

**Wordmark.** Lowercase `bulong` in SF Mono (or the app's mono token), typically beside the waveform glyph; menu bar keeps a template glyph (no text).

**App icon.** Built with Apple Icon Composer as a layered `.icon`: near-black ink squircle, single mint whisper-waveform glyph, gradient allowed inside the glyph only, legible at 16px. Replaces the current PNG iconset (which stays as a fallback for macOS 14/15 builds via the asset catalog).

**Attribution.** The NVIDIA Parakeet CC-BY-4.0 line stays in Settings' footer and the About box.

## 2. Theme 2.0 — tokens

`Theme.swift` becomes the single source of truth; **no hard-coded colors outside it** (the HUD's inline gradient/border/slate values migrate in). Token set:

| Group | Tokens | Values |
|---|---|---|
| Surfaces | `ink0` window, `ink1` raised, `ink2` overlay | rgb(7,9,11) / rgb(16,18,20) / rgb(22,24,26) |
| Hairlines | `hairline`, `hairlineStrong` | white 8% / white 12% |
| Text | `textPrimary`, `textSecondary`, `textTertiary` | #F0F2F2 / white 62% / white 40% |
| Accent | `accent` (mint), `accentText`, `accentDim` (borders/strokes) | rgb(43,222,177) / rgb(176,249,226) / mint 42% |
| Status | `failure` coral; success = mint (system `.green` is banned) | rgb(255,118,112) |
| Type | `display` (22 semibold, −2% tracking), `body` (13), `caption` (11), `mono` (SF Mono; transcripts, timers, counts, hotkey chips, model names) | |
| Radius | `radiusCard` 10, `radiusControl` 6, HUD 20 continuous; concentric rule: inner = outer − padding | |
| Motion | `easeFast` 0.16s easeOut, `spring` (response 0.38, damping 0.8); every animation checks Reduce Motion | |

Depth on dark = ladder + hairlines. Drop shadows only on floating panels (HUD, popover), never inside windows. Mint's three jobs: live states, primary action, focus. Grays carry a cold green-blue cast (already true of the ink ramp).

## 3. Surfaces

**Menu bar popover** (`MenuBarExtra` switches to `.window` style — new `MenuPopoverView`): ink2 panel, hairline rim. Header: status orb (idle dot / breathing mint while recording) + `bulong` wordmark + state text. Primary action row with rendered hotkey chip (keycap style, mono). While recording: live mini-waveform + elapsed time. Last transcript snippet (mono, 2-line clamp, click to copy). Footer row: History · Settings · Quit as quiet text buttons with hover states.

**Main window shell**: sidebar rows get hover + selected states on the ladder (replacing default `.sidebar` list styling where feasible without fighting AppKit); detail pane sits on `ink0` with content cards on `ink1`; section switches cross-fade with `easeFast` instead of hard cuts. Titlebar: `.titlebarAppearsTransparent` look, window min size unchanged.

**History**: rows become cards (`ink1`, hairline, `radiusCard`) with hover lift (background → `ink2`); transcript text in `mono` 13; metadata strip unchanged in content (app · time · engine · language) with engine in `accentText`; filtering animates insert/remove; empty state is designed: small mint line-art waveform (SF Symbol composition is fine — no asset pipeline), headline "Your dictations will appear here", body with a rendered hotkey keycap chip, and a "Try it now" button that starts dictation.

**Settings**: stock controls inside designed containers — each section a card on `ink1` with a hairline and a caption description; status-reactive hint copy for permissions ("Waiting for microphone…" → "Connected ✓" in mint); model rows show size + progress percentage + cancel; the hotkey recorder renders as a keycap chip that pulses mint while capturing; the HUD-position setting shows a live miniature preview of the pill in each preset position.

**Onboarding**: three borderless branded screens in the hosted window (title bar hidden, ink0 background, radius matching Tahoe geometry): (1) promise — wordmark, tagline, one line of what happens next; (2) permissions — two live-status cards (mic, Accessibility) with real reasons, granted states flip to mint checks without re-prompting; (3) first dictation — guided test field with the hotkey chip, live partial text, and a mint "it worked" payoff moment. Step dots at the bottom; spring transitions between steps; Back preserved. Model download lives in step 3's flow (blocking state with progress) rather than its own screen.

## 4. The living HUD

- **Orb**: the brand mark slot becomes a breathing mint radial orb whose glow radius/intensity tracks the live mic level (SwiftUI `TimelineView` + gradients; no Metal shader dependency). Silence reads as silence: below a low level threshold the orb settles to a calm minimum and the waveform flattens — motion only with real signal.
- **Waveform**: keeps 7 bars but amplitudes get per-bar smoothing/lag so movement reads organic rather than uniform.
- **States** (existing five stay): recording = orb alive + mint; transcribing = orb steady pulse + bars in idle sine; inserted = brief mint check moment; failed = coral, flatline, readable message. Shape+motion encode state, not color alone.
- **Interaction**: hover over the pill reveals cancel while recording (currently cancel only exists during transcribing); Esc behavior unchanged; drag unchanged; new position presets (bottom-center / top-right / near-notch) in Settings, persisted per display as today.
- **Colors** all from Theme tokens; pill stays ~94% opaque ink with a hairline rim highlight (no behind-window blur — controllable over any wallpaper).

## 5. Housekeeping

- Quit the legacy prototype process (running from `dist/` since Jul 5, competing for the hotkey) and delete `dist/` (already gitignored). `SourcesObjC/` stays in the repo as reference.
- `script/dev_build.sh`'s `pkill -x LocalTalk` hazard disappears with the rename (new process name Bulong); the script gets the new names.
- README updated to Bulong (name story + tagline).

## Error handling

No new failure modes are introduced; the redesign must preserve every existing honest-status behavior (paste honesty, watchdog, cancel paths, model-download failure states). Any surface change that touches a state machine keeps the existing AppModel contract — this phase is visual/UX only, plus the rename migration.

## Testing & verification

- Unit tests: rename-migration (defaults + Application Support move: fresh install, old-data present, already-migrated), plus existing suite stays green under the new bundle id/target name.
- Visual verification: after each surface lands, screenshot and compare against this spec's requirements; final pass is a harsh design-taste critique of every surface (hover states present, hairlines not shadows, mint discipline held, motion tokens used, no stock tells remaining from the audit's list).
- Manual smoke: the foundation checklist still passes end-to-end under the new name.

## Out of scope (Phase 3)

Website/landing page, licensing/trial/payments, personal dictionary, local AI cleanup, SpeechAnalyzer backend, App Store — all after the brand lands. Domain registration (bulong.app) is in progress separately on Hostinger and does not block this phase.
