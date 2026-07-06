#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

xcodegen generate
xcodebuild build -project Bulong.xcodeproj -scheme Bulong \
  -configuration Debug -destination 'platform=macOS,arch=arm64' -quiet

APP="$(xcodebuild -project Bulong.xcodeproj -scheme Bulong -configuration Debug \
  -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR = / {print $3}' | tail -n 1)/Bulong.app"
BINARY="$APP/Contents/MacOS/Bulong"

for pid in $(pgrep -x Bulong 2>/dev/null || true); do
  command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
  case "$command" in
    "$BINARY"*) kill "$pid" >/dev/null 2>&1 || true ;;
  esac
done

open "$APP"
echo "Launched $APP"
