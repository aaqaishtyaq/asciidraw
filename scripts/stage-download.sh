#!/bin/bash
# Build a drag-to-Applications disk image of AsciiDraw.app.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/AsciiDraw.dmg}"
APP="$ROOT/build/AsciiDraw.app"
BACKGROUND="$ROOT/packaging/background.png"

if [[ ! -d "$APP" ]]; then
  echo "Build the app first: scripts/build-app.sh" >&2
  exit 1
fi
if [[ ! -f "$BACKGROUND" ]]; then
  echo "Missing $BACKGROUND" >&2
  exit 1
fi
if [[ ! -x "$APP/Contents/SharedSupport/asciidraw" ]]; then
  echo "The app is missing Contents/SharedSupport/asciidraw." >&2
  exit 1
fi

WORK="$(mktemp -d)"
WORK="$(cd "$WORK" && pwd -P)"
RW="$WORK/rw.dmg"
MOUNTED=""

detach() {
  if [[ -z "$MOUNTED" ]]; then
    return 0
  fi
  local try
  for try in 1 2 3 4 5; do
    if ! mount | grep -F " on ${MOUNTED} " >/dev/null; then
      MOUNTED=""
      return 0
    fi
    hdiutil detach "$MOUNTED" >/dev/null 2>&1 && { MOUNTED=""; return 0; }
    sleep 1
  done
  hdiutil detach "$MOUNTED" -force >/dev/null 2>&1 || diskutil eject force "$MOUNTED" >/dev/null 2>&1 || true
  if mount | grep -F " on ${MOUNTED} " >/dev/null; then
    echo "Could not eject $MOUNTED" >&2
    return 1
  fi
  MOUNTED=""
}

attach() {
  local image="$1"
  shift
  local listing
  listing="$(hdiutil attach "$image" "$@" 2>/dev/null)"
  MOUNTED="$(printf '%s\n' "$listing" | awk '/\/Volumes\// { print $NF; exit }')"
  if [[ -z "$MOUNTED" || ! -d "$MOUNTED" ]]; then
    echo "Could not attach $image" >&2
    printf '%s\n' "$listing" >&2
    exit 1
  fi
}

trap 'detach || true; rm -rf "$WORK"' EXIT

# -type UDIF is a blank read/write image. -format is only valid with a source folder.
hdiutil create -size 80m -fs HFS+ -volname AsciiDraw -type UDIF "$RW" >/dev/null
attach "$RW" -nobrowse

ditto "$APP" "$MOUNTED/AsciiDraw.app"
ln -s /Applications "$MOUNTED/Applications"
mkdir -p "$MOUNTED/.background"
cp "$BACKGROUND" "$MOUNTED/.background/background.png"

# Finder ignores a volume attached with -nobrowse. Reattach so the window
# can open, then put the app on the left and Applications on the right.
detach
attach "$RW"

STYLE="$WORK/style.applescript"
cat > "$STYLE" << 'EOF'
tell application "Finder"
  tell disk "AsciiDraw"
    open
    delay 1
    set theWindow to container window
    set current view of theWindow to icon view
    set toolbar visible of theWindow to false
    set statusbar visible of theWindow to false
    set bounds of theWindow to {200, 120, 840, 500}
    set viewOptions to icon view options of theWindow
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:background.png"
    set position of item "AsciiDraw.app" of theWindow to {150, 175}
    set position of item "Applications" of theWindow to {490, 175}
    update without registering applications
    delay 2
    close
    open
    delay 1
    set theWindow to container window
    set current view of theWindow to icon view
    set toolbar visible of theWindow to false
    set statusbar visible of theWindow to false
    set bounds of theWindow to {200, 120, 840, 500}
    set viewOptions to icon view options of theWindow
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set background picture of viewOptions to file ".background:background.png"
    set position of item "AsciiDraw.app" of theWindow to {150, 175}
    set position of item "Applications" of theWindow to {490, 175}
    update without registering applications
    delay 2
    close
  end tell
end tell
EOF

if ! osascript "$STYLE"; then
  echo "Finder did not save the disk image layout. The image still contains the app and an Applications alias." >&2
fi

sync
detach

rm -f "$OUT"
hdiutil convert -format UDZO -imagekey zlib-level=9 -o "$OUT" "$RW" >/dev/null

attach "$OUT" -nobrowse
if [[ ! -d "$MOUNTED/AsciiDraw.app" ]]; then
  echo "The disk image is missing AsciiDraw.app." >&2
  exit 1
fi
if [[ "$(readlink "$MOUNTED/Applications")" != "/Applications" ]]; then
  echo "The disk image is missing the Applications alias." >&2
  exit 1
fi
echo "Built $OUT"
