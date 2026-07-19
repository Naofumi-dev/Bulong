#!/bin/bash
# Repairs the "I granted Accessibility but Bulong still says it's not granted"
# problem that ad-hoc-signed local dev builds hit.
#
# Root cause: multiple Bulong.app copies on disk (DerivedData Debug+Release,
# build artifacts, /Applications) all share the bundle id but have different
# code hashes. macOS binds the TCC (Accessibility/Microphone) grant to whichever
# copy it resolves, so the running /Applications binary can read as untrusted
# even though "Bulong" is toggled ON in System Settings.
#
# This script removes every stray registration, clears the stale grants, and
# leaves you to grant once on the clean /Applications binary. Grants then stick
# until the next rebuild (or forever, once you ship a Developer ID-signed build).
#
# Usage: script/fix_permissions.sh
set -euo pipefail

BUNDLE_ID="com.armageddonvivas.Bulong"
OLD_BUNDLE_ID="com.armageddonvivas.LocalTalk"   # pre-rename app, if still around
DEST="/Applications/Bulong.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

echo "==> Quitting Bulong"
osascript -e 'tell application "Bulong" to quit' >/dev/null 2>&1 || true
for pid in $(pgrep -x Bulong 2>/dev/null || true); do kill "$pid" >/dev/null 2>&1 || true; done
sleep 1

echo "==> Unregistering stray Bulong/LocalTalk copies (keeping $DEST)"
# DerivedData build products
find "$HOME/Library/Developer/Xcode/DerivedData" -maxdepth 5 \
  \( -name "Bulong.app" -o -name "LocalTalk.app" \) -path "*Products*" 2>/dev/null | while read -r app; do
  "$LSREGISTER" -u "$app" >/dev/null 2>&1 && echo "    unregistered: $app"
done
# In-repo build artifacts
find "$(cd "$(dirname "$0")/.." && pwd)/build" -maxdepth 6 -name "Bulong.app" 2>/dev/null | while read -r app; do
  [ "$app" != "$DEST" ] && "$LSREGISTER" -u "$app" >/dev/null 2>&1 && echo "    unregistered: $app"
done

if [ ! -d "$DEST" ]; then
  echo "!! $DEST not found — run script/dev_build.sh first, then re-run this."
  exit 1
fi
"$LSREGISTER" -f "$DEST"

echo "==> Clearing stale TCC grants"
tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
tccutil reset Microphone "$BUNDLE_ID" >/dev/null 2>&1 || true
tccutil reset Accessibility "$OLD_BUNDLE_ID" >/dev/null 2>&1 || true

echo "==> Re-arming first-run permission prompts"
defaults write "$BUNDLE_ID" hasCompletedOnboarding -bool false

echo
echo "Done. Now:"
echo "  1) open $DEST"
echo "  2) In the Welcome window: Continue -> grant Microphone (Allow) and"
echo "     Accessibility (Grant -> Allow) -> finish."
echo "  3) Quit and reopen Bulong once so it re-reads the grant."
echo
echo "Only ONE Bulong is registered now, so the grant binds to it and sticks."
