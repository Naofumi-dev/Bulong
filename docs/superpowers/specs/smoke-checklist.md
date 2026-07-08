# Bulong manual smoke checklist

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

- [ ] Fresh user (`defaults delete com.armageddonvivas.Bulong`): onboarding completes end-to-end to a successful test dictation
- [ ] Old LocalTalk data (history + settings) migrated on first Bulong launch; onboarding does not reappear
- [ ] Model download progress shows; killing network mid-download gives a readable failure and retry
- [ ] Second display: HUD position persists per screen
- [ ] Menu bar icon reflects idle, recording, transcribing, inserting, and failed states
- [ ] Quit during recording leaves no orphan process (`pgrep Bulong` empty)
- [ ] History survives relaunch; export writes a readable `.txt`; clear empties it

## Popover

- [ ] Popover opens/dismisses cleanly and every action works (start/stop, copy last transcript, History, Settings, Quit)
- [ ] Popover: opening History/Settings lands on the right pane and popover dismisses
- [ ] Start dictation from the popover → text pastes into the previously focused app

## Main Window

- [ ] History: hover lifts a card and reveals Copy; Copy shows "Copied ✓"; clearing shows the designed empty state
- [ ] Settings: permission hints react live after granting mic/Accessibility (no relaunch)

## Living HUD (requires live mouse + app inactive)

- [ ] Trigger dictation via hotkey from another app; hover the pill → cancel appears; click it → dictation cancels without activating Bulong
- [ ] Drag the pill smoothly (no jitter/jumping), release; position persists; next dictation appears there
- [ ] Push-to-talk: start drag, release the hotkey mid-drag → no jump on the next drag
- [ ] HUD position presets (bottom center / top right / below the notch) apply on every connected display

## Single-key trigger (Right Option) (requires live keyboard)

- [ ] Settings → Hotkey → Trigger → Right Option; with Accessibility granted the caption reads "Tap Right ⌥ to toggle · hold to talk" (no grant note)
- [ ] Tap Right ⌥ in TextEdit → HUD appears and stays (toggle armed); tap again → transcribes + pastes
- [ ] Hold Right ⌥ → records while held; release → transcribes (push-to-talk)
- [ ] Left ⌥ does nothing; Right ⌥ used inside another shortcut doesn't trigger dictation and still reaches the other app
- [ ] Switch Trigger back to Key combo → ⌃⌥Space works again, Right ⌥ inert
- [ ] Start a toggle session, press Esc → cancels; next Right ⌥ tap starts fresh (reset worked)
