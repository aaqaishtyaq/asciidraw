#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# One product per invocation. Repeating --product keeps only the last one,
# and on a case-insensitive volume AsciiDrawApp and asciidraw are one file.
# Copy each binary out before the next link.
mkdir -p "$ROOT/build"
BIN_DIR=""
copy_product() {
  local product="$1"
  local dest="$2"
  swift build -c release --product "$product"
  BIN_DIR="$(swift build -c release --product "$product" --show-bin-path)"
  cp "$BIN_DIR/$product" "$dest"
  chmod +x "$dest"
}
# Destination names differ by more than case. build/ is case-insensitive,
# so AsciiDraw.bin and asciidraw.bin would be one file.
copy_product AsciiDrawApp "$ROOT/build/app-binary"
copy_product asciidraw-mcp "$ROOT/build/mcp-binary"
copy_product asciidraw "$ROOT/build/cli-binary"
if cmp -s "$ROOT/build/app-binary" "$ROOT/build/cli-binary"; then
  echo "The app and the asciidraw command came out as the same binary." >&2
  exit 1
fi
APP="$ROOT/build/AsciiDraw.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts" "$APP/Contents/SharedSupport"
cp "$ROOT/build/app-binary" "$APP/Contents/MacOS/AsciiDraw"
cp "$ROOT/build/mcp-binary" "$APP/Contents/MacOS/asciidraw-mcp"
# SharedSupport, not MacOS. On a case-insensitive volume the name asciidraw
# would replace the AsciiDraw executable if both lived in Contents/MacOS.
cp "$ROOT/build/cli-binary" "$APP/Contents/SharedSupport/asciidraw"
cp "$ROOT/build/cli-binary" "$ROOT/build/asciidraw"
rm -f "$ROOT/build/app-binary" "$ROOT/build/mcp-binary" "$ROOT/build/cli-binary"
chmod +x "$APP/Contents/MacOS/AsciiDraw" "$APP/Contents/MacOS/asciidraw-mcp" \
  "$APP/Contents/SharedSupport/asciidraw" "$ROOT/build/asciidraw"
cp "$ROOT/App/Info.plist" "$APP/Contents/Info.plist"
VERSION="$(sed -n 's/^[[:space:]]*public static let semantic = "\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)".*/\1/p' "$ROOT/Sources/AsciiDrawCore/Version.swift")"
if [[ -z "$VERSION" ]]; then
  echo "Could not read the semantic version." >&2
  exit 1
fi
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
cp "$ROOT/App/AsciiDraw.icns" "$APP/Contents/Resources/AsciiDraw.icns"
cp "$ROOT/Fonts/"*.flf "$APP/Contents/Resources/Fonts/"
codesign --force --sign - "$APP/Contents/SharedSupport/asciidraw"
codesign --force --sign - "$ROOT/build/asciidraw"
codesign --force --sign - "$APP"
echo "Built $APP"
echo "Built $ROOT/build/asciidraw"
