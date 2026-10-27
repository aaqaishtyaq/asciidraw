# AsciiDraw

Native macOS diagram editor for monospaced character art. Shapes live on a free character canvas and render to one grid: rectangles, diamonds, text, lines, and FIGlet banners.

## Build

```sh
swift test
scripts/build-app.sh
open build/AsciiDraw.app
```

The `asciidraw` command prints a saved document or writes recoverable JSON:

```sh
asciidraw Diagram.asciidraw
asciidraw --json Diagram.asciidraw
```

Documents are JSON files with the extension `.asciidraw`.

## Tools

Keys select a tool with no modifier. Space pans and restores the previous tool.

| Key | Tool |
| --- | --- |
| V | Select |
| R | Rectangle |
| D | Diamond |
| T | Text |
| L | Line |
| P | Pencil |
| E | Eraser |
| B | Bucket |
| K | Picker |
| A | Banner |
| H | Pan |

Rectangles have single or double borders, a fill, and a shadow. Lines can be orthogonal or staircase, dashed, and finished with an arrow or one of three Crow’s foot ends. Drag a line endpoint onto a rectangle border to attach it. Option-click a border to drop a point the line can stick to.
