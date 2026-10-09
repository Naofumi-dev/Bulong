# Install Bulong (unsigned friend build)

Requirements: a Mac with Apple Silicon (M1 or newer) running macOS 14 or later.

This build is not notarized by Apple, so macOS will warn you the first time you open it. That is expected.

## Steps

1. Download `downloads/Bulong-1.0.0.dmg` from this repo (open the file on GitHub, then click **Download raw file**).
2. Double-click the DMG and drag **Bulong** onto **Applications**.
3. Open **Applications**, **right-click Bulong, choose Open**, then click **Open** in the dialog.
   - If macOS only offers "Move to Trash": go to **System Settings -> Privacy & Security**, scroll down, click **Open Anyway** next to Bulong, and confirm.
   - Or run this once in Terminal, then open Bulong normally:
     ```bash
     xattr -dr com.apple.quarantine /Applications/Bulong.app
     ```
4. When prompted, allow **Microphone** and **Accessibility** access (System Settings -> Privacy & Security). Bulong needs both to hear you and paste text.
5. Follow the onboarding to download a speech model, then press the hotkey and talk.

## Troubleshooting

- **Hotkey or paste does nothing:** re-check Accessibility in Privacy & Security; toggle Bulong off and on.
- **Permissions reset after an update:** this build is ad-hoc signed, so macOS treats each new build as a new app. Re-grant the permissions.
- **Intel Mac:** not supported.

SHA-256 of the DMG: `b7fdf29ab6781f2c9986d09adb18c0f5b437453f96e60bc454328f97a5f9a92e`
