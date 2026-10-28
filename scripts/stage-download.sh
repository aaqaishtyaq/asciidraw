#!/bin/bash
# Zip AsciiDraw.app and the asciidraw command for the GitHub release.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/AsciiDraw.zip}"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

ditto "$ROOT/build/AsciiDraw.app" "$STAGE/AsciiDraw.app"
cp "$ROOT/build/asciidraw" "$STAGE/asciidraw"
chmod +x "$STAGE/asciidraw"
cat > "$STAGE/README.txt" << 'EOF'
AsciiDraw for macOS 26 or later (Apple silicon).

This build is ad-hoc signed and not notarized.
Move AsciiDraw.app to /Applications, then right-click it and choose Open the first time.

If macOS says the app is damaged, clear the download quarantine:

  xattr -dr com.apple.quarantine /Applications/AsciiDraw.app

The asciidraw command prints a saved .asciidraw document:

  asciidraw Diagram.asciidraw
  asciidraw --json Diagram.asciidraw

Put that binary somewhere on your PATH.
EOF

rm -f "$OUT"
ditto -c -k --norsrc "$STAGE" "$OUT"
unzip -l "$OUT"
