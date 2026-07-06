#!/bin/bash
# One-time setup:
# xcrun notarytool store-credentials localtalk-notary \
#   --apple-id you@example.com --team-id XXXXXXXXXX --password <app-specific-password>
set -euo pipefail

cd "$(dirname "$0")/.."

APP="build/export/Bulong.app"
ZIP="build/Bulong-notarize.zip"

ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile localtalk-notary --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
echo "Notarized and stapled."
