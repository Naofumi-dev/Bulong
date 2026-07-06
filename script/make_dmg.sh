#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP="build/export/Bulong.app"
VERSION="$(defaults read "$(pwd)/$APP/Contents/Info" CFBundleShortVersionString)"
STAGING="build/dmg-staging"

rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Bulong" -srcfolder "$STAGING" -ov -format UDZO \
  "build/Bulong-${VERSION}.dmg"
echo "Built build/Bulong-${VERSION}.dmg"
