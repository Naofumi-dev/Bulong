# LocalTalk

Private, on-device dictation for macOS. Press a hotkey in any app, speak, and the words appear. Nothing leaves your Mac.

- Apple Silicon, macOS 14+
- Engines: NVIDIA Parakeet through FluidAudio for English and supported European languages; WhisperKit for everything else, including translate-to-English
- Filipino (Tagalog) support routes through WhisperKit
- The only network traffic is one-time model downloads from Hugging Face
- No telemetry, no cloud transcription, no API key

## Develop

```bash
brew install xcodegen
./script/dev_build.sh
xcodebuild test -project LocalTalk.xcodeproj -scheme LocalTalk -destination 'platform=macOS,arch=arm64'
```

## Release

Requires Apple Developer Program membership and a Developer ID Application certificate.

```bash
TEAM_ID=XXXXXXXXXX ./script/release.sh
./script/sign_and_notarize.sh
./script/make_dmg.sh
```

Run the manual release checks in `docs/superpowers/specs/smoke-checklist.md` before shipping.

`SourcesObjC/main.m` is the original prototype, kept as a design reference for the Phase 2 visual pass.

Includes NVIDIA Parakeet, © NVIDIA, CC-BY-4.0.
