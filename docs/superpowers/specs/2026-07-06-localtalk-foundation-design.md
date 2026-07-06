# LocalTalk v1.0 Foundation — Design

Date: 2026-07-06
Status: approved by Armageddon (positioning, tech base, shape, scope)

## Product decisions (locked)

- **Positioning:** simple, provably private, local-only macOS dictation. Target price $19–29 one-time purchase (single Mac), competing with VoiceInk ($25) and BetterDictation ($39) rather than Superwhisper.
- **Tech base:** SwiftUI rebuild on the existing `Sources/LocalTalk` skeleton, grown into an Xcode project. The ObjC app (`SourcesObjC/main.m`) becomes a reference implementation only; the Python `openai-whisper` CLI dependency is removed entirely.
- **Shape:** menu-bar-first. No Dock icon by default. One compact resizable main window (History, Settings; onboarding on first launch). The floating dictation HUD is preserved — it is the strongest design asset.
- **This phase:** foundation (engine swap, packaging, permissions, bug-class fixes). Visual redesign details, dictionary, AI cleanup, and licensing are later phases.

## Requirements

- macOS 14.0+, Apple Silicon only (Parakeet requires the Neural Engine; VoiceInk ships the same constraint).
- Fully offline dictation after models are downloaded. No analytics, no telemetry; the only network traffic the app ever produces is model downloads from Hugging Face, and this is documented.
- Core loop: global hotkey → record → stream local transcription → insert text into the app that was focused when recording started → append to history.

## Architecture

One app target, folder-organized modules. `AppModel` (@MainActor observable state machine: `idle → recording → transcribing → inserting → idle`, plus `failed`) coordinates single-purpose services, as the existing SwiftUI code already does.

### TranscriptionEngine protocol

```swift
protocol TranscriptionEngine {
    var id: EngineID { get }                    // .parakeet, .whisperKit
    func prepare(model: ModelDescriptor) async throws
    func transcribe(audio: AsyncStream<AVAudioPCMBuffer>, options: TranscriptionOptions)
        -> AsyncThrowingStream<TranscriptionUpdate, Error>   // .partial(String) / .final(String)
    func cancel()
}
```

- **ParakeetEngine** (FluidAudio, Apache-2.0): default engine. Parakeet v2 for English, v3 for its 25 European languages. ~80 ms streaming latency. Attribution line "Includes NVIDIA Parakeet, © NVIDIA, CC-BY-4.0" in the About screen.
- **WhisperKitEngine** (MIT): multilingual engine covering the full Whisper language set (including Filipino/Tagalog) and the translate-to-English task.
- **Engine selection:** automatic from the language/task setting — English and Parakeet-supported EU languages use Parakeet; all other languages and the translate task use WhisperKit. A Settings override lets the user force an engine. SpeechAnalyzer (macOS 26+) is a planned third conformance, out of scope this phase.

### Services

- **ModelManager** — downloads engine models from Hugging Face into `~/Library/Application Support/LocalTalk/Models`, with visible progress, resume on failure, offline detection, per-model disk usage, and delete. First-run onboarding blocks dictation until the default model is present (fixes the "first run looks hung" failure of the prototype).
- **AudioService** — `AVAudioEngine` input tap producing an `AsyncStream<AVAudioPCMBuffer>` (16 kHz mono) consumed by the engine, plus a published level value for the HUD waveform. Handles input-device removal and permission revocation by returning to `idle` with a message.
- **HotkeyService** — user-remappable global hotkey (Carbon `RegisterEventHotKey`; default ⌃⌥Space). Two modes: **toggle** and **push-to-talk** (record while the combo is held, using the Carbon pressed/released events — no Input Monitoring permission needed). Single-key/Fn push-to-talk is deferred (requires a CGEvent tap). Registration failure is surfaced in the menu and Settings, never silent.
- **PasteService** — captures the frontmost app at **recording start** and re-activates it if needed before insertion (fixes wrong-app paste). Primary path: Accessibility `kAXSelectedTextAttribute` insert. Fallback: synthesized ⌘V with the user's prior clipboard saved and restored afterward. Checks `AXIsProcessTrusted` first and reports honestly: "Inserted", "Pasted via ⌘V", or "Copied to clipboard — grant Accessibility to paste automatically".
- **HistoryStore** — append-only JSON-lines file in Application Support (fields: id, text, date, app name, engine, model, language, duration). Unlimited entries, in-memory search, export to plain text/Markdown, clear-all. Plain text on purpose: this market distrusts opaque databases.
- **SettingsStore** — UserDefaults-backed observable: hotkey, hotkey mode, language, task, engine override, insertion behavior (paste vs clipboard-only), HUD position, sounds, launch at login (`SMAppService`).

### UI

- **Menu bar item** — `MenuBarExtra` (window style): status line, Start/Stop, last transcript snippet with copy, Open LocalTalk, Quit. Icon reflects state (idle/recording/transcribing/error).
- **Main window** — SwiftUI, resizable (min 640×420), sidebar navigation (History, Settings), keeping the current dark identity (near-black surfaces, cyan accent) via forced dark appearance for this phase.
- **Onboarding (first launch)** — welcome → microphone permission → Accessibility permission → default model download with progress → "try dictating here" test field.
- **HUD** — non-activating `NSPanel` (all Spaces, status window level) hosting a SwiftUI view that ports the existing design: gradient shell, waveform bars driven by live levels, LOCAL and language badges, drag-to-reposition with persisted location (validated per-screen, not just main display). New capability: **streaming partial text appears in the HUD while speaking**. States: listening, transcribing, inserted, failed (red), too-short.

## Key flows and error handling

1. **Dictate:** hotkey → HUD appears, levels animate, partial text streams → stop → engine finalizes → insert into captured target app → HUD confirms → history appended → temp audio deleted.
2. **Cancel:** Esc while recording (in either hotkey mode) discards without transcribing. During transcription the HUD shows a Cancel button wired to `engine.cancel()`. A 60-second watchdog ends any stuck transcription with a readable error. Recordings under 0.4 s are discarded as "Too short".
3. **Failures:** every error path lands in a human-readable one-liner (HUD + menu status) with the failed state auto-clearing on the next action. No raw stderr, no silent failure, no success claims that were not verified.

## Packaging and distribution

- Xcode project with asset catalog; compile `Assets/LocalTalk.iconset` into a real `AppIcon.icns` (fixes generic Finder/Dock icon).
- Info.plist: `NSMicrophoneUsageDescription`, `LSUIElement = true`, bundle id `com.armageddonvivas.LocalTalk`, version 1.0.0.
- Hardened runtime + `com.apple.security.device.audio-input` entitlement. No App Sandbox (Accessibility-based insertion is incompatible with it; this is why every competitor ships outside the Mac App Store).
- Scripts: `script/build.sh` (xcodebuild archive/export), `script/sign_and_notarize.sh` (Developer ID + notarytool; activates once enrolled in the Apple Developer Program), `script/make_dmg.sh`.
- Privacy proof posture: no network code outside ModelManager; behavior documented so users can verify with Little Snitch.

## Testing

- Unit tests: HistoryStore (append/search/export), SettingsStore, engine-selection logic, hotkey mapping, clipboard save/restore, and AppModel state transitions driven by a `FakeEngine`.
- Manual smoke checklist at `docs/superpowers/specs/smoke-checklist.md` (created during implementation): dictation into TextEdit, Notes, Safari form, Slack, Terminal; permission-denied paths; model-missing path; cancel paths; multi-display HUD.

## Out of scope (later phases)

Phase 2 (design & UX): full visual polish pass, animations, empty states, dictionary UI. Phase 3 (sell): personal dictionary, local LLM cleanup (Apple Foundation Models), SpeechAnalyzer backend, trial + licensing (Lemon Squeezy/Paddle), landing page, Sparkle auto-update. Also deferred: Intel support, single-modifier-key push-to-talk, and the product rename decision ("LocalTalk" was Apple's 1980s networking protocol — revisit before launch).

## Prerequisites and risks

- **Xcode must be installed** (user action, in progress). Command Line Tools alone cannot build, sign, or notarize.
- Apple Developer Program ($99/yr) is required only for notarized distribution to others — enroll before the first external beta.
- Pin FluidAudio and WhisperKit package versions; both move quickly.
- Swift 6 strict concurrency: keep services explicitly actor-isolated to avoid a class of build friction.
