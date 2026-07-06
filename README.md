# LocalTalk

LocalTalk is a local-only macOS dictation prototype for private voice input.

- A native desktop window opens with Home, Dictation, Hotkeys, and Preferences sections.
- `Control+Option+Space` toggles recording from anywhere.
- A small floating dictation bar appears while recording and transcribing.
- Audio is recorded as a temporary WAV file on this Mac.
- Transcription runs through the local `whisper` executable.
- Results are copied to the clipboard and can be pasted automatically after Accessibility permission is granted.
- Recent transcripts are stored locally in macOS user defaults for quick review.

## Run

```bash
./script/build_and_run.sh
```

The app bundle is staged at `dist/LocalTalk.app`.

This build uses Objective-C/AppKit because the Command Line Tools on this Mac
currently fail to import Swift Foundation modules. A SwiftUI version is also
present in `Sources/LocalTalk`, but the working app path is `SourcesObjC/main.m`.

## Local AI Notes

This version uses the installed OpenAI Whisper command-line tool. The first time a model is used, Whisper may download that model into its local cache. After that, inference is local and no API key is used.

For translation into English, choose a multilingual model such as `small` or `medium`. English-only models like `base.en` are best for English transcription.

## MVP Limits

This prototype focuses on the core personal workflow: hotkey dictation, local transcription, paste into the focused app, and a polished settings shell. Single-key push-to-talk, custom dictionaries, snippets, account features, background audio ducking, packaging, signing, and auto-updates are intentionally left for the next product pass.
