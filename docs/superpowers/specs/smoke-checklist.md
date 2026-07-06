# LocalTalk manual smoke checklist

Run before any release build. All items must pass.

## Core Loop

- [ ] Toggle mode: hotkey starts and stops from TextEdit, Notes, Safari URL bar, a web textarea, Slack, Terminal
- [ ] Push-to-talk mode: hold, speak, release works in the same six targets
- [ ] Streaming partial text appears in the HUD while speaking English
- [ ] Filipino (Tagalog) dictation transcribes via WhisperKit
- [ ] Translate mode: speak Filipino, English text is inserted

## Honesty And Recovery

- [ ] Esc during recording cancels; nothing is pasted or added to history
- [ ] Cancel button during transcription works
- [ ] Recording under 0.4 s shows "Too short" and creates no history entry
- [ ] With Accessibility revoked, status says clipboard-only with guidance and never claims "Inserted"
- [ ] With mic revoked, status shows a readable error pointing at System Settings
- [ ] Clipboard: copy "abc", dictate with copy-to-clipboard off into an app needing Cmd-V fallback, then "abc" is restored
- [ ] Switch apps during a long transcription; text lands in the app you started in

## Environment

- [ ] Fresh user (`defaults delete com.armageddonvivas.LocalTalk`): onboarding flows to a successful test dictation
- [ ] Model download progress shows; killing network mid-download gives a readable failure and retry
- [ ] Second display: HUD position persists per screen
- [ ] Menu bar icon reflects idle, recording, transcribing, inserting, and failed states
- [ ] Quit during recording leaves no orphan process (`pgrep LocalTalk` empty)
- [ ] History survives relaunch; export writes a readable `.txt`; clear empties it
