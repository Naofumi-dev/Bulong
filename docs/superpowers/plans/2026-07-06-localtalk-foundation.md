# LocalTalk v1.0 Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild LocalTalk as a sellable menu-bar-first SwiftUI dictation app with in-process transcription (Parakeet via FluidAudio + WhisperKit), replacing the Python whisper CLI, per `docs/superpowers/specs/2026-07-06-localtalk-foundation-design.md`.

**Architecture:** `AppModel` (@MainActor state machine) coordinates single-purpose services (AudioService, HotkeyService, PasteService, HistoryStore, SettingsStore, ModelManager) and two `TranscriptionEngine` conformances. XcodeGen generates the Xcode project from `project.yml`. UI = MenuBarExtra + one resizable main window (History/Settings) + a floating NSPanel HUD.

**Tech Stack:** Swift 6 / SwiftUI / AppKit interop, FluidAudio **0.15.4** (pinned; Parakeet TDT v2/v3), WhisperKit via **argmax-oss-swift 1.0.0** (pinned), XcodeGen, XCTest, Carbon `RegisterEventHotKey`, Accessibility API.

**Verified API notes (2026-07-06, against release source — do NOT trust the packages' READMEs):**
- FluidAudio: `AsrModels.downloadAndLoad(version:progressHandler:)` + actor `SlidingWindowAsrManager` (`loadModels(_:)`, `startStreaming(source:)`, `streamAudio(_ buffer:)` accepts any `AVAudioPCMBuffer` format, `transcriptionUpdates: AsyncStream<SlidingWindowTranscriptionUpdate>` with `.text`/`.isConfirmed`, `finish() -> String`, `cancel()`, `reset()`). The README's `asrManager.configure(models:)` does NOT exist in 0.15.4.
- WhisperKit: init with `WhisperKitConfig(prewarm:false, load:false, download:false)`, then static `WhisperKit.download(variant:downloadBase:progressCallback:)`, set `.modelFolder`, `prewarmModels()`, `loadModels()`. `transcribe(audioPath:decodeOptions:)` **throws and returns `[TranscriptionResult]`** — join `.map(\.text)`. The README's `transcribe(...)?.text` does NOT compile against 1.0.0.
- Both packages require Apple Silicon (Parakeet hard-requires it) and handle 16 kHz mono resampling internally when given files/buffers.

---

## File structure

```
project.yml                                  XcodeGen spec (source of truth for the project)
LocalTalk/                                   app target sources
  LocalTalkApp.swift                         @main, MenuBarExtra + Window scenes
  AppModel.swift                             state machine + service coordination
  Support/                                   Info.plist + entitlements (xcodegen-generated)
  Core/
    Types.swift                              DictationState, EngineID, DictationTask, TranscriptionUpdate, HotkeySpec
    Theme.swift                              LocalTalk dark palette constants
  Services/
    SettingsStore.swift                      UserDefaults-backed observable settings
    HistoryStore.swift                       JSONL history: append/search/export/clear
    AudioService.swift                       AVAudioEngine tap -> AsyncStream<AVAudioPCMBuffer> + level
    HotkeyService.swift                      Carbon hotkey, toggle + push-to-talk, remappable
    PasteService.swift                       target-app capture, AX insert, Cmd+V fallback, clipboard restore
    ModelManager.swift                       model presence/download/progress for both engines
  Engines/
    TranscriptionEngine.swift                protocol + shared option types
    EngineSelector.swift                     language/task -> engine + model routing
    ParakeetEngine.swift                     FluidAudio SlidingWindowAsrManager (streaming partials)
    WhisperKitEngine.swift                   temp-file batch transcription (multilingual + translate)
  UI/
    MenuBarView.swift                        MenuBarExtra content
    HUD/HUDPanelController.swift             non-activating NSPanel host, position persistence
    HUD/HUDView.swift                        SwiftUI port of the existing HUD design
    MainWindow/MainWindowView.swift          sidebar shell (History | Settings)
    MainWindow/HistoryView.swift             searchable history list + export/clear
    MainWindow/SettingsView.swift            all settings incl. hotkey recorder + models
    Onboarding/OnboardingView.swift          welcome -> mic -> accessibility -> model download -> test
  Resources/
    Assets.xcassets/AppIcon.appiconset/      icons copied from Assets/LocalTalk.iconset
LocalTalkTests/
  SettingsStoreTests.swift
  HistoryStoreTests.swift
  EngineSelectorTests.swift
  HotkeySpecTests.swift
  AppModelTests.swift                        uses FakeEngine
  FakeEngine.swift
script/
  dev_build.sh                               xcodegen + xcodebuild build + open app (replaces build_and_run.sh use)
  release.sh                                 archive/export Developer ID build (activates post-enrollment)
  sign_and_notarize.sh                       notarytool submit + staple (requires Apple Developer)
  make_dmg.sh                                hdiutil DMG
docs/superpowers/specs/smoke-checklist.md    manual verification checklist
```

Legacy code: `SourcesObjC/main.m` stays as reference until the final task. `Package.swift` and `Sources/LocalTalk/` (old SwiftPM app) are deleted in Task 14 once parity is confirmed.

---

### Task 0: Toolchain gate (blocks everything)

Xcode was still downloading when this plan was written (`/Applications/Xcode.appdownload`). Nothing builds until this task passes.

**Files:** none.

- [ ] **Step 1: Verify Xcode finished installing**

Run: `ls /Applications/ | grep -i xcode`
Expected: `Xcode.app` (NOT `Xcode.appdownload`). If still downloading, STOP and wait.

- [ ] **Step 2: Point the toolchain at Xcode and accept the license** (needs admin — ask the user to run these if sudo prompts fail)

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
xcodebuild -runFirstLaunch
```

- [ ] **Step 3: Verify**

Run: `xcodebuild -version`
Expected: `Xcode 26.x` (or 16.x+) with a Build version line — NOT the "requires Xcode" error.

- [ ] **Step 4: Install XcodeGen**

Run: `brew install xcodegen && xcodegen --version`
Expected: `Version: 2.x`

---

### Task 1: Project scaffold — app boots to a menu bar icon

**Files:**
- Create: `project.yml`
- Create: `LocalTalk/LocalTalkApp.swift`
- Create: `LocalTalk/Core/Theme.swift`
- Create: `LocalTalk/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` (+ copied PNGs)
- Create: `LocalTalkTests/SmokeTests.swift`
- Modify: `.gitignore`

- [ ] **Step 1: Write `project.yml`**

```yaml
name: LocalTalk
options:
  bundleIdPrefix: com.armageddonvivas
  deploymentTarget:
    macOS: "14.0"
  createIntermediateGroups: true

packages:
  FluidAudio:
    url: https://github.com/FluidInference/FluidAudio
    exactVersion: 0.15.4
  WhisperKit:
    url: https://github.com/argmaxinc/argmax-oss-swift
    exactVersion: 1.0.0

targets:
  LocalTalk:
    type: application
    platform: macOS
    sources:
      - path: LocalTalk
    dependencies:
      - package: FluidAudio
        product: FluidAudio
      - package: WhisperKit
        product: WhisperKit
    info:
      path: LocalTalk/Support/Info.plist
      properties:
        NSMicrophoneUsageDescription: "LocalTalk records your microphone to transcribe speech entirely on this Mac. Audio never leaves your computer."
        LSUIElement: true
        LSMinimumSystemVersion: $(MACOSX_DEPLOYMENT_TARGET)
        CFBundleShortVersionString: "1.0.0"
        CFBundleVersion: "1"
        CFBundleDisplayName: LocalTalk
        NSPrincipalClass: NSApplication
    entitlements:
      path: LocalTalk/Support/LocalTalk.entitlements
      properties:
        com.apple.security.device.audio-input: true
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.armageddonvivas.LocalTalk
        SWIFT_VERSION: "6.0"
        ENABLE_HARDENED_RUNTIME: YES
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
      configs:
        Debug:
          CODE_SIGN_STYLE: Automatic
          CODE_SIGN_IDENTITY: "-"
    scheme:
      testTargets:
        - LocalTalkTests
  LocalTalkTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: LocalTalkTests
    dependencies:
      - target: LocalTalk
    settings:
      base:
        SWIFT_VERSION: "6.0"
        PRODUCT_BUNDLE_IDENTIFIER: com.armageddonvivas.LocalTalkTests
        CODE_SIGN_STYLE: Automatic
        CODE_SIGN_IDENTITY: "-"
```

Notes: NO `com.apple.security.app-sandbox` (Accessibility-based paste is incompatible with sandboxing — every competitor ships unsandboxed outside the App Store). Hardened runtime stays on. Ad-hoc Debug signing re-prompts mic permission after rebuilds; that's acceptable in dev (a free "Apple Development" cert fixes it if it gets annoying).

- [ ] **Step 2: Create the app icon asset catalog**

```bash
mkdir -p LocalTalk/Resources/Assets.xcassets/AppIcon.appiconset
for f in 16x16 16x16@2x 32x32 32x32@2x 128x128 128x128@2x 256x256 256x256@2x 512x512 512x512@2x; do
  cp "Assets/LocalTalk.iconset/icon_${f}.png" "LocalTalk/Resources/Assets.xcassets/AppIcon.appiconset/icon_${f}.png"
done
```

Write `LocalTalk/Resources/Assets.xcassets/Contents.json`:
```json
{ "info": { "author": "xcode", "version": 1 } }
```

Write `LocalTalk/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`:
```json
{
  "images": [
    { "filename": "icon_16x16.png",      "idiom": "mac", "scale": "1x", "size": "16x16" },
    { "filename": "icon_16x16@2x.png",   "idiom": "mac", "scale": "2x", "size": "16x16" },
    { "filename": "icon_32x32.png",      "idiom": "mac", "scale": "1x", "size": "32x32" },
    { "filename": "icon_32x32@2x.png",   "idiom": "mac", "scale": "2x", "size": "32x32" },
    { "filename": "icon_128x128.png",    "idiom": "mac", "scale": "1x", "size": "128x128" },
    { "filename": "icon_128x128@2x.png", "idiom": "mac", "scale": "2x", "size": "128x128" },
    { "filename": "icon_256x256.png",    "idiom": "mac", "scale": "1x", "size": "256x256" },
    { "filename": "icon_256x256@2x.png", "idiom": "mac", "scale": "2x", "size": "256x256" },
    { "filename": "icon_512x512.png",    "idiom": "mac", "scale": "1x", "size": "512x512" },
    { "filename": "icon_512x512@2x.png", "idiom": "mac", "scale": "2x", "size": "512x512" }
  ],
  "info": { "author": "xcode", "version": 1 }
}
```

- [ ] **Step 3: Write `LocalTalk/Core/Theme.swift`** (palette lifted from the ObjC app so the brand carries over)

```swift
import SwiftUI

enum Theme {
    static let root      = Color(red:   9/255, green:  10/255, blue:  10/255)
    static let sidebar   = Color(red:  12/255, green:  13/255, blue:  13/255)
    static let content   = Color(red:  18/255, green:  19/255, blue:  19/255)
    static let card      = Color(red:  24/255, green:  25/255, blue:  25/255)
    static let cardBorder = Color(red: 42/255, green:  44/255, blue:  42/255)
    static let accent    = Color(red:  76/255, green: 198/255, blue: 255/255)
    static let accentText = Color(red: 178/255, green: 234/255, blue: 255/255)
    static let failure   = Color(red: 255/255, green: 118/255, blue: 112/255)
    static let textSecondary = Color(white: 0.62)
}
```

- [ ] **Step 4: Write minimal `LocalTalk/LocalTalkApp.swift`**

```swift
import SwiftUI

@main
struct LocalTalkApp: App {
    var body: some Scene {
        MenuBarExtra("LocalTalk", systemImage: "waveform") {
            Text("LocalTalk is running")
            Divider()
            Button("Quit LocalTalk") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
```

- [ ] **Step 5: Write `LocalTalkTests/SmokeTests.swift`**

```swift
import XCTest
@testable import LocalTalk

final class SmokeTests: XCTestCase {
    func testThemeAccentExists() {
        XCTAssertNotNil(Theme.accent)
    }
}
```

- [ ] **Step 6: Add generated artifacts to `.gitignore`** (append lines)

```
LocalTalk.xcodeproj/
DerivedData/
```

(`project.yml` is the committed source of truth; the .xcodeproj is regenerated. `LocalTalk/Support/Info.plist` and the entitlements file ARE regenerated by xcodegen — commit them anyway so the repo is inspectable.)

- [ ] **Step 7: Generate, resolve, build, test**

```bash
xcodegen generate
xcodebuild -resolvePackageDependencies -project LocalTalk.xcodeproj -scheme LocalTalk
xcodebuild build -project LocalTalk.xcodeproj -scheme LocalTalk -configuration Debug -destination 'platform=macOS,arch=arm64'
xcodebuild test  -project LocalTalk.xcodeproj -scheme LocalTalk -destination 'platform=macOS,arch=arm64'
```

Expected: `BUILD SUCCEEDED`, then `TEST SUCCEEDED` (1 test). First resolve downloads FluidAudio + WhisperKit and may take minutes.

- [ ] **Step 8: Launch and verify visually**

```bash
open "$(xcodebuild -project LocalTalk.xcodeproj -scheme LocalTalk -configuration Debug -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR/{print $3}')/LocalTalk.app"
```
Expected: a waveform icon appears in the menu bar; clicking shows "LocalTalk is running" + Quit. No Dock icon.

- [ ] **Step 9: Commit**

```bash
git add project.yml LocalTalk LocalTalkTests .gitignore
git commit -m "feat: XcodeGen scaffold — menu bar app boots with pinned FluidAudio/WhisperKit deps"
```

---

### Task 2: Core types + SettingsStore (TDD)

**Files:**
- Create: `LocalTalk/Core/Types.swift`
- Create: `LocalTalk/Services/SettingsStore.swift`
- Test: `LocalTalkTests/SettingsStoreTests.swift`, `LocalTalkTests/HotkeySpecTests.swift`

- [ ] **Step 1: Write `LocalTalk/Core/Types.swift`**

```swift
import Foundation

enum DictationState: Equatable {
    case idle
    case recording(started: Date)
    case transcribing
    case inserting
    case failed(message: String)
}

enum EngineID: String, Codable, CaseIterable { case parakeet, whisperKit }

enum DictationTask: String, Codable { case transcribe, translate }

enum HotkeyMode: String, Codable, CaseIterable { case toggle, pushToTalk }

enum TranscriptionUpdate: Sendable, Equatable {
    case partial(String)
    case final(String)
}

enum InsertionResult: Equatable {
    case insertedDirectly          // AX selected-text write
    case pastedViaCmdV             // synthesized ⌘V, clipboard restored
    case clipboardOnly(reason: String)
}

struct HotkeySpec: Codable, Equatable {
    var keyCode: UInt32            // Carbon virtual key code (kVK_Space = 49)
    var carbonModifiers: UInt32    // Carbon flags: cmdKey|shiftKey|optionKey|controlKey
    static let `default` = HotkeySpec(keyCode: 49, carbonModifiers: 0x0800 | 0x1000) // ⌃⌥Space (optionKey|controlKey)

    var displayString: String {
        var parts: [String] = []
        if carbonModifiers & 0x1000 != 0 { parts.append("⌃") }   // controlKey
        if carbonModifiers & 0x0800 != 0 { parts.append("⌥") }   // optionKey
        if carbonModifiers & 0x0200 != 0 { parts.append("⇧") }   // shiftKey
        if carbonModifiers & 0x0100 != 0 { parts.append("⌘") }   // cmdKey
        parts.append(Self.keyName(for: keyCode))
        return parts.joined()
    }

    static func keyName(for keyCode: UInt32) -> String {
        switch keyCode {
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 53: return "Esc"
        default:
            let names: [UInt32: String] = [0:"A",11:"B",8:"C",2:"D",14:"E",3:"F",5:"G",4:"H",34:"I",38:"J",
                40:"K",37:"L",46:"M",45:"N",31:"O",35:"P",12:"Q",15:"R",1:"S",17:"T",32:"U",9:"V",13:"W",
                7:"X",16:"Y",6:"Z",29:"0",18:"1",19:"2",20:"3",21:"4",23:"5",22:"6",26:"7",28:"8",25:"9"]
            return names[keyCode] ?? "Key\(keyCode)"
        }
    }
}

struct HistoryEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var text: String
    var date: Date
    var appName: String
    var engine: EngineID
    var language: String
    var durationSeconds: Double
}
```

- [ ] **Step 2: Write failing tests `LocalTalkTests/HotkeySpecTests.swift`**

```swift
import XCTest
@testable import LocalTalk

final class HotkeySpecTests: XCTestCase {
    func testDefaultIsCtrlOptSpace() {
        let spec = HotkeySpec.default
        XCTAssertEqual(spec.displayString, "⌃⌥Space")
    }
    func testDisplayStringForCmdShiftD() {
        let spec = HotkeySpec(keyCode: 2, carbonModifiers: 0x0100 | 0x0200)
        XCTAssertEqual(spec.displayString, "⇧⌘D")
    }
    func testRoundTripsThroughJSON() throws {
        let spec = HotkeySpec(keyCode: 9, carbonModifiers: 0x1000)
        let data = try JSONEncoder().encode(spec)
        let back = try JSONDecoder().decode(HotkeySpec.self, from: data)
        XCTAssertEqual(spec, back)
    }
}
```

- [ ] **Step 3: Write failing tests `LocalTalkTests/SettingsStoreTests.swift`**

```swift
import XCTest
@testable import LocalTalk

final class SettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "SettingsStoreTests")!
        defaults.removePersistentDomain(forName: "SettingsStoreTests")
    }

    @MainActor func testDefaults() {
        let s = SettingsStore(defaults: defaults)
        XCTAssertEqual(s.language, "en")
        XCTAssertEqual(s.task, .transcribe)
        XCTAssertEqual(s.hotkeyMode, .toggle)
        XCTAssertEqual(s.hotkey, .default)
        XCTAssertNil(s.engineOverride)
        XCTAssertTrue(s.pasteAfterTranscription)
        XCTAssertFalse(s.hasCompletedOnboarding)
    }

    @MainActor func testPersistsAcrossInstances() {
        let s1 = SettingsStore(defaults: defaults)
        s1.language = "tl"
        s1.task = .translate
        s1.hotkey = HotkeySpec(keyCode: 2, carbonModifiers: 0x0100)
        s1.engineOverride = .whisperKit
        let s2 = SettingsStore(defaults: defaults)
        XCTAssertEqual(s2.language, "tl")
        XCTAssertEqual(s2.task, .translate)
        XCTAssertEqual(s2.hotkey.keyCode, 2)
        XCTAssertEqual(s2.engineOverride, .whisperKit)
    }
}
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `xcodebuild test -project LocalTalk.xcodeproj -scheme LocalTalk -destination 'platform=macOS,arch=arm64' 2>&1 | tail -20`
Expected: compile failure — `SettingsStore` not found. (Regenerate first: `xcodegen generate` — required after every file add.)

- [ ] **Step 5: Write `LocalTalk/Services/SettingsStore.swift`**

```swift
import Foundation
import Observation

@MainActor @Observable
final class SettingsStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.language = defaults.string(forKey: "language") ?? "en"
        self.task = DictationTask(rawValue: defaults.string(forKey: "task") ?? "") ?? .transcribe
        self.hotkeyMode = HotkeyMode(rawValue: defaults.string(forKey: "hotkeyMode") ?? "") ?? .toggle
        self.pasteAfterTranscription = defaults.object(forKey: "pasteAfterTranscription") as? Bool ?? true
        self.playSounds = defaults.object(forKey: "playSounds") as? Bool ?? false
        self.hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        if let data = defaults.data(forKey: "hotkey"),
           let spec = try? JSONDecoder().decode(HotkeySpec.self, from: data) {
            self.hotkey = spec
        } else {
            self.hotkey = .default
        }
        if let raw = defaults.string(forKey: "engineOverride") {
            self.engineOverride = EngineID(rawValue: raw)
        } else {
            self.engineOverride = nil
        }
    }

    var language: String { didSet { defaults.set(language, forKey: "language") } }
    var task: DictationTask { didSet { defaults.set(task.rawValue, forKey: "task") } }
    var hotkeyMode: HotkeyMode { didSet { defaults.set(hotkeyMode.rawValue, forKey: "hotkeyMode") } }
    var hotkey: HotkeySpec { didSet { defaults.set(try? JSONEncoder().encode(hotkey), forKey: "hotkey") } }
    var engineOverride: EngineID? { didSet { defaults.set(engineOverride?.rawValue, forKey: "engineOverride") } }
    var pasteAfterTranscription: Bool { didSet { defaults.set(pasteAfterTranscription, forKey: "pasteAfterTranscription") } }
    var playSounds: Bool { didSet { defaults.set(playSounds, forKey: "playSounds") } }
    var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") } }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -project LocalTalk.xcodeproj -scheme LocalTalk -destination 'platform=macOS,arch=arm64' 2>&1 | tail -5`
Expected: `TEST SUCCEEDED` (6 tests).

- [ ] **Step 7: Commit**

```bash
git add LocalTalk/Core/Types.swift LocalTalk/Services/SettingsStore.swift LocalTalkTests
git commit -m "feat: core types and persisted SettingsStore"
```

---

### Task 3: HistoryStore — JSONL with search and export (TDD)

**Files:**
- Create: `LocalTalk/Services/HistoryStore.swift`
- Test: `LocalTalkTests/HistoryStoreTests.swift`

- [ ] **Step 1: Write failing tests `LocalTalkTests/HistoryStoreTests.swift`**

```swift
import XCTest
@testable import LocalTalk

final class HistoryStoreTests: XCTestCase {
    private var tmpFile: URL!

    override func setUp() {
        tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-\(UUID().uuidString).jsonl")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: tmpFile) }

    private func entry(_ text: String, app: String = "TextEdit") -> HistoryEntry {
        HistoryEntry(id: UUID(), text: text, date: Date(), appName: app,
                     engine: .parakeet, language: "en", durationSeconds: 2.5)
    }

    @MainActor func testAppendAndReloadFromDisk() throws {
        let s1 = HistoryStore(fileURL: tmpFile)
        try s1.append(entry("hello world"))
        try s1.append(entry("second item"))
        let s2 = HistoryStore(fileURL: tmpFile)
        XCTAssertEqual(s2.entries.count, 2)
        XCTAssertEqual(s2.entries.first?.text, "second item") // newest first
    }

    @MainActor func testSearchIsCaseInsensitive() throws {
        let s = HistoryStore(fileURL: tmpFile)
        try s.append(entry("Meeting notes for Tuesday"))
        try s.append(entry("grocery list"))
        XCTAssertEqual(s.search("MEETING").count, 1)
        XCTAssertEqual(s.search("").count, 2)
    }

    @MainActor func testExportPlainText() throws {
        let s = HistoryStore(fileURL: tmpFile)
        try s.append(entry("alpha"))
        try s.append(entry("beta"))
        let text = s.exportPlainText()
        XCTAssertTrue(text.contains("alpha"))
        XCTAssertTrue(text.contains("beta"))
        XCTAssertTrue(text.contains("TextEdit"))
    }

    @MainActor func testClearRemovesFileContents() throws {
        let s = HistoryStore(fileURL: tmpFile)
        try s.append(entry("to be removed"))
        try s.clear()
        XCTAssertTrue(s.entries.isEmpty)
        let s2 = HistoryStore(fileURL: tmpFile)
        XCTAssertTrue(s2.entries.isEmpty)
    }

    @MainActor func testCorruptLinesAreSkippedNotFatal() throws {
        try "not json\n".write(to: tmpFile, atomically: true, encoding: .utf8)
        let s = HistoryStore(fileURL: tmpFile)
        XCTAssertTrue(s.entries.isEmpty)
        try s.append(entry("still works"))
        XCTAssertEqual(s.entries.count, 1)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodegen generate && xcodebuild test -project LocalTalk.xcodeproj -scheme LocalTalk -destination 'platform=macOS,arch=arm64' 2>&1 | tail -10`
Expected: compile failure — `HistoryStore` not found.

- [ ] **Step 3: Write `LocalTalk/Services/HistoryStore.swift`**

```swift
import Foundation
import Observation

@MainActor @Observable
final class HistoryStore {
    private(set) var entries: [HistoryEntry] = []   // newest first
    private let fileURL: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()

    static var defaultFileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalTalk", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.jsonl")
    }

    init(fileURL: URL = HistoryStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    private func load() {
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        entries = raw.split(separator: "\n")
            .compactMap { try? decoder.decode(HistoryEntry.self, from: Data($0.utf8)) }
            .sorted { $0.date > $1.date }
    }

    func append(_ entry: HistoryEntry) throws {
        entries.insert(entry, at: 0)
        let line = try encoder.encode(entry) + Data("\n".utf8)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: fileURL)
        }
    }

    func search(_ query: String) -> [HistoryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return entries }
        return entries.filter { $0.text.localizedCaseInsensitiveContains(q) }
    }

    func exportPlainText() -> String {
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .short
        return entries.reversed().map { e in
            "[\(df.string(from: e.date))] (\(e.appName))\n\(e.text)\n"
        }.joined(separator: "\n")
    }

    func clear() throws {
        entries = []
        try Data().write(to: fileURL)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project LocalTalk.xcodeproj -scheme LocalTalk -destination 'platform=macOS,arch=arm64' 2>&1 | tail -5`
Expected: `TEST SUCCEEDED` (11 tests).

- [ ] **Step 5: Commit**

```bash
git add LocalTalk/Services/HistoryStore.swift LocalTalkTests/HistoryStoreTests.swift
git commit -m "feat: JSONL HistoryStore with search, export, clear"
```

---

### Task 4: TranscriptionEngine protocol + EngineSelector (TDD)

**Files:**
- Create: `LocalTalk/Engines/TranscriptionEngine.swift`
- Create: `LocalTalk/Engines/EngineSelector.swift`
- Create: `LocalTalkTests/FakeEngine.swift`
- Test: `LocalTalkTests/EngineSelectorTests.swift`

- [ ] **Step 1: Write `LocalTalk/Engines/TranscriptionEngine.swift`**

```swift
import Foundation
@preconcurrency import AVFoundation

struct TranscriptionOptions: Sendable, Equatable {
    var language: String        // ISO 639-1 ("en", "tl", ...) — never "auto" here; selector resolves it
    var task: DictationTask
}

enum EngineError: LocalizedError {
    case modelNotDownloaded(EngineID)
    case cancelled
    case timedOut
    case engineFailure(String)

    var errorDescription: String? {
        switch self {
        case .modelNotDownloaded(let id): return "The \(id.rawValue) model isn't downloaded yet. Open Settings → Models."
        case .cancelled: return "Cancelled."
        case .timedOut: return "Transcription took too long and was stopped."
        case .engineFailure(let msg): return msg
        }
    }
}

protocol TranscriptionEngine: Sendable {
    var id: EngineID { get }
    /// True when the required model files are on disk and loadable.
    func isReady(for options: TranscriptionOptions) async -> Bool
    /// Download (if needed) and load models. Progress in [0, 1].
    func prepare(options: TranscriptionOptions, progress: @escaping @Sendable (Double) -> Void) async throws
    /// Consume mic buffers until the stream ends (= recording stopped), emitting partials and exactly one `.final`.
    /// The returned stream MUST finish after `.final` or throw.
    func transcribe(audio: AsyncStream<AVAudioPCMBuffer>, options: TranscriptionOptions)
        -> AsyncThrowingStream<TranscriptionUpdate, Error>
    /// Abandon the in-flight transcription; the update stream should throw `EngineError.cancelled`.
    func cancel() async
}
```

- [ ] **Step 2: Write failing tests `LocalTalkTests/EngineSelectorTests.swift`**

```swift
import XCTest
@testable import LocalTalk

final class EngineSelectorTests: XCTestCase {
    func testEnglishTranscribeUsesParakeetV2() {
        let r = EngineSelector.route(language: "en", task: .transcribe, override: nil)
        XCTAssertEqual(r.engine, .parakeet)
        XCTAssertEqual(r.parakeetVersion, .v2)
    }
    func testEuropeanLanguageUsesParakeetV3() {
        let r = EngineSelector.route(language: "de", task: .transcribe, override: nil)
        XCTAssertEqual(r.engine, .parakeet)
        XCTAssertEqual(r.parakeetVersion, .v3)
    }
    func testTagalogFallsBackToWhisperKit() {
        let r = EngineSelector.route(language: "tl", task: .transcribe, override: nil)
        XCTAssertEqual(r.engine, .whisperKit)
    }
    func testTranslateAlwaysUsesWhisperKit() {
        let r = EngineSelector.route(language: "en", task: .translate, override: nil)
        XCTAssertEqual(r.engine, .whisperKit)
    }
    func testUserOverrideWins() {
        let r = EngineSelector.route(language: "en", task: .transcribe, override: .whisperKit)
        XCTAssertEqual(r.engine, .whisperKit)
    }
    func testOverrideCannotBreakTranslate() {
        let r = EngineSelector.route(language: "en", task: .translate, override: .parakeet)
        XCTAssertEqual(r.engine, .whisperKit) // Parakeet cannot translate; correctness beats override
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `xcodegen generate && xcodebuild test -project LocalTalk.xcodeproj -scheme LocalTalk -destination 'platform=macOS,arch=arm64' 2>&1 | tail -10`
Expected: compile failure — `EngineSelector` not found.

- [ ] **Step 4: Write `LocalTalk/Engines/EngineSelector.swift`**

```swift
import Foundation

enum ParakeetVersion: Equatable { case v2, v3 }

struct EngineRoute: Equatable {
    var engine: EngineID
    var parakeetVersion: ParakeetVersion?   // nil when engine == .whisperKit
}

enum EngineSelector {
    /// Languages supported by parakeet-tdt-0.6b-v3 (25 European languages).
    static let parakeetV3Languages: Set<String> = [
        "bg","hr","cs","da","nl","en","et","fi","fr","de","el","hu","it","lv","lt",
        "mt","pl","pt","ro","sk","sl","es","sv","ru","uk",
    ]

    static func route(language: String, task: DictationTask, override: EngineID?) -> EngineRoute {
        if task == .translate { return EngineRoute(engine: .whisperKit, parakeetVersion: nil) }
        if let override {
            if override == .parakeet && !parakeetV3Languages.contains(language) {
                return EngineRoute(engine: .whisperKit, parakeetVersion: nil) // override can't do the impossible
            }
            return EngineRoute(engine: override,
                               parakeetVersion: override == .parakeet ? (language == "en" ? .v2 : .v3) : nil)
        }
        if language == "en" { return EngineRoute(engine: .parakeet, parakeetVersion: .v2) }
        if parakeetV3Languages.contains(language) { return EngineRoute(engine: .parakeet, parakeetVersion: .v3) }
        return EngineRoute(engine: .whisperKit, parakeetVersion: nil)
    }
}
```

- [ ] **Step 5: Write `LocalTalkTests/FakeEngine.swift`** (test double used by Task 5)

```swift
import Foundation
@preconcurrency import AVFoundation
@testable import LocalTalk

final class FakeEngine: TranscriptionEngine, @unchecked Sendable {
    let id: EngineID = .parakeet
    var scriptedUpdates: [TranscriptionUpdate] = [.partial("hel"), .partial("hello"), .final("hello world")]
    var scriptedError: Error?
    var ready = true
    private(set) var cancelCalled = false
    private(set) var buffersReceived = 0

    func isReady(for options: TranscriptionOptions) async -> Bool { ready }
    func prepare(options: TranscriptionOptions, progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(1.0); ready = true
    }
    func transcribe(audio: AsyncStream<AVAudioPCMBuffer>, options: TranscriptionOptions)
        -> AsyncThrowingStream<TranscriptionUpdate, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for await _ in audio { self.buffersReceived += 1 }   // drain until recording stops
                if let err = self.scriptedError { continuation.finish(throwing: err); return }
                for update in self.scriptedUpdates { continuation.yield(update) }
                continuation.finish()
            }
        }
    }
    func cancel() async { cancelCalled = true }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -project LocalTalk.xcodeproj -scheme LocalTalk -destination 'platform=macOS,arch=arm64' 2>&1 | tail -5`
Expected: `TEST SUCCEEDED` (17 tests).

- [ ] **Step 7: Commit**

```bash
git add LocalTalk/Engines LocalTalkTests/EngineSelectorTests.swift LocalTalkTests/FakeEngine.swift
git commit -m "feat: TranscriptionEngine protocol and language-aware EngineSelector"
```

---

### Task 5: AppModel state machine (TDD with FakeEngine)

**Files:**
- Create: `LocalTalk/AppModel.swift` (new file; the old `Sources/LocalTalk/AppModel.swift` is legacy and untouched)
- Test: `LocalTalkTests/AppModelTests.swift`

Interfaces this task depends on but that arrive in later tasks are injected as closures so AppModel is testable now: audio provider, paster, sound player.

- [ ] **Step 1: Write failing tests `LocalTalkTests/AppModelTests.swift`**

```swift
import XCTest
@preconcurrency import AVFoundation
@testable import LocalTalk

@MainActor
final class AppModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var tmpHistory: URL!

    override func setUp() {
        defaults = UserDefaults(suiteName: "AppModelTests")!
        defaults.removePersistentDomain(forName: "AppModelTests")
        tmpHistory = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-\(UUID().uuidString).jsonl")
    }

    private func makeModel(engine: FakeEngine) -> (AppModel, AudioStub) {
        let audio = AudioStub()
        let model = AppModel(
            settings: SettingsStore(defaults: defaults),
            history: HistoryStore(fileURL: tmpHistory),
            engineProvider: { _ in engine },
            audioStart: { audio.start() },
            audioStop: { audio.stop() },
            insertText: { _ in .insertedDirectly },
            frontmostAppName: { "TextEdit" },
            minimumDuration: 0,        // disable the too-short guard in most tests
            watchdogSeconds: 5
        )
        return (model, audio)
    }

    func testFullDictationFlowAppendsHistoryAndReturnsToIdle() async throws {
        let engine = FakeEngine()
        let (model, audio) = makeModel(engine: engine)
        await model.toggleDictation()                     // start
        guard case .recording = model.state else { return XCTFail("expected recording, got \(model.state)") }
        audio.emitSilence(buffers: 3)
        await model.toggleDictation()                     // stop -> transcribe -> insert
        await model.waitForIdle()
        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(model.history.entries.first?.text, "hello world")
        XCTAssertEqual(model.lastPartial, "")             // cleared after completion
    }

    func testEngineErrorLandsInFailedStateWithMessage() async throws {
        let engine = FakeEngine()
        engine.scriptedError = EngineError.engineFailure("model exploded")
        let (model, audio) = makeModel(engine: engine)
        await model.toggleDictation()
        audio.emitSilence(buffers: 1)
        await model.toggleDictation()
        await model.waitForIdle()
        guard case .failed(let message) = model.state else { return XCTFail("expected failed") }
        XCTAssertTrue(message.contains("model exploded"))
        XCTAssertTrue(model.history.entries.isEmpty)
    }

    func testCancelWhileRecordingDiscardsWithoutTranscribing() async throws {
        let engine = FakeEngine()
        let (model, audio) = makeModel(engine: engine)
        await model.toggleDictation()
        audio.emitSilence(buffers: 2)
        await model.cancelDictation()
        await model.waitForIdle()
        XCTAssertEqual(model.state, .idle)
        XCTAssertTrue(model.history.entries.isEmpty)
        XCTAssertTrue(engine.cancelCalled)
    }

    func testPartialUpdatesAreExposed() async throws {
        let engine = FakeEngine()
        let (model, audio) = makeModel(engine: engine)
        var partials: [String] = []
        model.onPartial = { partials.append($0) }
        await model.toggleDictation()
        audio.emitSilence(buffers: 1)
        await model.toggleDictation()
        await model.waitForIdle()
        XCTAssertEqual(partials, ["hel", "hello"])
    }

    func testFailedStateClearsOnNextStart() async throws {
        let engine = FakeEngine()
        engine.scriptedError = EngineError.engineFailure("boom")
        let (model, audio) = makeModel(engine: engine)
        await model.toggleDictation(); audio.emitSilence(buffers: 1); await model.toggleDictation()
        await model.waitForIdle()
        engine.scriptedError = nil
        await model.toggleDictation()
        guard case .recording = model.state else { return XCTFail("failed state must not block a new start") }
        await model.cancelDictation()
    }
}

/// Deterministic stand-in for AudioService.
@MainActor
final class AudioStub {
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    func start() -> AsyncStream<AVAudioPCMBuffer> {
        AsyncStream { self.continuation = $0 }
    }
    func stop() { continuation?.finish() }
    func emitSilence(buffers: Int) {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        for _ in 0..<buffers {
            let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600)!
            buf.frameLength = 1600
            continuation?.yield(buf)
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodegen generate && xcodebuild test -project LocalTalk.xcodeproj -scheme LocalTalk -destination 'platform=macOS,arch=arm64' 2>&1 | tail -10`
Expected: compile failure — new `AppModel` initializer not found.

- [ ] **Step 3: Write `LocalTalk/AppModel.swift`**

```swift
import Foundation
import Observation
@preconcurrency import AVFoundation

@MainActor @Observable
final class AppModel {
    private(set) var state: DictationState = .idle
    private(set) var lastPartial: String = ""
    private(set) var lastTranscript: String = ""
    private(set) var statusDetail: String = ""
    var onPartial: ((String) -> Void)?

    let settings: SettingsStore
    let history: HistoryStore

    private let engineProvider: (EngineRoute) -> any TranscriptionEngine
    private let audioStart: @MainActor () -> AsyncStream<AVAudioPCMBuffer>
    private let audioStop: @MainActor () -> Void
    private let insertText: @MainActor (String) async -> InsertionResult
    private let frontmostAppName: @MainActor () -> String
    private let minimumDuration: TimeInterval
    private let watchdogSeconds: TimeInterval

    private var activeEngine: (any TranscriptionEngine)?
    private var dictationTask: Task<Void, Never>?
    private var recordingStarted: Date?
    private var targetAppName: String = ""
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    init(settings: SettingsStore,
         history: HistoryStore,
         engineProvider: @escaping (EngineRoute) -> any TranscriptionEngine,
         audioStart: @escaping @MainActor () -> AsyncStream<AVAudioPCMBuffer>,
         audioStop: @escaping @MainActor () -> Void,
         insertText: @escaping @MainActor (String) async -> InsertionResult,
         frontmostAppName: @escaping @MainActor () -> String,
         minimumDuration: TimeInterval = 0.4,
         watchdogSeconds: TimeInterval = 60) {
        self.settings = settings
        self.history = history
        self.engineProvider = engineProvider
        self.audioStart = audioStart
        self.audioStop = audioStop
        self.insertText = insertText
        self.frontmostAppName = frontmostAppName
        self.minimumDuration = minimumDuration
        self.watchdogSeconds = watchdogSeconds
    }

    func toggleDictation() async {
        switch state {
        case .idle, .failed: await startDictation()
        case .recording: stopRecording()
        case .transcribing, .inserting: break   // stop is a no-op mid-pipeline; Cancel is explicit
        }
    }

    private func startDictation() async {
        let route = EngineSelector.route(language: settings.language,
                                         task: settings.task,
                                         override: settings.engineOverride)
        let engine = engineProvider(route)
        guard await engine.isReady(for: currentOptions()) else {
            state = .failed(message: EngineError.modelNotDownloaded(engine.id).localizedDescription)
            return
        }
        activeEngine = engine
        targetAppName = frontmostAppName()
        recordingStarted = Date()
        lastPartial = ""
        state = .recording(started: recordingStarted!)

        let audio = audioStart()
        let options = currentOptions()
        dictationTask = Task { [weak self] in
            await self?.runPipeline(engine: engine, audio: audio, options: options)
        }
    }

    private func stopRecording() {
        guard case .recording(let started) = state else { return }
        if Date().timeIntervalSince(started) < minimumDuration {
            Task { await cancelDictation(reason: "Too short — hold the hotkey while you speak.") }
            return
        }
        state = .transcribing
        audioStop()   // ends the buffer stream; engine finalizes
    }

    func cancelDictation(reason: String = "") async {
        audioStop()
        await activeEngine?.cancel()
        dictationTask?.cancel()
        dictationTask = nil
        activeEngine = nil
        state = reason.isEmpty ? .idle : .failed(message: reason)
        lastPartial = ""
        resumeIdleWaiters()
    }

    private func runPipeline(engine: any TranscriptionEngine,
                             audio: AsyncStream<AVAudioPCMBuffer>,
                             options: TranscriptionOptions) async {
        let watchdog = Task { [watchdogSeconds] in
            try? await Task.sleep(for: .seconds(watchdogSeconds + 300))   // recording can be long; reset below on stop
        }
        defer { watchdog.cancel() }
        do {
            var finalText: String?
            let updates = engine.transcribe(audio: audio, options: options)
            for try await update in updates {
                switch update {
                case .partial(let text):
                    lastPartial = text
                    onPartial?(text)
                case .final(let text):
                    finalText = text
                }
            }
            guard let text = finalText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                finish(.failed(message: "No speech detected."))
                return
            }
            state = .inserting
            let result = settings.pasteAfterTranscription
                ? await insertText(text)
                : .clipboardOnly(reason: "Auto-paste is off")
            lastTranscript = text
            statusDetail = Self.describe(result)
            try? history.append(HistoryEntry(
                id: UUID(), text: text, date: Date(), appName: targetAppName,
                engine: engine.id, language: options.language,
                durationSeconds: recordingStarted.map { Date().timeIntervalSince($0) } ?? 0))
            finish(.idle)
        } catch is CancellationError {
            finish(.idle)
        } catch {
            finish(.failed(message: error.localizedDescription))
        }
    }

    private func finish(_ newState: DictationState) {
        state = newState
        lastPartial = ""
        activeEngine = nil
        dictationTask = nil
        resumeIdleWaiters()
    }

    private func currentOptions() -> TranscriptionOptions {
        TranscriptionOptions(language: settings.language, task: settings.task)
    }

    static func describe(_ result: InsertionResult) -> String {
        switch result {
        case .insertedDirectly: return "Inserted."
        case .pastedViaCmdV: return "Pasted via ⌘V."
        case .clipboardOnly(let reason): return "Copied to clipboard — \(reason)."
        }
    }

    // Test support: await quiescence.
    func waitForIdle() async {
        if dictationTask == nil { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }
    private func resumeIdleWaiters() {
        idleWaiters.forEach { $0.resume() }
        idleWaiters = []
    }
}
```

Note on the watchdog: the real per-phase watchdog (60 s on the transcribing phase only) is wired in Task 11 when the HUD gains a Cancel button; the test hook here keeps a generous ceiling so tests never hang.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -project LocalTalk.xcodeproj -scheme LocalTalk -destination 'platform=macOS,arch=arm64' 2>&1 | tail -5`
Expected: `TEST SUCCEEDED` (22 tests). If a FakeEngine drain race makes `testFullDictationFlow...` flaky, yield after `emitSilence` (`await Task.yield()`) inside the test — determinism beats cleverness here.

- [ ] **Step 5: Commit**

```bash
git add LocalTalk/AppModel.swift LocalTalkTests/AppModelTests.swift
git commit -m "feat: AppModel dictation state machine with injectable services"
```

---

### Task 6: AudioService — AVAudioEngine tap with levels

**Files:**
- Create: `LocalTalk/Services/AudioService.swift`

Unit-testing a live mic is not meaningful; this task is verified manually in Task 7's end-to-end step. Keep the class small and boring.

- [ ] **Step 1: Write `LocalTalk/Services/AudioService.swift`**

```swift
import Foundation
import Observation
@preconcurrency import AVFoundation

@MainActor @Observable
final class AudioService {
    /// 0...1 smoothed input level for the HUD waveform.
    private(set) var level: Float = 0
    private(set) var isRunning = false

    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?

    enum AudioError: LocalizedError {
        case micPermissionDenied
        case engineStartFailed(String)
        var errorDescription: String? {
            switch self {
            case .micPermissionDenied:
                return "Microphone access is denied. Enable it in System Settings → Privacy & Security → Microphone."
            case .engineStartFailed(let m): return "Couldn't start audio input: \(m)"
            }
        }
    }

    static func requestMicPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    /// Starts the mic and returns a stream of native-format buffers.
    /// Both engines resample internally, so no conversion happens here.
    func start() throws -> AsyncStream<AVAudioPCMBuffer> {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw AudioError.micPermissionDenied
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let (stream, continuation) = AsyncStream.makeStream(of: AVAudioPCMBuffer.self,
                                                            bufferingPolicy: .unbounded)
        self.continuation = continuation
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            continuation.yield(buffer)
            let rms = Self.rms(of: buffer)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.level = max(rms, self.level * 0.7)   // fast attack, slow decay
            }
        }
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            self.continuation = nil
            throw AudioError.engineStartFailed(error.localizedDescription)
        }
        isRunning = true
        return stream
    }

    func stop() {
        guard isRunning else { continuation?.finish(); continuation = nil; return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
        isRunning = false
        level = 0
    }

    private nonisolated static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += data[i] * data[i] }
        let rms = sqrt(sum / Float(buffer.frameLength))
        // Normalize roughly like the ObjC app did (+58 dB window)
        let db = 20 * log10(max(rms, 1e-7))
        return min(1, max(0, (db + 58) / 58))
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild build -project LocalTalk.xcodeproj -scheme LocalTalk -configuration Debug -destination 'platform=macOS,arch=arm64' 2>&1 | tail -3`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add LocalTalk/Services/AudioService.swift
git commit -m "feat: AVAudioEngine AudioService with buffer stream and level metering"
```

---

### Task 7: ModelManager + ParakeetEngine — first real dictation

**Files:**
- Create: `LocalTalk/Services/ModelManager.swift`
- Create: `LocalTalk/Engines/ParakeetEngine.swift`
- Modify: `LocalTalk/LocalTalkApp.swift` (temporary debug wiring for manual verify)

- [ ] **Step 1: Write `LocalTalk/Services/ModelManager.swift`**

```swift
import Foundation
import Observation
import FluidAudio

@MainActor @Observable
final class ModelManager {
    enum DownloadState: Equatable {
        case notDownloaded, downloading(Double), ready, failed(String)
    }

    private(set) var parakeetV2: DownloadState = .notDownloaded
    private(set) var parakeetV3: DownloadState = .notDownloaded
    private(set) var whisperLargeTurbo: DownloadState = .notDownloaded

    static let whisperModelName = "large-v3-v20240930_turbo"
    static var whisperDownloadBase: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalTalk/Models/whisperkit", isDirectory: true)
    }
    static var whisperModelFolder: URL {
        whisperDownloadBase.appendingPathComponent(
            "models/argmaxinc/whisperkit-coreml/openai_whisper-\(whisperModelName)")
    }

    func refresh() {
        parakeetV2 = Self.parakeetExists(.v2) ? .ready : .notDownloaded
        parakeetV3 = Self.parakeetExists(.v3) ? .ready : .notDownloaded
        whisperLargeTurbo = FileManager.default.fileExists(atPath: Self.whisperModelFolder.path)
            ? .ready : .notDownloaded
    }

    static func parakeetExists(_ version: AsrModelVersion) -> Bool {
        let dir = AsrModels.defaultCacheDirectory(for: version)
        return AsrModels.modelsExist(at: dir, version: version, encoderPrecision: .int8)
    }

    func downloadParakeet(_ version: AsrModelVersion) async {
        setParakeet(version, .downloading(0))
        do {
            _ = try await AsrModels.download(version: version) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.setParakeet(version, .downloading(progress.fractionCompleted))
                }
            }
            setParakeet(version, .ready)
        } catch {
            setParakeet(version, .failed(error.localizedDescription))
        }
    }

    private func setParakeet(_ version: AsrModelVersion, _ state: DownloadState) {
        if version == .v2 { parakeetV2 = state } else { parakeetV3 = state }
    }
}
```

(The WhisperKit download half of ModelManager is added in Task 8 — this task keeps the diff focused on Parakeet.)

- [ ] **Step 2: Write `LocalTalk/Engines/ParakeetEngine.swift`**

```swift
import Foundation
@preconcurrency import AVFoundation
import FluidAudio

/// Streaming Parakeet engine. One instance per utterance is fine; model load is cached by FluidAudio.
actor ParakeetEngine: TranscriptionEngine {
    nonisolated let id: EngineID = .parakeet
    private let version: AsrModelVersion
    private var manager: SlidingWindowAsrManager?
    private var cancelled = false

    init(version: ParakeetVersion) {
        self.version = (version == .v2) ? .v2 : .v3
    }

    nonisolated func isReady(for options: TranscriptionOptions) async -> Bool {
        let v = version
        return ModelManager.parakeetExists(v)
    }

    func prepare(options: TranscriptionOptions, progress: @escaping @Sendable (Double) -> Void) async throws {
        let models = try await AsrModels.downloadAndLoad(version: version) { p in
            progress(p.fractionCompleted)
        }
        let m = SlidingWindowAsrManager(config: .streaming)
        try await m.loadModels(models)
        manager = m
    }

    nonisolated func transcribe(audio: AsyncStream<AVAudioPCMBuffer>, options: TranscriptionOptions)
        -> AsyncThrowingStream<TranscriptionUpdate, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.run(audio: audio, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func run(audio: AsyncStream<AVAudioPCMBuffer>,
                     continuation: AsyncThrowingStream<TranscriptionUpdate, Error>.Continuation) async throws {
        cancelled = false
        if manager == nil {
            try await prepare(options: TranscriptionOptions(language: "en", task: .transcribe)) { _ in }
        }
        guard let manager else { throw EngineError.modelNotDownloaded(.parakeet) }
        try await manager.startStreaming(source: .microphone)

        // Relay volatile/confirmed updates as partials while audio flows.
        let updatesTask = Task {
            var confirmed = ""
            for await update in await manager.transcriptionUpdates {
                if update.isConfirmed { confirmed += update.text }
                let display = (confirmed + (update.isConfirmed ? "" : " " + update.text))
                    .trimmingCharacters(in: .whitespaces)
                continuation.yield(.partial(display))
            }
        }

        for await buffer in audio {
            if cancelled { break }
            await manager.streamAudio(buffer)
        }
        updatesTask.cancel()

        if cancelled {
            await manager.cancel()
            try? await manager.reset()
            continuation.finish(throwing: EngineError.cancelled)
            return
        }
        let text = try await manager.finish()
        try? await manager.reset()
        continuation.yield(.final(text))
        continuation.finish()
    }

    func cancel() async { cancelled = true }
}
```

- [ ] **Step 3: Temporary debug wiring in `LocalTalk/LocalTalkApp.swift`** — replace the file with:

```swift
import SwiftUI
@preconcurrency import AVFoundation

@main
struct LocalTalkApp: App {
    @State private var appModel = AppComposition.makeAppModel()

    var body: some Scene {
        MenuBarExtra("LocalTalk", systemImage: menuIcon) {
            Text(statusLine)
            if !appModel.lastPartial.isEmpty { Text(appModel.lastPartial).font(.caption) }
            Divider()
            Button(buttonTitle) { Task { await appModel.toggleDictation() } }
            Button("Copy Last Transcript") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(appModel.lastTranscript, forType: .string)
            }.disabled(appModel.lastTranscript.isEmpty)
            Divider()
            Button("Quit LocalTalk") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }

    private var menuIcon: String {
        switch appModel.state {
        case .idle: "waveform"
        case .recording: "mic.circle.fill"
        case .transcribing, .inserting: "ellipsis.circle"
        case .failed: "exclamationmark.circle"
        }
    }
    private var statusLine: String {
        switch appModel.state {
        case .idle: "Ready"
        case .recording: "Listening…"
        case .transcribing: "Transcribing…"
        case .inserting: "Inserting…"
        case .failed(let m): m
        }
    }
    private var buttonTitle: String {
        if case .recording = appModel.state { "Stop and Transcribe" } else { "Start Dictation" }
    }
}

@MainActor
enum AppComposition {
    static let audio = AudioService()

    static func makeAppModel() -> AppModel {
        let settings = SettingsStore()
        return AppModel(
            settings: settings,
            history: HistoryStore(),
            engineProvider: { route in
                switch route.engine {
                case .parakeet: ParakeetEngine(version: route.parakeetVersion ?? .v2)
                case .whisperKit: ParakeetEngine(version: .v2)   // placeholder until Task 8
                }
            },
            audioStart: { (try? audio.start()) ?? AsyncStream { $0.finish() } },
            audioStop: { audio.stop() },
            insertText: { text in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                return .clipboardOnly(reason: "PasteService arrives in Task 10")
            },
            frontmostAppName: { NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown" }
        )
    }
}
```

- [ ] **Step 4: Build, run, and dictate for real**

```bash
xcodegen generate
xcodebuild build -project LocalTalk.xcodeproj -scheme LocalTalk -configuration Debug -destination 'platform=macOS,arch=arm64'
open "$(xcodebuild -project LocalTalk.xcodeproj -scheme LocalTalk -configuration Debug -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR/{print $3}')/LocalTalk.app"
```

Manual verification (user does this — it needs mic + a voice):
1. Click menu bar icon → Start Dictation. First run: grant mic permission; the Parakeet v2 model (~600 MB) downloads on first use — watch Console.app or just wait (this UX gap is fixed by onboarding in Task 13).
2. Speak a few sentences with natural pauses; watch the partial text appear in the menu (open it while recording).
3. Stop and Transcribe → transcript lands on the clipboard; paste into TextEdit and check accuracy — THIS is the accuracy A/B against the old base.en app.

- [ ] **Step 5: Commit**

```bash
git add LocalTalk/Services/ModelManager.swift LocalTalk/Engines/ParakeetEngine.swift LocalTalk/LocalTalkApp.swift
git commit -m "feat: ParakeetEngine streaming dictation with ModelManager (first real transcription)"
```

---

### Task 8: WhisperKitEngine + WhisperKit model management

**Files:**
- Create: `LocalTalk/Engines/WhisperKitEngine.swift`
- Modify: `LocalTalk/Services/ModelManager.swift` (add WhisperKit download)
- Modify: `LocalTalk/LocalTalkApp.swift` (route .whisperKit to the real engine)

- [ ] **Step 1: Write `LocalTalk/Engines/WhisperKitEngine.swift`**

WhisperKit OSS has no low-latency streaming; this engine records to a temp file and batch-transcribes at stop. The HUD shows "Transcribing…" instead of partials for these languages — acceptable, documented in the spec.

```swift
import Foundation
@preconcurrency import AVFoundation
import WhisperKit

actor WhisperKitEngine: TranscriptionEngine {
    nonisolated let id: EngineID = .whisperKit
    private static var shared: WhisperKit?     // model load is expensive (CoreML specialization); reuse
    private var transcribeTask: Task<Void, Never>?
    private var cancelled = false

    nonisolated func isReady(for options: TranscriptionOptions) async -> Bool {
        FileManager.default.fileExists(atPath: ModelManager.whisperModelFolder.path)
    }

    func prepare(options: TranscriptionOptions, progress: @escaping @Sendable (Double) -> Void) async throws {
        if Self.shared != nil { progress(1); return }
        let folder: URL
        if FileManager.default.fileExists(atPath: ModelManager.whisperModelFolder.path) {
            folder = ModelManager.whisperModelFolder
        } else {
            folder = try await WhisperKit.download(
                variant: ModelManager.whisperModelName,
                downloadBase: ModelManager.whisperDownloadBase,
                progressCallback: { p in progress(p.fractionCompleted * 0.8) })
        }
        let pipe = try await WhisperKit(WhisperKitConfig(prewarm: false, load: false, download: false))
        pipe.modelFolder = folder
        try await pipe.prewarmModels()
        progress(0.9)
        try await pipe.loadModels()
        progress(1.0)
        Self.shared = pipe
    }

    nonisolated func transcribe(audio: AsyncStream<AVAudioPCMBuffer>, options: TranscriptionOptions)
        -> AsyncThrowingStream<TranscriptionUpdate, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do { try await self.run(audio: audio, options: options, continuation: continuation) }
                catch { continuation.finish(throwing: error) }
            }
        }
    }

    private func run(audio: AsyncStream<AVAudioPCMBuffer>, options: TranscriptionOptions,
                     continuation: AsyncThrowingStream<TranscriptionUpdate, Error>.Continuation) async throws {
        cancelled = false
        // 1) Spool mic buffers to a temp CAF file in the buffers' native format.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("localtalk-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        var file: AVAudioFile?
        for await buffer in audio {
            if cancelled { break }
            if file == nil {
                file = try AVAudioFile(forWriting: url, settings: buffer.format.settings)
            }
            try file?.write(from: buffer)
        }
        file = nil   // flush/close
        if cancelled { continuation.finish(throwing: EngineError.cancelled); return }
        guard FileManager.default.fileExists(atPath: url.path) else {
            continuation.finish(throwing: EngineError.engineFailure("No audio was recorded.")); return
        }

        // 2) Ensure model is loaded, then batch transcribe.
        if Self.shared == nil { try await prepare(options: options) { _ in } }
        guard let pipe = Self.shared else { throw EngineError.modelNotDownloaded(.whisperKit) }
        let decode = DecodingOptions(
            task: options.task == .translate ? .translate : .transcribe,
            language: options.language,
            temperature: 0,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            chunkingStrategy: .vad)
        let results = try await pipe.transcribe(audioPath: url.path, decodeOptions: decode)
        if cancelled { continuation.finish(throwing: EngineError.cancelled); return }
        let text = results.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        continuation.yield(.final(text))
        continuation.finish()
    }

    func cancel() async { cancelled = true }
}
```

- [ ] **Step 2: Add WhisperKit download to `ModelManager`** — append this method to the class:

```swift
    func downloadWhisper() async {
        whisperLargeTurbo = .downloading(0)
        do {
            _ = try await WhisperKit.download(
                variant: Self.whisperModelName,
                downloadBase: Self.whisperDownloadBase,
                progressCallback: { [weak self] p in
                    let fraction = p.fractionCompleted
                    Task { @MainActor [weak self] in self?.whisperLargeTurbo = .downloading(fraction) }
                })
            whisperLargeTurbo = .ready
        } catch {
            whisperLargeTurbo = .failed(error.localizedDescription)
        }
    }
```

and `import WhisperKit` at the top of `ModelManager.swift`.

- [ ] **Step 3: Fix the Task 7 placeholder in `LocalTalkApp.swift`**

Replace the `engineProvider` closure body:

```swift
            engineProvider: { route in
                switch route.engine {
                case .parakeet: ParakeetEngine(version: route.parakeetVersion ?? .v2)
                case .whisperKit: WhisperKitEngine()
                }
            },
```

- [ ] **Step 4: Build + manual verify translate/multilingual**

Run: `xcodegen generate && xcodebuild build -project LocalTalk.xcodeproj -scheme LocalTalk -configuration Debug -destination 'platform=macOS,arch=arm64' 2>&1 | tail -3`
Expected: `BUILD SUCCEEDED`.

Manual (user): temporarily set language to Tagalog via `defaults write com.armageddonvivas.LocalTalk language tl`, relaunch, dictate in Tagalog. First run downloads the ~600 MB turbo model and pre-warms CoreML (can take minutes — one-time). Verify the transcript. Reset with `defaults write com.armageddonvivas.LocalTalk language en`. (Settings UI for this arrives in Task 12.)

- [ ] **Step 5: Run full test suite, then commit**

Run: `xcodebuild test -project LocalTalk.xcodeproj -scheme LocalTalk -destination 'platform=macOS,arch=arm64' 2>&1 | tail -3`
Expected: `TEST SUCCEEDED`.

```bash
git add LocalTalk/Engines/WhisperKitEngine.swift LocalTalk/Services/ModelManager.swift LocalTalk/LocalTalkApp.swift
git commit -m "feat: WhisperKitEngine for multilingual + translate via temp-file batch"
```

---

### Task 9: HotkeyService — remappable, toggle + push-to-talk

**Files:**
- Create: `LocalTalk/Services/HotkeyService.swift`
- Modify: `LocalTalk/LocalTalkApp.swift` (wire hotkey to AppModel)

- [ ] **Step 1: Write `LocalTalk/Services/HotkeyService.swift`**

```swift
import Foundation
import Carbon.HIToolbox

/// Global hotkey via Carbon RegisterEventHotKey.
/// kEventHotKeyPressed/kEventHotKeyReleased give us push-to-talk without Input Monitoring permission.
@MainActor
final class HotkeyService {
    var onPressed: (() -> Void)?
    var onReleased: (() -> Void)?
    private(set) var registrationError: String?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private static let signature: OSType = 0x4C544B31 // 'LTK1'

    func register(_ spec: HotkeySpec) {
        unregister()
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
            let kind = GetEventKind(event)
            DispatchQueue.main.async {
                if kind == UInt32(kEventHotKeyPressed) { service.onPressed?() }
                else if kind == UInt32(kEventHotKeyReleased) { service.onReleased?() }
            }
            return noErr
        }, 2, &eventTypes, selfPtr, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(spec.keyCode, spec.carbonModifiers, hotKeyID,
                                         GetEventDispatcherTarget(), 0, &hotKeyRef)
        registrationError = status == noErr ? nil
            : "Couldn't register \(spec.displayString) — another app may be using it. Pick a different shortcut."
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef); self.hotKeyRef = nil }
        if let handlerRef { RemoveEventHandler(handlerRef); self.handlerRef = nil }
    }
}
```

- [ ] **Step 2: Wire into `AppComposition` in `LocalTalkApp.swift`** — add below `static let audio`:

```swift
    static let hotkey = HotkeyService()

    static func wireHotkey(to model: AppModel) {
        hotkey.onPressed = { [weak model] in
            guard let model else { return }
            Task { @MainActor in
                switch model.settings.hotkeyMode {
                case .toggle: await model.toggleDictation()
                case .pushToTalk:
                    if case .idle = model.state { await model.toggleDictation() }
                    if case .failed = model.state { await model.toggleDictation() }
                }
            }
        }
        hotkey.onReleased = { [weak model] in
            guard let model else { return }
            Task { @MainActor in
                guard model.settings.hotkeyMode == .pushToTalk else { return }
                if case .recording = model.state { await model.toggleDictation() }
            }
        }
        hotkey.register(model.settings.hotkey)
    }
```

and call `AppComposition.wireHotkey(to: model)` once at startup — in `LocalTalkApp.init()`:

```swift
    init() {
        let model = AppComposition.makeAppModel()
        _appModel = State(initialValue: model)
        AppComposition.wireHotkey(to: model)
    }
```

- [ ] **Step 3: Build + manual verify**

Run: `xcodegen generate && xcodebuild build ... | tail -3` → `BUILD SUCCEEDED`. Launch:
1. Toggle mode: press ⌃⌥Space anywhere → recording starts; again → transcribes.
2. `defaults write com.armageddonvivas.LocalTalk hotkeyMode pushToTalk`, relaunch: hold ⌃⌥Space, speak, release → transcribes. (Settings UI in Task 12.)

- [ ] **Step 4: Commit**

```bash
git add LocalTalk/Services/HotkeyService.swift LocalTalk/LocalTalkApp.swift
git commit -m "feat: remappable Carbon hotkey with toggle and push-to-talk modes"
```

---

### Task 10: PasteService — honest insertion with clipboard restore

**Files:**
- Create: `LocalTalk/Services/PasteService.swift`
- Modify: `LocalTalk/LocalTalkApp.swift` (replace clipboard-only placeholder)

- [ ] **Step 1: Write `LocalTalk/Services/PasteService.swift`**

```swift
import AppKit
import ApplicationServices

@MainActor
final class PasteService {
    /// Captured when recording starts so a long transcription can't paste into the wrong app.
    private(set) var targetApp: NSRunningApplication?

    func captureTarget() {
        targetApp = NSWorkspace.shared.frontmostApplication
    }

    var targetAppName: String { targetApp?.localizedName ?? "Unknown" }

    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func insert(_ text: String, alsoCopy: Bool) async -> InsertionResult {
        // Always leave the transcript on the clipboard afterwards if the user asked for that.
        defer { if alsoCopy { Self.setClipboard(text) } }

        guard Self.isAccessibilityTrusted else {
            Self.setClipboard(text)
            return .clipboardOnly(reason: "grant Accessibility in System Settings to paste automatically")
        }
        // Reactivate the app that was focused when recording started.
        if let target = targetApp, NSWorkspace.shared.frontmostApplication != target {
            target.activate()
            try? await Task.sleep(for: .milliseconds(150))
        }
        if axInsert(text) { return .insertedDirectly }
        return await pasteViaCmdV(text, preserveClipboard: !alsoCopy)
    }

    private func axInsert(_ text: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused else { return false }
        let axElement = element as! AXUIElement
        return AXUIElementSetAttributeValue(axElement, kAXSelectedTextAttribute as CFString, text as CFString) == .success
    }

    private func pasteViaCmdV(_ text: String, preserveClipboard: Bool) async -> InsertionResult {
        let pasteboard = NSPasteboard.general
        let saved: [NSPasteboardItem] = preserveClipboard ? pasteboard.pasteboardItems?.map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        } ?? [] : []

        Self.setClipboard(text)
        let source = CGEventSource(stateID: .combinedSessionState)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)   // kVK_ANSI_V
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)

        if preserveClipboard && !saved.isEmpty {
            try? await Task.sleep(for: .milliseconds(400))   // let the target app read the pasteboard first
            pasteboard.clearContents()
            pasteboard.writeObjects(saved)
        }
        return .pastedViaCmdV
    }

    private static func setClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
```

- [ ] **Step 2: Wire into `AppComposition`** — add `static let paste = PasteService()`, change `insertText:` to

```swift
            insertText: { text in
                await paste.insert(text, alsoCopy: true)
            },
            frontmostAppName: { paste.targetAppName },
```

and make AppModel capture the target at start: in `AppModel.startDictation()`, the `frontmostAppName()` call stays, but add a capture hook. Add to AppModel init parameters: `captureTarget: @escaping @MainActor () -> Void = {}` stored as `private let captureTarget`, called first line of `startDictation()`. In `AppComposition`: `captureTarget: { paste.captureTarget() }`. (Update `AppModelTests.makeModel` with `captureTarget: {}` — default arg keeps existing tests compiling.)

- [ ] **Step 3: Build + tests**

Run: `xcodegen generate && xcodebuild test ... | tail -3` → `TEST SUCCEEDED`.

- [ ] **Step 4: Manual verify (user)**
1. Launch, trigger Accessibility prompt (System Settings opens; add LocalTalk).
2. Focus TextEdit, hotkey, speak, stop → text appears IN TextEdit ("Inserted." path).
3. Copy something else (e.g. "abc"), dictate into Safari's search field → text arrives; if ⌘V fallback was used and Copy-to-clipboard is off, "abc" is restored to the clipboard afterward.
4. Revoke Accessibility → dictate → status honestly reports clipboard-only with guidance.

- [ ] **Step 5: Commit**

```bash
git add LocalTalk/Services/PasteService.swift LocalTalk/AppModel.swift LocalTalk/LocalTalkApp.swift LocalTalkTests/AppModelTests.swift
git commit -m "feat: PasteService with target capture, AX insert, clipboard-preserving fallback"
```

---

### Task 11: Floating HUD — port the brand, add streaming text + cancel

**Files:**
- Create: `LocalTalk/UI/HUD/HUDPanelController.swift`
- Create: `LocalTalk/UI/HUD/HUDView.swift`
- Modify: `LocalTalk/LocalTalkApp.swift` (show/hide HUD on state changes)
- Modify: `LocalTalk/AppModel.swift` (Esc cancel + 60 s transcription watchdog)

- [ ] **Step 1: Write `LocalTalk/UI/HUD/HUDView.swift`** (SwiftUI port of the ObjC HUD design)

```swift
import SwiftUI

struct HUDView: View {
    let state: DictationState
    let level: Float
    let partial: String
    let language: String
    var onCancel: () -> Void

    private var isFailed: Bool { if case .failed = state { true } else { false } }
    private var accent: Color { isFailed ? Theme.failure : Theme.accent }

    var body: some View {
        HStack(spacing: 12) {
            Image("MenuIcon").resizable().scaledToFit()
                .frame(width: 34, height: 34).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                Text(detail).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    .lineLimit(1).truncationMode(.head)
            }
            Spacer(minLength: 8)
            WaveformBars(state: state, level: level, accent: accent)
            badge("LOCAL")
            badge(language.uppercased())
            if case .transcribing = state {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(width: 380, height: 76)
        .background(
            LinearGradient(colors: [Color(red: 13/255, green: 17/255, blue: 23/255),
                                    Color(red: 9/255, green: 12/255, blue: 16/255)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .overlay(RoundedRectangle(cornerRadius: 19)
            .stroke(Color(red: 46/255, green: 73/255, blue: 91/255), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 19))
        .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
    }

    private var title: String {
        switch state {
        case .recording: "Listening"
        case .transcribing: "Transcribing"
        case .inserting: "Inserting"
        case .failed: "Failed"
        case .idle: "LocalTalk"
        }
    }
    private var detail: String {
        if case .failed(let m) = state { return m }
        if !partial.isEmpty { return partial }
        if case .recording(let started) = state {
            return "\(Int(Date().timeIntervalSince(started)))s — Esc to cancel"
        }
        return "On-device transcription"
    }
    private func badge(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(isFailed ? Theme.failure : Theme.accentText)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().stroke(accent.opacity(0.5), lineWidth: 1))
    }
}

struct WaveformBars: View {
    let state: DictationState
    let level: Float
    let accent: Color
    private let heights: [CGFloat] = [0.35, 0.6, 1.0, 0.75, 0.5, 0.8, 0.4]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i >= 2 && i <= 4 ? accent : Color(red: 85/255, green: 96/255, blue: 107/255))
                    .frame(width: 4, height: barHeight(i))
                    .animation(.easeOut(duration: 0.16), value: level)
            }
        }
    }
    private func barHeight(_ i: Int) -> CGFloat {
        let base = heights[i] * 22
        switch state {
        case .recording: return max(4, base * CGFloat(0.25 + 0.75 * level))
        case .transcribing, .inserting: return max(4, base * 0.5)
        case .failed: return 4
        case .idle: return base * 0.3
        }
    }
}
```

(Add an image set named `MenuIcon` in Assets.xcassets using `Assets/LocalTalkLogo.png`, or substitute `Image(systemName: "waveform.circle.fill")` if the logo copy step is skipped.)

- [ ] **Step 2: Write `LocalTalk/UI/HUD/HUDPanelController.swift`**

```swift
import AppKit
import SwiftUI

@MainActor
final class HUDPanelController {
    private var panel: NSPanel?

    func show<Content: View>(@ViewBuilder content: () -> Content) {
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 76),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.level = .statusBar
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false                 // SwiftUI draws its own shadow
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.isMovableByWindowBackground = true
            panel = p
        }
        panel?.contentView = NSHostingView(rootView: content())
        position(panel!)
        panel?.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }

    private func position(_ panel: NSPanel) {
        let defaults = UserDefaults.standard
        // Restore per-screen saved position; fall back to bottom-center of the screen with the mouse.
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        guard let screen else { return }
        let key = "hudOrigin-\(screen.localizedName)"
        if let saved = defaults.string(forKey: key) {
            let origin = NSPointFromString(saved)
            if screen.visibleFrame.contains(origin) { panel.setFrameOrigin(origin); return }
        }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - 190, y: frame.minY + 24))
    }

    func persistPosition() {
        guard let panel, let screen = panel.screen else { return }
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin),
                                  forKey: "hudOrigin-\(screen.localizedName)")
    }
}
```

- [ ] **Step 3: Wire HUD + Esc + watchdog**

In `AppComposition`: `static let hud = HUDPanelController()`. In `LocalTalkApp`, observe state via `onChange` on a small bridging view, or simpler: give AppModel an `onStateChange` closure. Add to AppModel:

```swift
    var onStateChange: ((DictationState) -> Void)?
    // call onStateChange?(state) in a didSet on `state` (convert `state` to: private(set) var state ... { didSet { onStateChange?(state) } })
```

In `AppComposition.wireHotkey` (rename to `wire(model:)`), add:

```swift
        model.onStateChange = { state in
            switch state {
            case .recording, .transcribing, .inserting:
                hud.show {
                    HUDStateView(model: model)   // small @Observable-driven wrapper below
                }
            case .failed:
                hud.show { HUDStateView(model: model) }
                Task { try? await Task.sleep(for: .seconds(3)); await MainActor.run {
                    if case .failed = model.state { hud.hide() } } }
            case .idle:
                Task { try? await Task.sleep(for: .milliseconds(600)); await MainActor.run {
                    if case .idle = model.state { hud.hide() } } }
            }
        }
```

```swift
struct HUDStateView: View {
    var model: AppModel
    var body: some View {
        HUDView(state: model.state,
                level: AppComposition.audio.level,
                partial: model.lastPartial,
                language: model.settings.language,
                onCancel: { Task { await model.cancelDictation() } })
    }
}
```

Esc cancel: NSEvent local monitors don't fire globally without permissions; instead register a SECOND Carbon hotkey for plain Esc (keyCode 53, no modifiers) that is registered ONLY while recording/transcribing and unregistered on idle — add `registerEscape(onPress:)`/`unregisterEscape()` to HotkeyService following the same pattern with `EventHotKeyID(signature:, id: 2)`, and call them from `onStateChange`.

Watchdog: in `AppModel.stopRecording()` after setting `.transcribing`, start `watchdogTask = Task { try? await Task.sleep(for: .seconds(60)); if case .transcribing = self.state { await self.cancelDictation(reason: EngineError.timedOut.localizedDescription) } }`; cancel `watchdogTask` in `finish(_:)`.

- [ ] **Step 4: Build + tests + manual verify**

`xcodegen generate && xcodebuild test ... | tail -3` → `TEST SUCCEEDED`.
Manual: dictate → HUD slides up bottom-center with live bars and streaming words (Parakeet path); Esc cancels; drag the HUD, dictate again → position remembered; on a failure (rename the model folder temporarily) bars flatten red and the message reads like English.

- [ ] **Step 5: Commit**

```bash
git add LocalTalk/UI/HUD LocalTalk/AppModel.swift LocalTalk/Services/HotkeyService.swift LocalTalk/LocalTalkApp.swift
git commit -m "feat: floating HUD with streaming partials, Esc cancel, transcription watchdog"
```

---

### Task 12: Menu bar content + main window (History, Settings)

**Files:**
- Create: `LocalTalk/UI/MenuBarView.swift`
- Create: `LocalTalk/UI/MainWindow/MainWindowView.swift`
- Create: `LocalTalk/UI/MainWindow/HistoryView.swift`
- Create: `LocalTalk/UI/MainWindow/SettingsView.swift`
- Modify: `LocalTalk/LocalTalkApp.swift`

This is foundation-grade UI: correct, on-brand, resizable. The taste pass (hover states, motion, empty states) is Phase 2 by design — don't gold-plate here.

- [ ] **Step 1: Write `LocalTalk/UI/MenuBarView.swift`** (extracted from the Task 7 debug menu, plus window opener)

```swift
import SwiftUI

struct MenuBarView: View {
    var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(primaryTitle) { Task { await model.toggleDictation() } }
        Text(statusLine)
        Divider()
        Button("Open LocalTalk") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }.keyboardShortcut("0")
        Button("Copy Last Transcript") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(model.lastTranscript, forType: .string)
        }.disabled(model.lastTranscript.isEmpty)
        Divider()
        Button("Quit LocalTalk") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }

    private var primaryTitle: String {
        if case .recording = model.state { "Stop and Transcribe" } else { "Start Dictation  \(model.settings.hotkey.displayString)" }
    }
    private var statusLine: String {
        switch model.state {
        case .idle: "Ready — \(model.settings.language.uppercased()) · on-device"
        case .recording: "Listening…"
        case .transcribing: "Transcribing…"
        case .inserting: "Inserting…"
        case .failed(let m): m
        }
    }
}
```

- [ ] **Step 2: Write `LocalTalk/UI/MainWindow/MainWindowView.swift`**

```swift
import SwiftUI

enum MainSection: String, CaseIterable, Identifiable {
    case history = "History", settings = "Settings"
    var id: String { rawValue }
    var icon: String { self == .history ? "clock.arrow.circlepath" : "slider.horizontal.3" }
}

struct MainWindowView: View {
    var model: AppModel
    var modelManager: ModelManager
    @State private var section: MainSection = .history

    var body: some View {
        NavigationSplitView {
            List(MainSection.allCases, selection: $section) { s in
                Label(s.rawValue, systemImage: s.icon).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
            .safeAreaInset(edge: .top) {
                HStack(spacing: 10) {
                    Image("MenuIcon").resizable().frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("LocalTalk").font(.system(size: 16, weight: .bold))
                        Text("Private input").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                }.padding(12)
            }
        } detail: {
            switch section {
            case .history: HistoryView(history: model.history)
            case .settings: SettingsView(model: model, modelManager: modelManager)
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }
}
```

- [ ] **Step 3: Write `LocalTalk/UI/MainWindow/HistoryView.swift`**

```swift
import SwiftUI

struct HistoryView: View {
    var history: HistoryStore
    @State private var query = ""
    @State private var confirmClear = false

    private var results: [HistoryEntry] { history.search(query) }

    var body: some View {
        List(results) { entry in
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.text).font(.system(size: 13)).lineLimit(3).textSelection(.enabled)
                HStack(spacing: 8) {
                    Text(entry.appName)
                    Text(entry.date, style: .time).monospacedDigit()
                    Text(entry.engine.rawValue).foregroundStyle(Theme.accent)
                }.font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
            .padding(.vertical, 4)
            .contextMenu {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.text, forType: .string)
                }
            }
        }
        .searchable(text: $query, prompt: "Search transcripts")
        .overlay {
            if results.isEmpty {
                ContentUnavailableView(query.isEmpty ? "No transcripts yet" : "No matches",
                    systemImage: "waveform",
                    description: Text(query.isEmpty ? "Press \(AppComposition.hotkeyDisplay) in any app to dictate." : ""))
            }
        }
        .toolbar {
            Button("Export…") { export() }
            Button("Clear", role: .destructive) { confirmClear = true }
        }
        .confirmationDialog("Delete all transcripts?", isPresented: $confirmClear) {
            Button("Delete All", role: .destructive) { try? history.clear() }
        }
        .navigationTitle("History")
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "LocalTalk-transcripts.txt"
        if panel.runModal() == .OK, let url = panel.url {
            try? history.exportPlainText().write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
```

(Add `static var hotkeyDisplay: String { SettingsStore().hotkey.displayString }` to `AppComposition` — or pass the settings object through; either is fine, just keep it compiling.)

- [ ] **Step 4: Write `LocalTalk/UI/MainWindow/SettingsView.swift`**

```swift
import SwiftUI
import FluidAudio

struct SettingsView: View {
    var model: AppModel
    var modelManager: ModelManager
    @State private var recordingHotkey = false

    private let languages: [(code: String, name: String)] = [
        ("en", "English"), ("tl", "Filipino (Tagalog)"), ("es", "Spanish"), ("fr", "French"),
        ("de", "German"), ("it", "Italian"), ("pt", "Portuguese"), ("ja", "Japanese"),
        ("ko", "Korean"), ("zh", "Chinese"),
    ]

    var body: some View {
        Form {
            Section("Dictation") {
                Picker("Language", selection: languageBinding) {
                    ForEach(languages, id: \.code) { Text($0.name).tag($0.code) }
                }
                Picker("Mode", selection: taskBinding) {
                    Text("Transcribe").tag(DictationTask.transcribe)
                    Text("Translate to English").tag(DictationTask.translate)
                }
                Toggle("Paste into the focused app", isOn: pasteBinding)
                Toggle("Play sounds", isOn: soundsBinding)
            }
            Section("Hotkey") {
                LabeledContent("Shortcut") {
                    Button(recordingHotkey ? "Press keys…" : model.settings.hotkey.displayString) {
                        recordingHotkey = true
                    }
                    .background(HotkeyRecorder(isRecording: $recordingHotkey) { spec in
                        model.settings.hotkey = spec
                        AppComposition.hotkey.register(spec)
                    })
                }
                Picker("Behavior", selection: hotkeyModeBinding) {
                    Text("Toggle — press to start, press to stop").tag(HotkeyMode.toggle)
                    Text("Push to talk — hold while speaking").tag(HotkeyMode.pushToTalk)
                }
                if let err = AppComposition.hotkey.registrationError {
                    Text(err).font(.caption).foregroundStyle(Theme.failure)
                }
            }
            Section("Models") {
                modelRow("Parakeet — fast English", state: modelManager.parakeetV2) {
                    Task { await modelManager.downloadParakeet(.v2) }
                }
                modelRow("Parakeet — European languages", state: modelManager.parakeetV3) {
                    Task { await modelManager.downloadParakeet(.v3) }
                }
                modelRow("Whisper — all languages + translate", state: modelManager.whisperLargeTurbo) {
                    Task { await modelManager.downloadWhisper() }
                }
            }
            Section("Permissions") {
                LabeledContent("Microphone") {
                    Button("Request") { Task { _ = await AudioService.requestMicPermission() } }
                }
                LabeledContent("Accessibility (auto-paste)") {
                    Button(PasteService.isAccessibilityTrusted ? "Granted" : "Request") {
                        PasteService.requestAccessibility()
                    }.disabled(PasteService.isAccessibilityTrusted)
                }
            }
            Section {
                Text("Includes NVIDIA Parakeet, © NVIDIA, CC-BY-4.0. Transcription runs entirely on this Mac; the only network use is downloading models above.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear { modelManager.refresh() }
    }

    private func modelRow(_ title: String, state: ModelManager.DownloadState,
                          download: @escaping () -> Void) -> some View {
        LabeledContent(title) {
            switch state {
            case .ready: Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .notDownloaded: Button("Download", action: download)
            case .downloading(let p): ProgressView(value: p).frame(width: 120)
            case .failed(let msg): Button("Retry — \(msg)", action: download).foregroundStyle(Theme.failure)
            }
        }
    }

    private var languageBinding: Binding<String> {
        Binding(get: { model.settings.language }, set: { model.settings.language = $0 })
    }
    private var taskBinding: Binding<DictationTask> {
        Binding(get: { model.settings.task }, set: { model.settings.task = $0 })
    }
    private var pasteBinding: Binding<Bool> {
        Binding(get: { model.settings.pasteAfterTranscription }, set: { model.settings.pasteAfterTranscription = $0 })
    }
    private var soundsBinding: Binding<Bool> {
        Binding(get: { model.settings.playSounds }, set: { model.settings.playSounds = $0 })
    }
    private var hotkeyModeBinding: Binding<HotkeyMode> {
        Binding(get: { model.settings.hotkeyMode }, set: { model.settings.hotkeyMode = $0 })
    }
}

/// Invisible NSView that captures the next keyDown while recording a new hotkey.
struct HotkeyRecorder: NSViewRepresentable {
    @Binding var isRecording: Bool
    var onCapture: (HotkeySpec) -> Void

    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        if isRecording && context.coordinator.monitor == nil {
            context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let carbonMods = HotkeyRecorder.carbonFlags(from: event.modifierFlags)
                if carbonMods != 0 || event.keyCode == 53 {   // require a modifier; Esc cancels
                    if event.keyCode != 53 {
                        onCapture(HotkeySpec(keyCode: UInt32(event.keyCode), carbonModifiers: carbonMods))
                    }
                    Task { @MainActor in isRecording = false }
                    context.coordinator.stop()
                    return nil
                }
                return event
            }
        } else if !isRecording {
            context.coordinator.stop()
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator {
        var monitor: Any?
        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        }
    }

    static func carbonFlags(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= 0x0100 }
        if flags.contains(.shift)   { carbon |= 0x0200 }
        if flags.contains(.option)  { carbon |= 0x0800 }
        if flags.contains(.control) { carbon |= 0x1000 }
        return carbon
    }
}
```

- [ ] **Step 5: Replace the debug scene in `LocalTalkApp.swift`**

```swift
    var body: some Scene {
        MenuBarExtra("LocalTalk", systemImage: menuIcon) {
            MenuBarView(model: appModel)
        }
        Window("LocalTalk", id: "main") {
            MainWindowView(model: appModel, modelManager: AppComposition.modelManager)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 760, height: 480)
    }
```

Add `static let modelManager = ModelManager()` to `AppComposition`. Keep `menuIcon` computed property.

- [ ] **Step 6: Build, tests, manual verify, commit**

`xcodegen generate && xcodebuild test ... | tail -3` → `TEST SUCCEEDED`. Manual: open window from menu → resizable dark window; change language to Filipino in Settings (no more `defaults write`); remap hotkey by clicking the shortcut button and pressing ⌘⇧D → menu shows new shortcut and it works; History shows dictations with search/export/clear.

```bash
git add LocalTalk/UI LocalTalk/LocalTalkApp.swift
git commit -m "feat: menu bar view and main window with history and full settings"
```

---

### Task 13: Onboarding — first launch to first dictation without dead ends

**Files:**
- Create: `LocalTalk/UI/Onboarding/OnboardingView.swift`
- Modify: `LocalTalk/LocalTalkApp.swift`

- [ ] **Step 1: Write `LocalTalk/UI/Onboarding/OnboardingView.swift`**

```swift
import SwiftUI

struct OnboardingView: View {
    var model: AppModel
    var modelManager: ModelManager
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var micGranted = AVCaptureAuthHelper.isGranted
    @State private var testText = ""

    var body: some View {
        VStack(spacing: 20) {
            Image("MenuIcon").resizable().frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(titles[step]).font(.system(size: 22, weight: .bold))
            Text(subtitles[step]).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 380)

            Group {
                switch step {
                case 1:
                    Button(micGranted ? "Microphone granted" : "Allow microphone") {
                        Task { micGranted = await AudioService.requestMicPermission() }
                    }.disabled(micGranted)
                case 2:
                    Button(PasteService.isAccessibilityTrusted ? "Accessibility granted" : "Open Accessibility settings") {
                        PasteService.requestAccessibility()
                    }
                    Text("Optional — without it, transcripts go to your clipboard instead of pasting.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                case 3:
                    switch modelManager.parakeetV2 {
                    case .ready: Label("English model ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .downloading(let p):
                        ProgressView(value: p) { Text("Downloading the English model (~600 MB)…") }
                            .frame(width: 320)
                    case .notDownloaded:
                        Button("Download English model") { Task { await modelManager.downloadParakeet(.v2) } }
                    case .failed(let msg):
                        Text(msg).font(.caption).foregroundStyle(Theme.failure)
                        Button("Retry") { Task { await modelManager.downloadParakeet(.v2) } }
                    }
                case 4:
                    TextField("Click here, press \(model.settings.hotkey.displayString), and speak", text: $testText)
                        .textFieldStyle(.roundedBorder).frame(width: 380)
                default: EmptyView()
                }
            }.frame(minHeight: 70)

            HStack {
                if step > 0 { Button("Back") { step -= 1 } }
                Spacer()
                Button(step == 4 ? "Finish" : "Continue") {
                    if step == 4 {
                        model.settings.hasCompletedOnboarding = true
                        dismiss()
                    } else { step += 1 }
                }
                .buttonStyle(.borderedProminent)
                .disabled(step == 3 && modelManager.parakeetV2 != .ready)
            }.padding(.top, 8)
        }
        .padding(32)
        .frame(width: 520, height: 380)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .onAppear { modelManager.refresh() }
    }

    private let titles = ["Welcome to LocalTalk", "Microphone", "Auto-paste", "Speech model", "Try it"]
    private let subtitles = [
        "Dictation that never leaves your Mac. Four quick steps and you're talking.",
        "LocalTalk needs your microphone to hear you. Audio is processed on this Mac and never uploaded.",
        "Accessibility permission lets LocalTalk type the result straight into whatever app you're using.",
        "The on-device English model is a one-time download. Other languages can be added later in Settings.",
        "Focus the field below, press your hotkey, say something, and press it again.",
    ]
}

enum AVCaptureAuthHelper {
    static var isGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
}
```

(`import AVFoundation` at top alongside SwiftUI.)

- [ ] **Step 2: Show it on first launch** — in `LocalTalkApp` body add a scene:

```swift
        Window("Welcome to LocalTalk", id: "onboarding") {
            OnboardingView(model: appModel, modelManager: AppComposition.modelManager)
        }
        .windowResizability(.contentSize)
```

and open it on first launch from `AppComposition.wire(model:)` using a plain AppKit window (deterministic regardless of scene lifecycle — SwiftUI's `openWindow` isn't reachable from app init):

```swift
        if !model.settings.hasCompletedOnboarding {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                let host = NSHostingController(
                    rootView: OnboardingWindowView(model: model, modelManager: modelManager))
                let window = NSWindow(contentViewController: host)
                window.title = "Welcome to LocalTalk"
                window.styleMask = [.titled, .closable]
                window.center()
                window.isReleasedWhenClosed = false
                onboardingWindow = window                    // static var onboardingWindow: NSWindow?
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
```

```swift
/// Wrapper so `dismiss` works when hosted in a plain NSWindow.
struct OnboardingWindowView: View {
    var model: AppModel
    var modelManager: ModelManager
    var body: some View {
        OnboardingView(model: model, modelManager: modelManager)
            .onChange(of: model.settings.hasCompletedOnboarding) { _, done in
                if done { AppComposition.onboardingWindow?.close() }
            }
    }
}
```

In `OnboardingView`, the Finish button already sets `hasCompletedOnboarding = true`; keep its `dismiss()` call (harmless in the hosted window) — closing happens via the `onChange` above. Delete the separate `Window("Welcome to LocalTalk", id: "onboarding")` scene; the hosted NSWindow replaces it.

- [ ] **Step 3: Build + manual verify + commit**

Manual: `defaults delete com.armageddonvivas.LocalTalk` then launch → onboarding appears, each step works, model download shows progress, test field receives dictated text, Finish → never shows again on relaunch.

```bash
git add LocalTalk/UI/Onboarding LocalTalk/LocalTalkApp.swift
git commit -m "feat: first-launch onboarding with permissions and model download"
```

---

### Task 14: Packaging scripts + legacy cleanup + smoke checklist

**Files:**
- Create: `script/dev_build.sh`, `script/release.sh`, `script/sign_and_notarize.sh`, `script/make_dmg.sh`
- Create: `docs/superpowers/specs/smoke-checklist.md`
- Modify: `README.md`
- Delete: `Package.swift`, `Sources/` (legacy SwiftPM app), `script/build_and_run.sh`
- Keep: `SourcesObjC/main.m` (reference for Phase 2 visual port)

- [ ] **Step 1: Write `script/dev_build.sh`**

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
xcodebuild build -project LocalTalk.xcodeproj -scheme LocalTalk \
  -configuration Debug -destination 'platform=macOS,arch=arm64' -quiet
APP="$(xcodebuild -project LocalTalk.xcodeproj -scheme LocalTalk -configuration Debug \
  -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR/{print $3}')/LocalTalk.app"
pkill -x LocalTalk >/dev/null 2>&1 || true
open "$APP"
echo "Launched $APP"
```

- [ ] **Step 2: Write `script/release.sh`**

```bash
#!/bin/bash
# Requires: Apple Developer Program membership + "Developer ID Application" cert in the keychain.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${TEAM_ID:?Set TEAM_ID=XXXXXXXXXX (your 10-char Apple team id)}"
xcodegen generate
xcodebuild archive -project LocalTalk.xcodeproj -scheme LocalTalk \
  -configuration Release -archivePath build/LocalTalk.xcarchive \
  DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application"
cat > build/export-options.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>${TEAM_ID}</string>
</dict></plist>
EOF
xcodebuild -exportArchive -archivePath build/LocalTalk.xcarchive \
  -exportOptionsPlist build/export-options.plist -exportPath build/export
echo "Exported: build/export/LocalTalk.app"
```

- [ ] **Step 3: Write `script/sign_and_notarize.sh`**

```bash
#!/bin/bash
# One-time setup: xcrun notarytool store-credentials localtalk-notary \
#   --apple-id you@example.com --team-id XXXXXXXXXX --password <app-specific-password>
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/export/LocalTalk.app"
ZIP="build/LocalTalk-notarize.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile localtalk-notary --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
echo "Notarized and stapled."
```

- [ ] **Step 4: Write `script/make_dmg.sh`**

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/export/LocalTalk.app"
VERSION="$(defaults read "$(pwd)/$APP/Contents/Info" CFBundleShortVersionString)"
STAGING="build/dmg-staging"
rm -rf "$STAGING" && mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "LocalTalk" -srcfolder "$STAGING" -ov -format UDZO \
  "build/LocalTalk-${VERSION}.dmg"
echo "Built build/LocalTalk-${VERSION}.dmg"
```

- [ ] **Step 5: Write `docs/superpowers/specs/smoke-checklist.md`**

```markdown
# LocalTalk manual smoke checklist

Run before any release build. All items must pass.

## Core loop
- [ ] Toggle mode: hotkey starts/stops from TextEdit, Notes, Safari URL bar, a web textarea, Slack, Terminal
- [ ] Push-to-talk mode: hold-speak-release works in the same six targets
- [ ] Streaming partial text appears in the HUD while speaking (English)
- [ ] Filipino (Tagalog) dictation transcribes via WhisperKit
- [ ] Translate mode: speak Filipino, English text is inserted

## Honesty & recovery
- [ ] Esc during recording cancels; nothing is pasted or added to history
- [ ] Cancel button during transcription works
- [ ] Recording under 0.4 s → "Too short" message, no history entry
- [ ] With Accessibility revoked → status says clipboard-only with guidance (never claims "Inserted")
- [ ] With mic revoked → readable error pointing at System Settings
- [ ] Clipboard: copy "abc", dictate with copy-to-clipboard OFF into an app needing ⌘V fallback → "abc" restored after
- [ ] Switch apps during a long transcription → text lands in the app you started in

## Environment
- [ ] Fresh user (`defaults delete com.armageddonvivas.LocalTalk`): onboarding flows to a successful test dictation
- [ ] Model download progress shows; killing network mid-download → readable failure + retry
- [ ] Second display: HUD position persists per screen
- [ ] Menu bar icon reflects all four states
- [ ] Quit during recording leaves no orphan process (`pgrep LocalTalk` empty)
- [ ] History survives relaunch; export writes a readable .txt; clear empties it
```

- [ ] **Step 6: Delete legacy code + update README**

```bash
git rm Package.swift script/build_and_run.sh
git rm -r Sources
chmod +x script/*.sh
```

Rewrite `README.md`:

```markdown
# LocalTalk

Private, on-device dictation for macOS. Press a hotkey in any app, speak, and the words appear — nothing ever leaves your Mac.

- Apple Silicon, macOS 14+
- Engines: NVIDIA Parakeet (via FluidAudio) for English/European languages, WhisperKit for everything else including translate-to-English
- The only network traffic is one-time model downloads from Hugging Face

## Develop

```bash
brew install xcodegen
./script/dev_build.sh        # generate project, build, launch
xcodebuild test -project LocalTalk.xcodeproj -scheme LocalTalk -destination 'platform=macOS,arch=arm64'
```

## Release (requires Apple Developer Program)

```bash
TEAM_ID=XXXXXXXXXX ./script/release.sh
./script/sign_and_notarize.sh
./script/make_dmg.sh
```

`SourcesObjC/main.m` is the original prototype, kept as a design reference.

Includes NVIDIA Parakeet, © NVIDIA, CC-BY-4.0.
```

- [ ] **Step 7: Full test suite + smoke checklist run + final commit**

```bash
xcodebuild test -project LocalTalk.xcodeproj -scheme LocalTalk -destination 'platform=macOS,arch=arm64'
```
Expected: `TEST SUCCEEDED`. Then the user runs the smoke checklist top to bottom.

```bash
git add -A
git commit -m "feat: packaging scripts, smoke checklist, legacy SwiftPM app removed"
```

---

## Self-review notes (kept for the executor)

- **Spec coverage:** engines/selector (T4/7/8), streaming partials + HUD + Esc + watchdog + min-duration (T5/11), remappable hotkey + PTT (T9), PasteService honesty + clipboard restore + target capture (T10), history JSONL/search/export (T3/12), settings + models UI (T12), onboarding (T13), icon/Info.plist/entitlements/no-sandbox (T1), signing/notarize/DMG scripts (T14), Parakeet attribution (T12 Settings footer + README). Launch-at-login (`SMAppService`) was in the spec's SettingsStore list — deliberately deferred to Phase 2; it's a two-line addition and not load-bearing.
- **Known soft spots the executor must expect:** (1) exact Swift 6 concurrency annotations may need adjustment when compiling against the real SDKs — the architecture (actors for engines, @MainActor for services/UI) is the contract, individual `@Sendable`/`@preconcurrency` tweaks are fine; (2) `EnvironmentValues().openWindow` in Task 13 has a stated fallback; (3) FluidAudio's `SlidingWindowAsrManager.startStreaming(source:)` may itself capture the mic — if feeding via `streamAudio` conflicts, drop `startStreaming` and check whether `streamAudio` alone suffices (the CLI feeds taps manually); verify against the local package checkout in DerivedData.
- **Versions are pinned** (FluidAudio 0.15.4, argmax-oss-swift 1.0.0) — do not bump mid-plan.



