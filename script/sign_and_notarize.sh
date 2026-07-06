#!/bin/bash
# One-time setup:
# xcrun notarytool store-credentials localtalk-notary \
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
