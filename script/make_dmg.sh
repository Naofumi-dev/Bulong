#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP="build/export/LocalTalk.app"
VERSION="$(defaults read "$(pwd)/$APP/Contents/Info" CFBundleShortVersionString)"
STAGING="build/dmg-staging"

rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "LocalTalk" -srcfolder "$STAGING" -ov -format UDZO \
  "build/LocalTalk-${VERSION}.dmg"
echo "Built build/LocalTalk-${VERSION}.dmg"
