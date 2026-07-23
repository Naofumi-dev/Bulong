#!/bin/bash
# Builds Debug and runs the app from a SINGLE canonical location (/Applications).
#
# Why not `open` the DerivedData build directly: every build has a different
# ad-hoc code hash, and macOS keys Accessibility/Microphone (TCC) grants to that
# hash. Leaving multiple registered Bulong.app copies (DerivedData + /Applications
# + build artifacts) makes macOS bind grants to whichever copy it resolves, so a
# freshly-built binary reads as "not trusted" even though Settings shows the app
# enabled. Installing to one place keeps exactly one registration.
#
# Permissions still reset on each build (ad-hoc signing = new hash). That churn
# only exists for local dev; a Developer ID-signed release (see script/release.sh)
# pins TCC to a stable identity that survives every update. If a build ever reads
# as untrusted, run: script/fix_permissions.sh
set -euo pipefail

cd "$(dirname "$0")/.."

xcodegen generate
xcodebuild build -project Bulong.xcodeproj -scheme Bulong \
  -configuration Debug -destination 'platform=macOS,arch=arm64' -quiet

BUILT="$(xcodebuild -project Bulong.xcodeproj -scheme Bulong -configuration Debug \
  -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR = / {print $3}' | tail -n 1)/Bulong.app"
DEST="/Applications/Bulong.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

osascript -e 'tell application "Bulong" to quit' >/dev/null 2>&1 || true
for pid in $(pgrep -x Bulong 2>/dev/null || true); do kill "$pid" >/dev/null 2>&1 || true; done
sleep 1

# Drop stale registrations of any other Bulong copy so only /Applications wins.
"$LSREGISTER" -u "$BUILT" >/dev/null 2>&1 || true

rm -rf "$DEST"
ditto "$BUILT" "$DEST"
# Delete the DerivedData product after installing: Spotlight indexes it and
# users end up seeing two or three "Bulong" apps in search. One copy on disk.
rm -rf "$BUILT"
"$LSREGISTER" -f "$DEST"

open "$DEST"
echo "Installed and launched $DEST"
