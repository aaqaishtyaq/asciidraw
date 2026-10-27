#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build -c release --product AsciiDrawApp
BIN_DIR="$(swift build -c release --product AsciiDrawApp --show-bin-path)"
APP="$ROOT/build/AsciiDraw.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts"
cp "$BIN_DIR/AsciiDrawApp" "$APP/Contents/MacOS/AsciiDraw"
chmod +x "$APP/Contents/MacOS/AsciiDraw"
cp "$ROOT/App/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Fonts/"*.flf "$APP/Contents/Resources/Fonts/"
codesign --force --sign - "$APP"
echo "Built $APP"
