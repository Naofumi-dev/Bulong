#!/bin/bash
# Requires: Apple Developer Program membership and a Developer ID Application cert in the keychain.
set -euo pipefail

cd "$(dirname "$0")/.."

: "${TEAM_ID:?Set TEAM_ID=XXXXXXXXXX (your 10-char Apple team id)}"

mkdir -p build
xcodegen generate
xcodebuild archive -project Bulong.xcodeproj -scheme Bulong \
  -configuration Release -archivePath build/Bulong.xcarchive \
  DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application"

cat > build/export-options.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>${TEAM_ID}</string>
</dict></plist>
EOF

xcodebuild -exportArchive -archivePath build/Bulong.xcarchive \
  -exportOptionsPlist build/export-options.plist -exportPath build/export
echo "Exported: build/export/Bulong.app"
