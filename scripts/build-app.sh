#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build -c release --product AsciiDrawApp --product asciidraw-mcp --product asciidraw
BIN_DIR="$(swift build -c release --product AsciiDrawApp --show-bin-path)"
APP="$ROOT/build/AsciiDraw.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts" "$ROOT/build"
cp "$BIN_DIR/AsciiDrawApp" "$APP/Contents/MacOS/AsciiDraw"
cp "$BIN_DIR/asciidraw-mcp" "$APP/Contents/MacOS/asciidraw-mcp"
# The CLI stays beside the app. On a case-insensitive volume its name
# would collide with Contents/MacOS/AsciiDraw.
cp "$BIN_DIR/asciidraw" "$ROOT/build/asciidraw"
chmod +x "$APP/Contents/MacOS/AsciiDraw" "$APP/Contents/MacOS/asciidraw-mcp" "$ROOT/build/asciidraw"
cp "$ROOT/App/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/App/AsciiDraw.icns" "$APP/Contents/Resources/AsciiDraw.icns"
cp "$ROOT/Fonts/"*.flf "$APP/Contents/Resources/Fonts/"
codesign --force --sign - "$ROOT/build/asciidraw"
codesign --force --sign - "$APP"
echo "Built $APP"
echo "Built $ROOT/build/asciidraw"
