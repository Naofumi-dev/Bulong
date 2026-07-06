# Bulong Phase 2 Implementation Plan — Identity & Design System

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename LocalTalk to **Bulong** and execute the approved "quiet instrument + living HUD" redesign per `docs/superpowers/specs/2026-07-06-bulong-phase2-design.md`.

**Architecture:** Theme.swift becomes a token system (surfaces, hairlines, type, radius, motion) consumed by every surface; each template surface (menu popover, History, Settings, onboarding, HUD) is rebuilt against it. The rename changes product/module/bundle-id with a one-way data migration; directories stay named `LocalTalk/` to avoid churn (module name ≠ folder name is fine in XcodeGen).

**Tech Stack:** Swift 6 / SwiftUI / AppKit interop, XcodeGen, XCTest. No new dependencies. CoreGraphics script for icon rendering.

**Ground rules for every task:**
- After any file add/remove: `xcodegen generate` before building.
- Build/test command (referenced as BUILD and TEST below):
  - BUILD: `xcodebuild build -project Bulong.xcodeproj -scheme Bulong -configuration Debug -destination 'platform=macOS,arch=arm64' 2>&1 | tail -3` (project/scheme are `LocalTalk.xcodeproj`/`LocalTalk` only until Task 1 lands)
  - TEST: `xcodebuild test -project Bulong.xcodeproj -scheme Bulong -destination 'platform=macOS,arch=arm64' 2>&1 | tail -5`
- Launch for manual checks: `./script/dev_build.sh`
- NEVER `pkill -x LocalTalk` (a legacy prototype may run under that name until Task 1 retires it); kill by exact binary path only.
- Motion must check `@Environment(\.accessibilityReduceMotion)` wherever an animation is added.

---

## File structure (changes)

```
project.yml                                  rename: Bulong targets/bundle ids
LocalTalk/  (directory name unchanged)
  Core/Theme.swift                           REPLACED: token system
  Core/Components.swift                      NEW: HotkeyChip, SectionCard, LevelBars, HoverButtonStyle, StepDots
  Services/MigrationService.swift            NEW: LocalTalk -> Bulong data migration
  Services/SettingsStore.swift               MODIFIED: + hudPosition
  UI/MenuBarView.swift                       DELETED (replaced by popover)
  UI/MenuPopoverView.swift                   NEW: designed .window-style popover
  UI/MainWindow/MainWindowView.swift         MODIFIED: ladder, cross-fade, hover sidebar
  UI/MainWindow/HistoryView.swift            REPLACED: card list + empty state
  UI/MainWindow/SettingsView.swift           REPLACED: section cards + live hints + HUD preview
  UI/Onboarding/OnboardingView.swift         REPLACED: 3 branded steps
  UI/HUD/HUDView.swift                       REPLACED: living orb + smoothed bars + hover cancel
  UI/HUD/HUDPanelController.swift            MODIFIED: position presets
  LocalTalkApp.swift                         MODIFIED: names, popover style, onboarding window chrome
LocalTalkTests/
  MigrationServiceTests.swift                NEW
  SettingsStoreTests.swift                   MODIFIED: hudPosition
  (all files)                                @testable import Bulong
script/render_icon.swift                     NEW: renders AppIcon + MenuIcon from code
script/dev_build.sh, release.sh, make_dmg.sh MODIFIED: Bulong names
README.md                                    REPLACED: Bulong story
```

---

### Task 1: Rename to Bulong + data migration + legacy retirement

**Files:**
- Modify: `project.yml`, `LocalTalk/LocalTalkApp.swift`, `script/dev_build.sh`, `script/release.sh`, `script/make_dmg.sh`, `README.md`, every file in `LocalTalkTests/`
- Create: `LocalTalk/Services/MigrationService.swift`
- Test: `LocalTalkTests/MigrationServiceTests.swift`

- [ ] **Step 1: Write failing tests `LocalTalkTests/MigrationServiceTests.swift`**

```swift
import XCTest
@testable import Bulong

final class MigrationServiceTests: XCTestCase {
    private var oldDefaults: UserDefaults!
    private var newDefaults: UserDefaults!
    private var oldDir: URL!
    private var newDir: URL!

    override func setUp() {
        oldDefaults = UserDefaults(suiteName: "MigrationOld")!
        newDefaults = UserDefaults(suiteName: "MigrationNew")!
        oldDefaults.removePersistentDomain(forName: "MigrationOld")
        newDefaults.removePersistentDomain(forName: "MigrationNew")
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-\(UUID().uuidString)")
        oldDir = base.appendingPathComponent("LocalTalk")
        newDir = base.appendingPathComponent("Bulong")
    }

    func testCopiesDefaultsAndMovesSupportDirOnce() throws {
        oldDefaults.set("tl", forKey: "language")
        oldDefaults.set(true, forKey: "hasCompletedOnboarding")
        try FileManager.default.createDirectory(at: oldDir, withIntermediateDirectories: true)
        try "x".write(to: oldDir.appendingPathComponent("history.jsonl"), atomically: true, encoding: .utf8)

        MigrationService.migrateIfNeeded(from: oldDefaults, to: newDefaults,
                                         oldSupportDir: oldDir, newSupportDir: newDir)

        XCTAssertEqual(newDefaults.string(forKey: "language"), "tl")
        XCTAssertTrue(newDefaults.bool(forKey: "hasCompletedOnboarding"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newDir.appendingPathComponent("history.jsonl").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldDir.path))
        XCTAssertTrue(newDefaults.bool(forKey: "didMigrateFromLocalTalk"))
    }

    func testDoesNotOverwriteExistingNewData() throws {
        newDefaults.set("en", forKey: "language")
        newDefaults.set(true, forKey: "didMigrateFromLocalTalk")
        oldDefaults.set("tl", forKey: "language")

        MigrationService.migrateIfNeeded(from: oldDefaults, to: newDefaults,
                                         oldSupportDir: oldDir, newSupportDir: newDir)

        XCTAssertEqual(newDefaults.string(forKey: "language"), "en") // marker set -> untouched
    }

    func testSilentWhenNothingToMigrate() {
        MigrationService.migrateIfNeeded(from: oldDefaults, to: newDefaults,
                                         oldSupportDir: oldDir, newSupportDir: newDir)
        XCTAssertTrue(newDefaults.bool(forKey: "didMigrateFromLocalTalk")) // marker still set (idempotence)
    }
}
```

- [ ] **Step 2: Write `LocalTalk/Services/MigrationService.swift`**

```swift
import Foundation

/// One-way, idempotent migration of LocalTalk-era data into the Bulong bundle identity.
enum MigrationService {
    static let markerKey = "didMigrateFromLocalTalk"
    /// Keys persisted by SettingsStore (keep in sync when SettingsStore adds keys pre-1.0).
    static let settingsKeys = [
        "language", "task", "hotkeyMode", "hotkey", "engineOverride",
        "pasteAfterTranscription", "playSounds", "hasCompletedOnboarding",
    ]

    static func migrateIfNeeded(
        from old: UserDefaults? = UserDefaults(suiteName: "com.armageddonvivas.LocalTalk"),
        to new: UserDefaults = .standard,
        oldSupportDir: URL = supportDir("LocalTalk"),
        newSupportDir: URL = supportDir("Bulong")
    ) {
        guard !new.bool(forKey: markerKey) else { return }
        defer { new.set(true, forKey: markerKey) }

        if let old {
            for key in settingsKeys where new.object(forKey: key) == nil {
                if let value = old.object(forKey: key) { new.set(value, forKey: key) }
            }
        }
        let fm = FileManager.default
        if fm.fileExists(atPath: oldSupportDir.path), !fm.fileExists(atPath: newSupportDir.path) {
            try? fm.createDirectory(at: newSupportDir.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
            try? fm.moveItem(at: oldSupportDir, to: newSupportDir)
        }
    }

    private static func supportDir(_ name: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name, isDirectory: true)
    }
}
```

Call it first thing in the app: in `LocalTalkApp.init()` (LocalTalkApp.swift:9), add `MigrationService.migrateIfNeeded()` as the FIRST line, before `AppComposition.makeAppModel()` (SettingsStore must read post-migration values). Also update `HistoryStore.defaultFileURL` and `ModelManager.whisperDownloadBase` to use `"Bulong"` instead of `"LocalTalk"` as the Application Support folder name (grep for `"LocalTalk"` string literals in `LocalTalk/Services/` — both exist).

- [ ] **Step 3: Rename in `project.yml`**

Change: `name: LocalTalk` → `name: Bulong`; target key `LocalTalk:` → `Bulong:` (keep `sources: - path: LocalTalk`); `CFBundleDisplayName: Bulong`; `NSMicrophoneUsageDescription: "Bulong records your microphone to transcribe speech entirely on this Mac. Audio never leaves your computer."`; `PRODUCT_BUNDLE_IDENTIFIER: com.armageddonvivas.Bulong`; scheme `testTargets: [BulongTests]`; test target key `LocalTalkTests:` → `BulongTests:` (keep `sources: - path: LocalTalkTests`) with `PRODUCT_BUNDLE_IDENTIFIER: com.armageddonvivas.BulongTests`. Info/entitlements paths stay under `LocalTalk/Support/`.

- [ ] **Step 4: Mechanical renames in code**

```bash
grep -rln '@testable import LocalTalk' LocalTalkTests | xargs sed -i '' 's/@testable import LocalTalk/@testable import Bulong/'
```

In `LocalTalk/LocalTalkApp.swift`: `MenuBarExtra("Bulong", ...)` (line 16); `Window("Bulong", id: "main")` (line 20); onboarding `window.title = "Welcome to Bulong"` (line 173). In `LocalTalk/UI/MenuBarView.swift`: "Open Bulong", "Quit Bulong". Grep for any remaining user-facing "LocalTalk" strings in `LocalTalk/` and update (do NOT touch `SourcesObjC/`, specs, or plans).

- [ ] **Step 5: Update scripts + README**

`script/dev_build.sh`: project `Bulong.xcodeproj`, scheme `Bulong`, `pkill -x Bulong` (was the hazardous `pkill -x LocalTalk` — the name change makes it safe), app path ends `/Bulong.app`. `script/release.sh` and `script/make_dmg.sh`: same renames (archive path `build/Bulong.xcarchive`, export `build/export/Bulong.app`, volname `Bulong`, dmg `Bulong-<ver>.dmg`). README.md: retitle `# Bulong`, first line: `Bulong — Tagalog for "whisper." Private, on-device dictation for macOS: press a hotkey, speak, and the words appear. Your voice never leaves your Mac.` Keep develop/release sections with new names; keep the Parakeet attribution line; note `SourcesObjC/main.m` remains the original prototype reference.

- [ ] **Step 6: Retire the legacy prototype**

```bash
pgrep -fl "dist/LocalTalk.app" && pkill -f "dist/LocalTalk.app/Contents/MacOS/LocalTalk" || true
rm -rf dist
```
(dist/ is gitignored — nothing to commit for the deletion itself.)

- [ ] **Step 7: Generate, build, test, launch**

```bash
xcodegen generate
xcodebuild test -project Bulong.xcodeproj -scheme Bulong -destination 'platform=macOS,arch=arm64' 2>&1 | tail -5
./script/dev_build.sh
```
Expected: TEST SUCCEEDED (all existing tests + 3 migration tests). Manual: menu bar item appears; open main window — **history from the LocalTalk era is present** (migration proof); settings preserved; onboarding does NOT reappear (hasCompletedOnboarding migrated). Note: macOS re-prompts mic + Accessibility (new bundle id) — expected, grant again.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat!: rename app to Bulong with one-way data migration, retire legacy prototype"
```

---

### Task 2: Theme 2.0 — the token system

**Files:**
- Replace: `LocalTalk/Core/Theme.swift`
- Modify: every file currently referencing old token names (mechanical map below)

- [ ] **Step 1: Replace `LocalTalk/Core/Theme.swift`**

```swift
import SwiftUI

/// Bulong design tokens. HARD RULE: no `Color(red:...)`, `.green`, or ad-hoc
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
    static let accentDim = accent.opacity(0.42)
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
        static let caption = Font.system(size: 11)
        /// Brand voice: transcripts, timers, counts, hotkey chips, model names.
        static func mono(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
    }

    // Radii — concentric rule: inner = outer − padding
    static let radiusCard: CGFloat = 10
    static let radiusControl: CGFloat = 6
    static let radiusHUD: CGFloat = 20

    // Motion
    static let easeFast = Animation.easeOut(duration: 0.16)
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.8)
}
```

- [ ] **Step 2: Mechanical token migration across the codebase**

Apply this mapping everywhere outside Theme.swift (grep each old name):
`Theme.root` → `Theme.ink0` · `Theme.sidebar` → `Theme.ink0` · `Theme.content` → `Theme.ink1` · `Theme.card` → `Theme.ink1` · `Theme.cardBorder` → `Theme.hairlineStrong` · `Theme.textSecondary` stays · `.foregroundStyle(.white)` on primary text → `Theme.textPrimary`.

Replace both off-brand greens (audit: `SettingsView.swift:117`, `OnboardingView.swift:101` — locate by `grep -rn '\.green' LocalTalk/`) with `Theme.accent`.

In `HUDView.swift`, replace the hard-coded colors with the new tokens: gradient stops → `Theme.hudShellTop`/`Theme.hudShellBottom`, border → `Theme.hudRim`, inactive waveform bars → `Theme.waveInactive`. (Full HUD redesign is Task 7; this step only de-hard-codes.)

- [ ] **Step 3: Verify the hard rule holds, then commit**

```bash
grep -rn "Color(red" LocalTalk/ --include="*.swift" | grep -v "Core/Theme.swift"   # expect: empty
grep -rn "\.green" LocalTalk/ --include="*.swift"                                   # expect: empty
xcodebuild test -project Bulong.xcodeproj -scheme Bulong -destination 'platform=macOS,arch=arm64' 2>&1 | tail -3
git add -A && git commit -m "feat: Theme 2.0 token system — surface ladder, hairlines, type scale, motion"
```

---

### Task 3: Shared components + menu bar popover

**Files:**
- Create: `LocalTalk/Core/Components.swift`
- Create: `LocalTalk/UI/MenuPopoverView.swift`
- Delete: `LocalTalk/UI/MenuBarView.swift`
- Modify: `LocalTalk/LocalTalkApp.swift`

- [ ] **Step 1: Write `LocalTalk/Core/Components.swift`**

```swift
import SwiftUI

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
            .onAppear {
                guard pulsing, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever()) { pulse = true }
            }
    }
}

/// Section container: caption title above an ink1 card with a hairline.
struct SectionCard<Content: View>: View {
    let title: String
    var footer: String? = nil
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
                Text(footer).font(Theme.Fonts.caption).foregroundStyle(Theme.textTertiary).padding(.leading, 4)
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
```

- [ ] **Step 2: Write `LocalTalk/UI/MenuPopoverView.swift`**

```swift
import AppKit
import SwiftUI

struct MenuPopoverView: View {
    var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            primaryAction
            if case .recording(let started) = model.state { recordingStrip(started: started) }
            if !model.lastTranscript.isEmpty { transcriptCard }
            Divider().overlay(Theme.hairline)
            footer
        }
        .padding(14)
        .frame(width: 300)
        .background(Theme.ink0)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isLive ? Theme.accent : Theme.textTertiary)
                .frame(width: 7, height: 7)
            Text("bulong").font(Theme.Fonts.mono(14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(stateText).font(Theme.Fonts.caption)
                .foregroundStyle(isFailed ? Theme.failure : Theme.textSecondary)
                .lineLimit(1)
        }
    }

    private var primaryAction: some View {
        Button {
            Task { await model.toggleDictation() }
        } label: {
            HStack {
                Image(systemName: isRecording ? "stop.fill" : "mic.fill").font(.system(size: 11))
                Text(isRecording ? "Stop and transcribe" : "Start dictation")
                    .font(Theme.Fonts.bodyStrong)
                Spacer()
                if !isRecording { HotkeyChip(text: model.settings.hotkey.displayString) }
            }
            .foregroundStyle(isRecording ? Theme.textPrimary : Theme.ink0)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: Theme.radiusControl + 2)
                .fill(isRecording ? Theme.ink2 : Theme.accent))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusControl + 2)
                .stroke(isRecording ? Theme.accentDim : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func recordingStrip(started: Date) -> some View {
        HStack(spacing: 8) {
            LevelBars(level: AppComposition.audio.level, active: true)
            TimelineView(.periodic(from: started, by: 0.5)) { context in
                Text(elapsed(from: started, now: context.date))
                    .font(Theme.Fonts.mono(11)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Text("Esc to cancel").font(Theme.Fonts.caption).foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 4)
    }

    private var transcriptCard: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(model.lastTranscript, forType: .string)
            copied = true
            Task { try? await Task.sleep(for: .seconds(1.2)); copied = false }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.lastTranscript)
                    .font(Theme.Fonts.mono(11.5)).foregroundStyle(Theme.textSecondary)
                    .lineLimit(2).multilineTextAlignment(.leading)
                Text(copied ? "Copied ✓" : "Click to copy")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(copied ? Theme.accent : Theme.textTertiary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.radiusControl + 2).fill(Theme.ink1))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusControl + 2).stroke(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .animation(Theme.easeFast, value: copied)
    }

    private var footer: some View {
        HStack(spacing: 2) {
            Button("History") { openMain() }.buttonStyle(HoverButtonStyle())
            Button("Settings") { openMain() }.buttonStyle(HoverButtonStyle())
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }.buttonStyle(HoverButtonStyle())
        }
    }

    private func openMain() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    private var isRecording: Bool { if case .recording = model.state { true } else { false } }
    private var isFailed: Bool { if case .failed = model.state { true } else { false } }
    private var isLive: Bool {
        switch model.state { case .recording, .transcribing, .inserting: true; default: false }
    }
    private var stateText: String {
        switch model.state {
        case .idle: "\(model.settings.language.uppercased()) · on-device"
        case .recording: "Listening"
        case .transcribing: "Transcribing…"
        case .inserting: "Inserting…"
        case .failed(let m): m
        }
    }
    private func elapsed(from start: Date, now: Date) -> String {
        let s = Int(now.timeIntervalSince(start))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
```

- [ ] **Step 3: Switch the scene and delete the old menu**

In `LocalTalkApp.swift` body: replace the `MenuBarExtra` content with `MenuPopoverView(model: appModel)` and add `.menuBarExtraStyle(.window)` on the MenuBarExtra. Delete `LocalTalk/UI/MenuBarView.swift`. Note: `.window` style has no automatic key equivalents — ⌘Q inside it goes away; Quit stays clickable and the app menu isn't present (LSUIElement), acceptable.

- [ ] **Step 4: Build, manual check, commit**

BUILD → succeeded. Manual: click menu bar icon → branded popover (wordmark, mint primary button with hotkey chip); click outside → dismisses; History/Settings/Quit hover pills work; during recording the strip shows live bars + timer; last transcript click shows "Copied ✓".

```bash
git add -A && git commit -m "feat: designed menu bar popover replaces stock dropdown"
```

---

### Task 4: History redesign — cards, hover, designed empty state

**Files:**
- Replace: `LocalTalk/UI/MainWindow/HistoryView.swift`
- Modify: `LocalTalk/UI/MainWindow/MainWindowView.swift` (cross-fade + ladder polish)

- [ ] **Step 1: Replace `LocalTalk/UI/MainWindow/HistoryView.swift`**

```swift
import AppKit
import SwiftUI

struct HistoryView: View {
    var model: AppModel
    @State private var query = ""
    @State private var confirmClear = false

    private var results: [HistoryEntry] { model.history.search(query) }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if results.isEmpty {
                Spacer()
                if query.isEmpty { EmptyHistoryView(model: model) } else { noMatches }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(results) { entry in HistoryCard(entry: entry) }
                    }
                    .padding(16)
                    .animation(Theme.easeFast, value: results.map(\.id))
                }
            }
        }
        .background(Theme.ink0)
        .confirmationDialog("Delete all transcripts?", isPresented: $confirmClear) {
            Button("Delete All", role: .destructive) { try? model.history.clear() }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                TextField("Search transcripts", text: $query)
                    .textFieldStyle(.plain)
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Theme.radiusControl + 2).fill(Theme.ink1))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusControl + 2).stroke(Theme.hairline, lineWidth: 1))

            Text("\(model.history.entries.count) clips")
                .font(Theme.Fonts.mono(11)).foregroundStyle(Theme.textTertiary)
                .fixedSize()
            Button("Export") { export() }.buttonStyle(HoverButtonStyle())
            Button("Clear") { confirmClear = true }.buttonStyle(HoverButtonStyle())
                .disabled(model.history.entries.isEmpty)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Theme.ink0)
        .overlay(Rectangle().fill(Theme.hairline).frame(height: 1), alignment: .bottom)
    }

    private var noMatches: some View {
        Text("No matches for “\(query)”")
            .font(Theme.Fonts.body).foregroundStyle(Theme.textTertiary)
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Bulong-transcripts.txt"
        if panel.runModal() == .OK, let url = panel.url {
            try? model.history.exportPlainText().write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

private struct HistoryCard: View {
    let entry: HistoryEntry
    @State private var hovering = false
    @State private var copied = false
    @State private var copyResetTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.text)
                .font(Theme.Fonts.mono(12.5))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(3)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                Text(entry.appName)
                Text(entry.date, style: .time)
                Text(entry.engine.rawValue).foregroundStyle(Theme.accentText)
                Text(entry.language.uppercased())
                Spacer()
                if hovering {
                    Button(copied ? "Copied ✓" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.text, forType: .string)
                        copied = true
                        copyResetTask?.cancel()
                        copyResetTask = Task {
                            try? await Task.sleep(for: .seconds(1.2))
                            if !Task.isCancelled { copied = false }
                        }
                    }
                    .buttonStyle(.plain)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(copied ? Theme.accent : Theme.textSecondary)
                }
            }
            .font(Theme.Fonts.mono(10.5))
            .foregroundStyle(Theme.textTertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.radiusCard).fill(hovering ? Theme.ink2 : Theme.ink1))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard)
            .stroke(hovering ? Theme.hairlineStrong : Theme.hairline, lineWidth: 1))
        .onHover { hovering = $0 }
        .animation(Theme.easeFast, value: hovering)
        .animation(Theme.easeFast, value: copied)
    }
}

private struct EmptyHistoryView: View {
    var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 3) {
                ForEach(0..<7, id: \.self) { i in
                    Capsule().fill(Theme.accentDim)
                        .frame(width: 3.5, height: [10, 18, 28, 22, 30, 16, 9][i])
                }
            }
            Text("Your dictations will appear here")
                .font(Theme.Fonts.title).foregroundStyle(Theme.textPrimary)
            HStack(spacing: 6) {
                Text("Press").font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary)
                HotkeyChip(text: model.settings.hotkey.displayString)
                Text("in any app to dictate").font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary)
            }
            Button {
                Task { await model.toggleDictation() }
            } label: {
                Text("Try it now")
                    .font(Theme.Fonts.action).foregroundStyle(Theme.ink0)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(Theme.accent))
            }
            .buttonStyle(.plain)
        }
    }
}
```

Note: `HistoryView(history:)` becomes `HistoryView(model:)` — update the call in `MainWindowView.swift` accordingly.

- [ ] **Step 2: Cross-fade + ladder in `MainWindowView.swift`**

In the detail `ZStack`, give each section view `.transition(.opacity)` and wrap the `section` switch driver with `.animation(Theme.easeFast, value: section)`. NOTE (post-review): the section selection was hoisted out of MainWindowView's local `@State` into `AppComposition.uiState` (an `@Observable UIState`) by Task 3's fixes so the popover can navigate — bind to that (via `@Bindable`), do NOT reintroduce local section state. Sidebar rows: replace plain `Label` with a row that gets `Theme.textPrimary` when selected, `Theme.textSecondary` otherwise, hover background `Theme.ink1` via `.listRowBackground` alternatives — where `.listStyle(.sidebar)` fights custom hover, keep the stock selection but add `.tint(Theme.accent)` (already present at window level) and move on; do not burn more than 30 minutes fighting AppKit here (spec allows "where feasible").

- [ ] **Step 3: Build, tests, manual check, commit**

TEST → succeeded. Manual: history shows cards; hover lifts a card and reveals Copy; search filters with a soft fade; clearing history shows the designed empty state with the keycap chip; "Try it now" starts dictation.

```bash
git add -A && git commit -m "feat: history as hoverable cards with designed empty state"
```

---

### Task 5: Settings redesign — section cards, live hints, HUD position

**Files:**
- Modify: `LocalTalk/Services/SettingsStore.swift` (+ `LocalTalk/Core/Types.swift`)
- Replace: `LocalTalk/UI/MainWindow/SettingsView.swift`
- Test: `LocalTalkTests/SettingsStoreTests.swift`

- [ ] **Step 1: Add HUDPosition — failing test first**

Append to `LocalTalkTests/SettingsStoreTests.swift`:

```swift
    @MainActor func testHudPositionDefaultsToBottomCenterAndPersists() {
        let s1 = SettingsStore(defaults: defaults)
        XCTAssertEqual(s1.hudPosition, .bottomCenter)
        s1.hudPosition = .topRight
        let s2 = SettingsStore(defaults: defaults)
        XCTAssertEqual(s2.hudPosition, .topRight)
    }
```

In `LocalTalk/Core/Types.swift` add:

```swift
enum HUDPosition: String, Codable, CaseIterable {
    case bottomCenter, topRight, nearNotch
    var label: String {
        switch self {
        case .bottomCenter: "Bottom center"
        case .topRight: "Top right"
        case .nearNotch: "Below the notch"
        }
    }
}
```

In `SettingsStore`: add `var hudPosition: HUDPosition { didSet { defaults.set(hudPosition.rawValue, forKey: "hudPosition") } }`, initialized in `init` via `HUDPosition(rawValue: defaults.string(forKey: "hudPosition") ?? "") ?? .bottomCenter`. Do NOT touch `MigrationService.settingsKeys` — it is a frozen snapshot of LocalTalk-era keys and `hudPosition` never existed in the old domain. Run TEST → the new test passes.

- [ ] **Step 2: Replace `LocalTalk/UI/MainWindow/SettingsView.swift`**

```swift
import AppKit
import AVFoundation
import SwiftUI
import FluidAudio

struct SettingsView: View {
    var model: AppModel
    var modelManager: ModelManager
    @State private var recordingHotkey = false
    @State private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var axTrusted = PasteService.isAccessibilityTrusted

    private let languages: [(code: String, name: String)] = [
        ("en", "English"), ("tl", "Filipino (Tagalog)"), ("es", "Spanish"), ("fr", "French"),
        ("de", "German"), ("it", "Italian"), ("pt", "Portuguese"), ("ja", "Japanese"),
        ("ko", "Korean"), ("zh", "Chinese"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionCard(title: "Dictation") {
                    row("Language") {
                        Picker("", selection: bind(\.language)) {
                            ForEach(languages, id: \.code) { Text($0.name).tag($0.code) }
                        }.labelsHidden().frame(width: 190)
                    }
                    divider
                    row("Mode") {
                        Picker("", selection: bind(\.task)) {
                            Text("Transcribe").tag(DictationTask.transcribe)
                            Text("Translate to English").tag(DictationTask.translate)
                        }.labelsHidden().frame(width: 190)
                    }
                    divider
                    row("Paste into the focused app") { Toggle("", isOn: bind(\.pasteAfterTranscription)).labelsHidden() }
                    divider
                    row("Play sounds") { Toggle("", isOn: bind(\.playSounds)).labelsHidden() }
                }

                SectionCard(title: "Hotkey",
                            footer: AppComposition.hotkey.registrationError) {
                    row("Shortcut") {
                        Button { recordingHotkey = true } label: {
                            HotkeyChip(text: recordingHotkey ? "Press keys…" : model.settings.hotkey.displayString,
                                       pulsing: recordingHotkey)
                        }
                        .buttonStyle(.plain)
                        .background(HotkeyRecorder(isRecording: $recordingHotkey) { spec in
                            model.settings.hotkey = spec
                            AppComposition.hotkey.register(spec)
                        })
                    }
                    divider
                    row("Behavior") {
                        Picker("", selection: bind(\.hotkeyMode)) {
                            Text("Toggle").tag(HotkeyMode.toggle)
                            Text("Push to talk").tag(HotkeyMode.pushToTalk)
                        }.pickerStyle(.segmented).labelsHidden().frame(width: 190)
                    }
                }

                SectionCard(title: "Dictation bar") {
                    HStack(spacing: 10) {
                        ForEach(HUDPosition.allCases, id: \.self) { pos in
                            HUDPositionPreview(position: pos, selected: model.settings.hudPosition == pos)
                                .onTapGesture { model.settings.hudPosition = pos }
                        }
                    }
                }

                SectionCard(title: "Models") {
                    modelRow("Parakeet — fast English", state: modelManager.parakeetV2) {
                        Task { await modelManager.downloadParakeet(.v2) }
                    }
                    divider
                    modelRow("Parakeet — European languages", state: modelManager.parakeetV3) {
                        Task { await modelManager.downloadParakeet(.v3) }
                    }
                    divider
                    modelRow("Whisper — all languages + translate", state: modelManager.whisperLargeTurbo) {
                        Task { await modelManager.downloadWhisper() }
                    }
                }

                SectionCard(title: "Permissions") {
                    permissionRow("Microphone",
                                  granted: micGranted,
                                  grantedHint: "Connected ✓",
                                  pendingHint: "Bulong needs your mic to hear you") {
                        Task { micGranted = await AudioService.requestMicPermission() }
                    }
                    divider
                    permissionRow("Accessibility",
                                  granted: axTrusted,
                                  grantedHint: "Granted ✓ — pastes into any app",
                                  pendingHint: "Lets Bulong type the result where you're working") {
                        PasteService.requestAccessibility()
                    }
                }

                Text("Bulong — Tagalog for “whisper.” Transcription runs entirely on this Mac; the only network use is downloading models above. Includes NVIDIA Parakeet, © NVIDIA, CC-BY-4.0.")
                    .font(Theme.Fonts.caption).foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 4)
            }
            .padding(20)
        }
        .background(Theme.ink0)
        .onAppear { modelManager.refresh() }
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            axTrusted = PasteService.isAccessibilityTrusted
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1).padding(.vertical, 8)
    }

    private func row(_ title: String, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            Text(title).font(Theme.Fonts.body).foregroundStyle(Theme.textPrimary)
            Spacer()
            control()
        }
    }

    private func modelRow(_ title: String, state: ModelManager.DownloadState,
                          download: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(Theme.Fonts.body).foregroundStyle(Theme.textPrimary)
            Spacer()
            switch state {
            case .ready:
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .font(Theme.Fonts.caption).foregroundStyle(Theme.accent)
            case .notDownloaded:
                Button("Download", action: download).buttonStyle(HoverButtonStyle())
            case .downloading(let p):
                HStack(spacing: 8) {
                    ProgressView(value: p).frame(width: 90)
                    Text("\(Int(p * 100))%").font(Theme.Fonts.mono(10.5)).foregroundStyle(Theme.textSecondary)
                }
            case .failed(let msg):
                VStack(alignment: .trailing, spacing: 2) {
                    Text(msg).font(Theme.Fonts.caption).foregroundStyle(Theme.failure).lineLimit(1)
                    Button("Retry", action: download).buttonStyle(HoverButtonStyle())
                }
            }
        }
    }

    private func permissionRow(_ title: String, granted: Bool, grantedHint: String,
                               pendingHint: String, request: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Fonts.body).foregroundStyle(Theme.textPrimary)
                Text(granted ? grantedHint : pendingHint)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(granted ? Theme.accent : Theme.textTertiary)
            }
            Spacer()
            if !granted { Button("Grant", action: request).buttonStyle(HoverButtonStyle()) }
        }
    }

    private func bind<T>(_ keyPath: ReferenceWritableKeyPath<SettingsStore, T>) -> Binding<T> {
        Binding(get: { model.settings[keyPath: keyPath] }, set: { model.settings[keyPath: keyPath] = $0 })
    }
}

/// Miniature screen showing where the HUD pill sits for a preset.
struct HUDPositionPreview: View {
    let position: HUDPosition
    let selected: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: alignment) {
                RoundedRectangle(cornerRadius: 6).fill(Theme.ink2)
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(selected ? Theme.accent : Theme.hairlineStrong, lineWidth: selected ? 1.5 : 1))
                Capsule().fill(selected ? Theme.accent : Theme.waveInactive)
                    .frame(width: 26, height: 7)
                    .padding(6)
            }
            .frame(width: 92, height: 58)
            Text(position.label)
                .font(Theme.Fonts.caption)
                .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
        }
        .contentShape(Rectangle())
        .animation(Theme.easeFast, value: selected)
    }

    private var alignment: Alignment {
        switch position {
        case .bottomCenter: .bottom
        case .topRight: .topTrailing
        case .nearNotch: .top
        }
    }
}
```

Keep the existing `HotkeyRecorder` NSViewRepresentable from the current SettingsView (move it unchanged to the bottom of the new file — it captures the next keydown while `isRecording`).

- [ ] **Step 3: Build, tests, manual check, commit**

TEST → succeeded (incl. new hudPosition test). Manual: sections are ink cards with mono captions; permission hints flip to mint "Connected ✓" live after granting; hotkey chip pulses mint while capturing; HUD position previews select with a mint outline; model rows show percentages.

```bash
git add -A && git commit -m "feat: settings as section cards with live permission hints and HUD position presets"
```

---

### Task 6: Onboarding redesign — three branded steps

**Files:**
- Replace: `LocalTalk/UI/Onboarding/OnboardingView.swift`
- Modify: `LocalTalk/LocalTalkApp.swift:162-181` (window chrome)

- [ ] **Step 1: Replace `LocalTalk/UI/Onboarding/OnboardingView.swift`**

```swift
import AVFoundation
import SwiftUI
import FluidAudio

struct OnboardingView: View {
    var model: AppModel
    var modelManager: ModelManager
    @State private var step = 0
    @State private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var axTrusted = PasteService.isAccessibilityTrusted
    @State private var testText = ""
    @State private var payoff = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch step {
                case 0: promiseStep.transition(stepTransition)
                case 1: permissionsStep.transition(stepTransition)
                default: dictateStep.transition(stepTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : Theme.spring, value: step)

            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }.buttonStyle(HoverButtonStyle())
                }
                Spacer()
                StepDots(count: 3, index: step)
                Spacer()
                Button(step == 2 ? "Finish" : "Continue") {
                    if step == 2 { model.settings.hasCompletedOnboarding = true } else { step += 1 }
                }
                .buttonStyle(.plain)
                .font(Theme.Fonts.action)
                .foregroundStyle(continueEnabled ? Theme.ink0 : Theme.textTertiary)
                .padding(.horizontal, 16).padding(.vertical, 7)
                .background(Capsule().fill(continueEnabled ? Theme.accent : Theme.ink2))
                .disabled(!continueEnabled)
            }
            .padding(20)
        }
        .frame(width: 560, height: 420)
        .background(Theme.ink0)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .onAppear { modelManager.refresh() }
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            axTrusted = PasteService.isAccessibilityTrusted
        }
        .onChange(of: model.lastTranscript) { _, new in
            if step == 2, !new.isEmpty { payoff = true }
        }
    }

    private var stepTransition: AnyTransition {
        .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity))
    }

    private var continueEnabled: Bool {
        switch step {
        case 1: micGranted            // accessibility stays optional
        case 2: modelManager.parakeetV2 == .ready
        default: true
        }
    }

    // Step 0 — the promise
    private var promiseStep: some View {
        VStack(spacing: 16) {
            HStack(spacing: 3) {
                ForEach(0..<7, id: \.self) { i in
                    Capsule().fill(Theme.accent)
                        .frame(width: 4, height: [12, 22, 34, 26, 36, 18, 10][i])
                }
            }
            Text("bulong").font(Theme.Fonts.mono(30, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Text("Tagalog for “whisper”")
                .font(Theme.Fonts.caption).foregroundStyle(Theme.textTertiary)
            Text("Press a hotkey. Speak. The words appear —\nand your voice never leaves this Mac.")
                .font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center).lineSpacing(3)
        }
        .padding(32)
    }

    // Step 1 — permissions with live status
    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Two permissions").font(Theme.Fonts.display).foregroundStyle(Theme.textPrimary)
            permissionCard(icon: "mic.fill", title: "Microphone", granted: micGranted, required: true,
                           reason: "So Bulong can hear you. Audio is processed on this Mac and never uploaded.") {
                Task { micGranted = await AudioService.requestMicPermission() }
            }
            permissionCard(icon: "keyboard.fill", title: "Accessibility", granted: axTrusted, required: false,
                           reason: "Lets Bulong type the result into whatever app you're using. Optional — without it, transcripts go to your clipboard.") {
                PasteService.requestAccessibility()
            }
        }
        .padding(28)
    }

    private func permissionCard(icon: String, title: String, granted: Bool, required: Bool,
                                reason: String, request: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 16))
                .foregroundStyle(granted ? Theme.accent : Theme.textSecondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).font(Theme.Fonts.title).foregroundStyle(Theme.textPrimary)
                    if !required {
                        Text("optional").font(Theme.Fonts.mono(9)).foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().stroke(Theme.hairlineStrong, lineWidth: 1))
                    }
                }
                Text(granted ? "Granted ✓" : reason)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(granted ? Theme.accent : Theme.textSecondary)
                    .lineSpacing(2)
            }
            Spacer()
            if !granted {
                Button("Grant", action: request).buttonStyle(HoverButtonStyle())
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.radiusCard).fill(Theme.ink1))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard)
            .stroke(granted ? Theme.accentDim : Theme.hairline, lineWidth: 1))
        .animation(Theme.easeFast, value: granted)
    }

    // Step 2 — model + first dictation payoff
    private var dictateStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Say something").font(Theme.Fonts.display).foregroundStyle(Theme.textPrimary)
            switch modelManager.parakeetV2 {
            case .ready:
                HStack(spacing: 6) {
                    Text("Click the field, press").font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary)
                    HotkeyChip(text: model.settings.hotkey.displayString)
                    Text("and speak.").font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary)
                }
                TextField("", text: $testText, prompt: Text("Your words land here…")
                    .foregroundStyle(Theme.textTertiary))
                    .textFieldStyle(.plain)
                    .font(Theme.Fonts.mono(13))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: Theme.radiusCard).fill(Theme.ink1))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard)
                        .stroke(payoff ? Theme.accent : Theme.hairlineStrong, lineWidth: 1))
                if payoff {
                    Label("It worked — that's Bulong. Same hotkey, any app.", systemImage: "checkmark.circle.fill")
                        .font(Theme.Fonts.body).foregroundStyle(Theme.accent)
                        .transition(.opacity)
                }
            case .downloading(let p):
                VStack(alignment: .leading, spacing: 6) {
                    Text("Downloading the English model — one time, ~600 MB.")
                        .font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 8) {
                        ProgressView(value: p).frame(width: 260)
                        Text("\(Int(p * 100))%").font(Theme.Fonts.mono(11)).foregroundStyle(Theme.textSecondary)
                    }
                }
            case .notDownloaded:
                Button("Download the speech model") { Task { await modelManager.downloadParakeet(.v2) } }
                    .buttonStyle(HoverButtonStyle())
            case .failed(let msg):
                VStack(alignment: .leading, spacing: 6) {
                    Text(msg).font(Theme.Fonts.caption).foregroundStyle(Theme.failure)
                    Button("Retry") { Task { await modelManager.downloadParakeet(.v2) } }
                        .buttonStyle(HoverButtonStyle())
                }
            }
            Spacer()
        }
        .padding(28)
        .animation(Theme.easeFast, value: payoff)
    }
}
```

Keep `OnboardingWindowView` (the `onChange`-closing wrapper in LocalTalkApp.swift) as is.

- [ ] **Step 2: Brand the onboarding window chrome** — in `showOnboardingIfNeeded` (LocalTalkApp.swift:172-175) replace the window config:

```swift
            let window = NSWindow(contentViewController: host)
            window.title = "Welcome to Bulong"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.backgroundColor = NSColor(red: 7/255, green: 9/255, blue: 11/255, alpha: 1)
            window.center()
            window.isReleasedWhenClosed = false
```

- [ ] **Step 3: Build, manual check, commit**

Manual: `defaults delete com.armageddonvivas.Bulong && ./script/dev_build.sh` → onboarding appears borderless-looking (traffic lights float over ink); wordmark step → permissions cards flip to mint live → model step gates Continue → dictating into the field triggers the mint payoff line; Finish closes; relaunch shows no onboarding. Then restore your settings: run the app once and reconfigure (or `defaults import` if you exported first — simplest is to just re-pick language/hotkey in Settings).

```bash
git add -A && git commit -m "feat: three-step branded onboarding with live permission status and payoff moment"
```

---

### Task 7: The living HUD — orb, smoothed bars, hover cancel, presets

**Files:**
- Replace: `LocalTalk/UI/HUD/HUDView.swift`
- Modify: `LocalTalk/UI/HUD/HUDPanelController.swift` (preset default positions)

- [ ] **Step 1: Replace `LocalTalk/UI/HUD/HUDView.swift`**

Requirements the new file must meet (keep the existing view API: `HUDView(state:level:partial:language:onCancel:onDragChanged:onDragEnded:)` so `HUDStateView` in LocalTalkApp.swift compiles unchanged):

```swift
import SwiftUI

struct HUDView: View {
    let state: DictationState
    let level: Float
    let partial: String
    let language: String
    var onCancel: () -> Void
    var onDragChanged: (CGSize) -> Void
    var onDragEnded: () -> Void

    @State private var hovering = false
    @State private var smoothed: [Float] = Array(repeating: 0, count: 7)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isFailed: Bool { if case .failed = state { true } else { false } }
    private var isRecording: Bool { if case .recording = state { true } else { false } }
    private var accent: Color { isFailed ? Theme.failure : Theme.accent }

    var body: some View {
        HStack(spacing: 12) {
            OrbView(level: level, state: state, reduceMotion: reduceMotion)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Fonts.bodyStrong).foregroundStyle(Theme.textPrimary)
                Text(detail).font(Theme.Fonts.mono(10.5)).foregroundStyle(Theme.textSecondary)
                    .lineLimit(1).truncationMode(.head)
            }
            Spacer(minLength: 8)
            SmoothedWaveform(level: level, state: state, smoothed: $smoothed, reduceMotion: reduceMotion)
            badge("ON-DEVICE")
            badge(language.uppercased())
            if showCancel {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                .accessibilityLabel("Cancel dictation")
            }
        }
        .padding(.horizontal, 16)
        .frame(width: 392, height: 74)
        .background(
            LinearGradient(colors: [Theme.hudShellTop, Theme.hudShellBottom],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .opacity(0.96)
        )
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusHUD, style: .continuous)
            .stroke(isFailed ? Theme.failure.opacity(0.6) : Theme.hudRim, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusHUD, style: .continuous))
        .shadow(color: .black.opacity(0.34), radius: 22, y: 12)
        .onHover { hovering = $0 }
        .animation(Theme.easeFast, value: hovering)
        .animation(Theme.easeFast, value: showCancel)
        .gesture(DragGesture()
            .onChanged { onDragChanged($0.translation) }
            .onEnded { _ in onDragEnded() })
    }

    private var showCancel: Bool {
        if case .transcribing = state { return true }
        return isRecording && hovering
    }

    private var title: String {
        switch state {
        case .recording: "Listening"
        case .transcribing: "Transcribing"
        case .inserting: "Inserting"
        case .failed: "Failed"
        case .idle: "Bulong"
        }
    }

    private var detail: String {
        if case .failed(let m) = state { return m }
        if !partial.isEmpty { return partial }
        if case .recording = state { return "Voice stays on this Mac — Esc to cancel" }
        return "On-device dictation"
    }

    private func badge(_ text: String) -> some View {
        Text(text).font(Theme.Fonts.mono(9, weight: .bold))
            .foregroundStyle(isFailed ? Theme.failure : Theme.accentText)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().stroke(accent.opacity(0.42), lineWidth: 1))
    }
}

/// The living orb: a mint radial core whose glow breathes with the live level.
/// Silence reads as silence — below the threshold it settles to a calm minimum.
struct OrbView: View {
    let level: Float
    let state: DictationState
    let reduceMotion: Bool

    private static let silenceThreshold: Float = 0.06

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let energy = energyValue(t: t)
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [color.opacity(0.45 * energy), .clear],
                        center: .center, startRadius: 2, endRadius: 17 + 10 * energy))
                Circle()
                    .fill(RadialGradient(
                        colors: [Color.white.opacity(0.85), color, color.opacity(0.25)],
                        center: UnitPoint(x: 0.38, y: 0.35), startRadius: 0, endRadius: 11))
                    .frame(width: 16 + 5 * energy, height: 16 + 5 * energy)
            }
            .animation(Theme.easeFast, value: energy)
        }
    }

    private var paused: Bool {
        if reduceMotion { return true }
        switch state { case .idle, .failed: return true; default: return false }
    }

    private var color: Color {
        if case .failed = state { return Theme.failure }
        return Theme.accent
    }

    /// Recording: live level (flat when below threshold). Transcribing/inserting: slow steady pulse.
    private func energyValue(t: TimeInterval) -> CGFloat {
        switch state {
        case .recording:
            let live = level < Self.silenceThreshold ? 0 : level
            return CGFloat(0.25 + 0.75 * live)
        case .transcribing, .inserting:
            return reduceMotion ? 0.5 : 0.4 + 0.2 * CGFloat(abs(sin(t * 2.2)))
        case .failed: return 0.2
        case .idle: return 0.3
        }
    }
}

/// Seven bars with per-bar smoothing lag so movement reads organic, not uniform.
struct SmoothedWaveform: View {
    let level: Float
    let state: DictationState
    @Binding var smoothed: [Float]
    let reduceMotion: Bool

    private let base: [CGFloat] = [0.35, 0.6, 1.0, 0.75, 0.5, 0.8, 0.4]
    private let lag: [Float] = [0.55, 0.4, 0.25, 0.35, 0.5, 0.3, 0.6]
    private static let silenceThreshold: Float = 0.06

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion || !isRecording)) { context in
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i >= 2 && i <= 4 ? activeColor : Theme.waveInactive)
                        .frame(width: 4, height: height(i, t: context.date.timeIntervalSinceReferenceDate))
                }
            }
        }
    }

    private var isRecording: Bool { if case .recording = state { true } else { false } }
    private var activeColor: Color {
        if case .failed = state { return Theme.failure }
        return Theme.accent
    }

    private func height(_ i: Int, t: TimeInterval) -> CGFloat {
        let cap = base[i] * 22
        switch state {
        case .recording:
            let target = level < Self.silenceThreshold ? 0 : level
            smoothed[i] += (target - smoothed[i]) * lag[i]          // per-bar lag
            return max(4, cap * CGFloat(0.2 + 0.8 * smoothed[i]))
        case .transcribing, .inserting:
            return reduceMotion ? cap * 0.5 : max(4, cap * (0.35 + 0.25 * abs(sin(t * 2 + Double(i) * 0.9))))
        case .failed: return 4
        case .idle: return cap * 0.3
        }
    }
}
```

(If mutating `smoothed` inside TimelineView triggers a "modifying state during view update" warning at execution time, move the smoothing into a `@State` holder updated via `.onChange(of: level)` — the visual contract is what matters: per-bar lag, silence-flat.)

- [ ] **Step 2: Position presets in `HUDPanelController.swift`**

Read the file first. In its default-position logic (the branch used when no saved per-screen origin exists — currently bottom-center +24pt), switch on `SettingsStore().hudPosition`:

```swift
        let frame = screen.visibleFrame
        let size = NSSize(width: 392, height: 74)
        let origin: NSPoint
        switch SettingsStore().hudPosition {
        case .bottomCenter:
            origin = NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 24)
        case .topRight:
            origin = NSPoint(x: frame.maxX - size.width - 24, y: frame.maxY - size.height - 24)
        case .nearNotch:
            origin = NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 10)
        }
        panel.setFrameOrigin(origin)
```

A user drag still wins: keep the saved-origin branch first. ALSO: when the user picks a new preset in Settings, stale saved origins would mask it — add `func clearSavedPositions()` to HUDPanelController that removes all `hudOrigin-*` defaults keys, and call it from the Settings `onTapGesture` after setting `hudPosition` (Task 5's `HUDPositionPreview` tap: `model.settings.hudPosition = pos; AppComposition.hud.clearSavedPositions()`).

- [ ] **Step 3: Build, tests, manual check, commit**

TEST → succeeded. Manual: dictate — orb breathes with your voice and goes calm when you pause (silence = stillness); bars move organically, not in lockstep; hover the pill while recording → cancel appears; pick "Top right" in Settings → next dictation shows the HUD top-right; drag it somewhere → position sticks; failure state shows coral flatline.

```bash
git add -A && git commit -m "feat: living HUD — breathing orb, silence-aware smoothed waveform, hover cancel, position presets"
```

---

### Task 8: App icon + wordmark render

**Files:**
- Create: `script/render_icon.swift`
- Modify: `LocalTalk/Resources/Assets.xcassets/AppIcon.appiconset/` (regenerated PNGs), `MenuIcon.imageset` (glyph)

- [ ] **Step 1: Write `script/render_icon.swift`** (run directly with `swift script/render_icon.swift` — CoreGraphics only, no SPM)

```swift
import AppKit
import CoreGraphics

// Bulong icon: ink squircle, mint waveform glyph with a soft glow.
// Renders the AppIcon iconset sizes + a 256px transparent glyph for MenuIcon.

let ink = CGColor(red: 7/255, green: 9/255, blue: 11/255, alpha: 1)
let inkEdge = CGColor(red: 16/255, green: 20/255, blue: 22/255, alpha: 1)
let mint = CGColor(red: 43/255, green: 222/255, blue: 177/255, alpha: 1)
let mintPale = CGColor(red: 176/255, green: 249/255, blue: 226/255, alpha: 1)

func render(size: Int, glyphOnly: Bool) -> NSBitmapImageRep {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    if !glyphOnly {
        // Squircle-ish background (macOS masks Dock icons itself; we still round for Finder)
        let r = s * 0.2237
        let path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                          cornerWidth: r, cornerHeight: r, transform: nil)
        ctx.addPath(path)
        ctx.clip()
        // Subtle vertical ink gradient
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [inkEdge, ink] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: s/2, y: s), end: CGPoint(x: s/2, y: 0), options: [])
    }

    // Glyph: 7 waveform bars, whisper-quiet silhouette
    let heights: [CGFloat] = [0.18, 0.34, 0.56, 0.44, 0.60, 0.28, 0.15]
    let glyphWidth = s * 0.62
    let barW = glyphWidth / 13.0                    // 7 bars + 6 gaps
    let x0 = (s - glyphWidth) / 2
    let midY = s * (glyphOnly ? 0.5 : 0.52)

    // Soft glow behind the glyph
    if !glyphOnly {
        let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [CGColor(red: 43/255, green: 222/255, blue: 177/255, alpha: 0.28),
                     CGColor(red: 43/255, green: 222/255, blue: 177/255, alpha: 0)] as CFArray,
            locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: s/2, y: midY), startRadius: 0,
                               endCenter: CGPoint(x: s/2, y: midY), endRadius: s * 0.42, options: [])
    }

    let barGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: [mintPale, mint] as CFArray, locations: [0, 1])!
    for (i, h) in heights.enumerated() {
        let barH = s * h
        let x = x0 + CGFloat(i) * barW * 2
        let rect = CGRect(x: x, y: midY - barH/2, width: barW, height: barH)
        let bar = CGPath(roundedRect: rect, cornerWidth: barW/2, cornerHeight: barW/2, transform: nil)
        ctx.saveGState()
        ctx.addPath(bar)
        ctx.clip()
        ctx.drawLinearGradient(barGrad, start: CGPoint(x: x, y: midY + barH/2),
                               end: CGPoint(x: x, y: midY - barH/2), options: [])
        ctx.restoreGState()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, to path: String) {
    try! rep.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

let iconsetDir = "LocalTalk/Resources/Assets.xcassets/AppIcon.appiconset"
for (px, name) in [(16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"),
                   (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"),
                   (512, "icon_256x256@2x"), (512, "icon_512x512"), (1024, "icon_512x512@2x")] {
    write(render(size: px, glyphOnly: false), to: "\(iconsetDir)/\(name).png")
}
write(render(size: 256, glyphOnly: true), to: "LocalTalk/Resources/Assets.xcassets/MenuIcon.imageset/LocalTalkLogo.png")
```

- [ ] **Step 2: Render + verify visually**

```bash
cd /Users/armageddonvivas/Documents/Codex/2026-07-05/hey-codex-i-want-to-create/outputs/LocalTalk
swift script/render_icon.swift
open LocalTalk/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512.png
```
Eyeball: ink squircle, mint bars readable, glow subtle. Rebuild + launch: new icon in the app switcher; MenuIcon glyph renders in the main-window header and onboarding. (Note for later, NOT this task: an Icon Composer `.icon` for Tahoe glass treatment is a manual polish step the user can do with guidance.)

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: rendered Bulong app icon and menu glyph (ink squircle, mint waveform)"
```

---

### Task 9: Final polish gate — stock-tell sweep, screenshots, critique

**Files:**
- Modify: `docs/superpowers/specs/smoke-checklist.md` (rename to Bulong, add Phase 2 items)
- No new code except fixes that fall out of the critique.

- [ ] **Step 1: Automated stock-tell sweep** (all must return empty)

```bash
grep -rn "Color(red" LocalTalk/ --include="*.swift" | grep -v "Core/Theme.swift"
grep -rn "\.green" LocalTalk/ --include="*.swift"
grep -rn "ContentUnavailableView\|formStyle(.grouped)\|\.borderedProminent\|\.roundedBorder" LocalTalk/ --include="*.swift"
grep -rn "\"LocalTalk\"" LocalTalk/ --include="*.swift"    # user-facing strings must say Bulong
```

- [ ] **Step 2: Full suite + surface screenshots**

TEST → succeeded. Launch and screenshot every surface (popover idle + recording, History with data, History empty, Settings, all 3 onboarding steps, HUD in all 4 live states) — save to the session scratchpad for the critique.

- [ ] **Step 3: Harsh design critique**

Dispatch a design-critique reviewer (executor: use the audit's "stock tells" list from the Phase 2 grounding as the rubric) against the screenshots + code. Every Critical/Important finding gets fixed and re-verified; Minor findings are logged in the plan file under a "Follow-ups" heading.

- [ ] **Step 4: Update smoke checklist + final commit**

In `docs/superpowers/specs/smoke-checklist.md`: replace LocalTalk with Bulong throughout; add items: "Popover opens/dismisses and all actions work", "History hover + copy + empty state", "Settings permission hints react live", "HUD presets apply on all displays", "Onboarding completes end-to-end on a fresh user", "Old LocalTalk data migrated on first Bulong launch". Run the checklist top to bottom.

```bash
git add -A && git commit -m "chore: phase 2 polish gate — stock-tell sweep, smoke checklist for Bulong"
```

---

## Self-review notes (for the executor)

- **Spec coverage:** rename+migration+legacy retirement (T1), tokens incl. HUD de-hard-coding + green ban (T2), popover (T3), History cards/empty state (T4), Settings cards/hints/keycap/HUD presets (T5), onboarding 3-step (T6), living HUD + presets wiring (T7), icon/wordmark (T8), verification + critique gate (T9). Spec's "sidebar hover" is explicitly time-boxed in T4 Step 2 per the spec's "where feasible" clause. Icon Composer `.icon` is explicitly deferred (manual, user-assisted) — the rendered iconset satisfies this phase.
- **Sequencing is strict:** T1 (module rename) before everything; T2 (tokens) before all surface tasks; T3–T6 are order-independent after T2; T7 needs T5's `hudPosition`; T8/T9 last.
- **Files I could not read before writing this plan** (implementer must read before modifying, adapting the shown code to reality): `HUDPanelController.swift` (T7 Step 2 — the API shape `show/hide/drag(to:)/finishDrag()` and per-screen persistence are confirmed by the Phase 2 audit), current `HistoryView/SettingsView/OnboardingView` (fully replaced anyway — but check for helpers other code imports before deleting, e.g. `HotkeyRecorder` must move, not die).
- **Swift 6 concurrency:** same contract as Phase 1 — annotation tweaks are fine; architecture changes are not.
- **Never bump package pins in this phase.**


