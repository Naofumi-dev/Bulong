# Bulong Settings Redesign — Implementation Plan

**Goal:** Reframe the Settings window from a flat config dump into a friendly get-dictating flow: a Set up / Advanced tab split, a state-aware hero, essentials-first order, mint (not system-blue) nav, and a set of clarity/contrast/a11y fixes — all using existing Theme tokens + components.

**Source:** multi-lens design critique (workflow wf_20945757-b4a), user approved scope = "Add Set up / Advanced tabs" (fullest).

**Constraints (hard):** Native SwiftUI. No `Color(red:` outside Theme.swift; no `.green`; no ad-hoc font sizes (Theme.Fonts.* only). Reuse SectionCard / SegmentedChoice / MenuPicker / MintToggleStyle / HotkeyChip / BorderedActionButtonStyle / HUDPositionPreview. Do NOT touch MigrationService.settingsKeys (frozen). Do NOT change the hotkey monitor / audio / licensing crypto. Commits end `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`; explicit `git add` paths only (never -A; mp3s at repo root must stay untracked).

---

## Task A — Foundations: mint nav, component tweaks, recommendation helper

**Files:** MainWindowView.swift, Core/Components.swift, new Core/ModelRecommendation.swift, LocalTalkTests/ModelRecommendationTests.swift

- **A1. Mint sidebar nav (kill system blue).** In `MainWindowView`, replace the `List(MainSection.allCases, selection:)` + `.listStyle(.sidebar)` with a custom `VStack` of `.buttonStyle(.plain)` rows that set `uiState.mainSection`. Each row: leading 2pt `Capsule().fill(selected ? Theme.accent : .clear)` (height ~16), `Image(systemName: item.icon)`, `Text(item.rawValue)`, `Spacer()`; foreground `selected ? Theme.textPrimary : Theme.textSecondary`; row background `RoundedRectangle(cornerRadius: Theme.radiusControl).fill(selected ? Theme.ink2 : .clear)`; `.contentShape(Rectangle())`; padding H10 V6. Keep `brandHeader` pinned at top, `Theme.ink0` background, and the `.navigationSplitViewColumnWidth(min: 168, ideal: 188)`. Trailing `Spacer()` fills the column.
- **A2. Titlebar names the pane.** Add `.navigationTitle(uiState.mainSection.rawValue)` to the detail branch so the titlebar stops repeating "Bulong". Verify visually after build; if the large title wastes space, keep it — naming the pane is the goal.
- **A3. Reduce-motion on the pane cross-fade.** Add `@Environment(\.accessibilityReduceMotion) private var reduceMotion` to MainWindowView; change the detail `.animation(Theme.easeFast, value: uiState.mainSection)` to `.animation(reduceMotion ? nil : Theme.easeFast, value:)`.
- **A4. SectionCard: readable header + optional accent stroke.** In Components.swift `SectionCard`: change the title `.foregroundStyle(Theme.textTertiary)` → `Theme.textSecondary` (clears WCAG AA; applies app-wide, intended). Add `var accentStroke: Bool = false`; when true the card body overlay stroke uses `Theme.accent` (lineWidth 1) instead of `Theme.hairline`. Footer stays `textTertiary`.
- **A5. BorderedActionButtonStyle respects disabled.** Add `@Environment(\.isEnabled) private var isEnabled`. When `!isEnabled`: foreground `Theme.textTertiary`, no hover fill, no press scale (so a disabled Activate reads disabled).
- **A6. MintToggleStyle becomes a full-width labeled row.** Update `MintToggleStyle.makeBody` to render, inside the Button, an `HStack { configuration.label.font(Theme.Fonts.body).foregroundStyle(Theme.textPrimary); Spacer(); <the 16×16 box> }` with `.contentShape(Rectangle())` so the whole row toggles and the label is clickable. Grep confirms MintToggleStyle is used only in SettingsView; update those call sites in Task B (pass the title as the Toggle label, drop `labelsHidden()` and the `row()` wrapper for toggles).
- **A7. Recommendation helper (TDD).** New `Core/ModelRecommendation.swift`:
  ```swift
  enum RecommendedModel: Equatable { case parakeetV2, parakeetV3, whisper }
  enum ModelRecommendation {
      /// Which bundled model best fits the chosen dictation language.
      static func model(forLanguage code: String) -> RecommendedModel {
          switch code {
          case "en": return .parakeetV2                       // English — fast
          case "es", "fr", "de", "it", "pt": return .parakeetV3   // European languages
          default: return .whisper                            // tl, ja, ko, zh, everything else
          }
      }
  }
  ```
  Test `ModelRecommendationTests`: en→parakeetV2; es/fr/de/it/pt→parakeetV3; tl/ja/ko/zh/unknown→whisper.
- **A8.** `xcodegen generate`, build, run tests (baseline 56 → 57+). Commit.

## Task B — Settings reframe + content (depends on A)

**File:** LocalTalk/UI/MainWindow/SettingsView.swift

- **B1. Capped, centered column.** Wrap the content VStack: `.frame(maxWidth: 600)` then `.frame(maxWidth: .infinity, alignment: .center)` so the reading column centers in the ScrollView and label↔control gaps collapse. Keep the `.padding(20)`.
- **B2. Extract each card to a computed `private var` (`generalCard`, `dictationCard`, `hotkeyCard`, `recordingPillCard`, `modelsCard`, `permissionsCard`, `licenseCard`)** to make the tab switch readable. Behavior identical to today except where noted below.
- **B3. Set up / Advanced tabs.** Add `private enum SettingsTab: Hashable { case setup, advanced }` and `@State private var tab: SettingsTab = .setup`. Top of the column: `SegmentedChoice(options: [("Set up", .setup), ("Advanced", .advanced)], selection: $tab)`. Render `tab == .setup` → `hero, permissionsCard, hotkeyCard, modelsCard`; `.advanced` → `dictationCard, recordingPillCard, generalCard, licenseCard`. Every existing setting stays reachable.
- **B4. State-aware hero (first child of Set up).** `private var setupComplete: Bool { micGranted && axTrusted && recommendedModelReady }` where `recommendedModelReady` maps `ModelRecommendation.model(forLanguage: model.settings.language)` to the matching `modelManager` state == `.ready`. When complete: a mint `Label("You're ready", systemImage: "checkmark.circle.fill")` (Theme.accent) + a line "Press <trigger> anywhere to dictate", where <trigger> is `HotkeyChip(text: model.settings.hotkey.displayString)` for `.combo` or `Text("tap \(model.settings.singleKeyChoice.displayName)")` for `.singleKey`. When incomplete: a compact 2-step checklist — "Allow microphone" and "Grant Accessibility" — each a done state (checkmark.circle.fill / Theme.accent) or pending (Theme.textSecondary label + the same Grant action buttons the Permissions card uses). Theme.Fonts only; no ad-hoc sizes. Keep it calm and short.
- **B5. Permissions leads + emphasized while incomplete.** `permissionsCard` uses `SectionCard(title: "Permissions", accentStroke: !(micGranted && axTrusted))`. Mic `grantedHint` "Connected ✓" → "Granted ✓ — Bulong can hear you".
- **B6. Toggle rows → labeled MintToggle.** Replace the 3 `row("…"){ Toggle("", isOn:).toggleStyle(MintToggleStyle()).labelsHidden() }` (Launch at login, Paste into the focused app, Play sounds) with `Toggle("…", isOn: binding).toggleStyle(MintToggleStyle())` (full-row tappable per A6).
- **B7. Paste ↔ Accessibility loop.** In `dictationCard`, when `!axTrusted && model.settings.pasteAfterTranscription`, show a caption under the Paste row: "Needs Accessibility — grant it in Set up" in `Theme.accent`.
- **B8. Model rows.** Rename card "Models" → "Speech models". Lead each row with the meaningful choice, demote the codename to the descriptor:
  - "English — fast" / desc "Parakeet" / ~600 MB / `parakeetV2`
  - "European languages" / desc "Parakeet" / ~1 GB / `parakeetV3`
  - "All languages + translate" / desc "Whisper" / ~600 MB / `whisperLargeTurbo`
  Add a `recommended: Bool` param to `modelRow`; when true, render a "Recommended" tag (Theme.Fonts.caption, Theme.accent) inline after the title. Compute per row from `ModelRecommendation.model(forLanguage: model.settings.language)`. Add SectionCard footer: "English is ready — download another only if you dictate in other languages."
- **B9. Recording pill card.** Rename "Dictation bar" → "Recording pill"; add SectionCard footer "The small pill shown while you talk — choose where it sits." Add reduce-motion guard to `HUDPositionPreview` (`.animation(reduceMotion ? nil : Theme.easeFast, value: selected)` with an `@Environment(\.accessibilityReduceMotion)`).
- **B10. License polish.** Add `@FocusState private var keyFieldFocused: Bool`; `.focused($keyFieldFocused)` on the TextField; overlay stroke `keyFieldFocused ? Theme.accent : Theme.hairline` with `.animation(Theme.easeFast, value: keyFieldFocused)`. Disable Activate on empty: `.disabled(licenseKeyField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)`. Pluralize the trial line: `Text(d == 1 ? "1 day left" : "\(d) days left")`.
- **B11. Copy cleanups.** `buyRow` label "Buy Bulong" → "Full version" (keep "Buy — $29"). Split the footer into two Texts: privacy (Theme.textSecondary) "Everything runs on this Mac. The only network use is downloading models above." + attribution (Theme.textTertiary) "Bulong is Tagalog for a soft whisper. Includes NVIDIA Parakeet — © NVIDIA, CC-BY-4.0."
- **B12.** Keep the existing `.task` poll + self-arm logic and `.onAppear { modelManager.refresh() }`. Build green; app launches in both tabs without crashing. Commit.

## Verification (after A + B)
- Parallel review: spec-compliance + code-quality + a fresh design critique (does it now read as friendly? any token/constraint violations?).
- Build + relaunch; screenshot both tabs and the ready vs. checklist hero via Claude Preview / a real launch.
