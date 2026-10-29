import Foundation

/// Maps a text caret onto the character grid. The origin matches `ShapeRaster.place`.
public enum TextCaret {
    public static func location(_ text: String, index: Int) -> (line: Int, column: Int) {
        let clamped = min(max(0, index), text.count)
        var line = 0
        var column = 0
        for (offset, character) in text.enumerated() {
            if offset == clamped { return (line, column) }
            if character == "\n" {
                line += 1
                column = 0
            } else {
                column += 1
            }
        }
        return (line, column)
    }

    public static func index(_ text: String, line: Int, column: Int) -> Int {
        let lines = text.components(separatedBy: "\n")
        let row = min(max(0, line), max(0, lines.count - 1))
        let col = min(max(0, column), lines[row].count)
        var cursor = 0
        for current in 0..<row {
            cursor += lines[current].count + 1
        }
        return cursor + col
    }

    public static func insert(_ text: String, at index: Int, _ insertion: String) -> (text: String, caret: Int) {
        let clamped = min(max(0, index), text.count)
        let at = text.index(text.startIndex, offsetBy: clamped)
        var copy = text
        copy.insert(contentsOf: insertion, at: at)
        return (copy, clamped + insertion.count)
    }

    public static func deleteBackward(_ text: String, at index: Int) -> (text: String, caret: Int) {
        let clamped = min(max(0, index), text.count)
        guard clamped > 0 else { return (text, clamped) }
        let end = text.index(text.startIndex, offsetBy: clamped)
        let start = text.index(before: end)
        var copy = text
        copy.removeSubrange(start..<end)
        return (copy, clamped - 1)
    }

    public static func deleteForward(_ text: String, at index: Int) -> (text: String, caret: Int) {
        let clamped = min(max(0, index), text.count)
        guard clamped < text.count else { return (text, clamped) }
        let start = text.index(text.startIndex, offsetBy: clamped)
        let end = text.index(after: start)
        var copy = text
        copy.removeSubrange(start..<end)
        return (copy, clamped)
    }

    public static func cell(text: String, index: Int, frame: GridRect, props: TextProps) -> GridPoint {
        let lines = text.components(separatedBy: "\n")
        let spot = location(text, index: index)
        let origin = blockOrigin(lines: lines, content: contentRect(frame: frame, props: props), props: props)
        let visualLine = visualLine(spot.line, count: lines.count, sweep: props.sweep)
        let line = lines[min(spot.line, max(0, lines.count - 1))]
        let column = visualColumn(line: line, column: spot.column, lines: lines, alignment: props.alignment)
        return GridPoint(x: origin.x + column, y: origin.y + visualLine)
    }

    public static func index(in text: String, frame: GridRect, props: TextProps, cell: GridPoint) -> Int {
        let lines = text.components(separatedBy: "\n")
        guard !lines.isEmpty else { return 0 }
        let content = contentRect(frame: frame, props: props)
        let origin = blockOrigin(lines: lines, content: content, props: props)
        if cell.y < origin.y {
            let source = props.sweep == .up ? lines.count - 1 : 0
            return index(text, line: source, column: 0)
        }
        if cell.y >= origin.y + lines.count {
            let source = props.sweep == .up ? 0 : lines.count - 1
            return index(text, line: source, column: lines[source].count)
        }
        let visual = cell.y - origin.y
        let source = props.sweep == .up ? lines.count - 1 - visual : visual
        let line = lines[source]
        let pad = leftPad(line: line, lines: lines, alignment: props.alignment)
        let column = min(max(0, cell.x - origin.x - pad), line.count)
        return index(text, line: source, column: column)
    }

    /// Grows from the origin. `minimum` keeps a box the user already sized.
    public static func fittedFrame(text: String, props: TextProps, origin: GridRect, minimum: GridRect?) -> GridRect {
        var measured = props
        measured.text = text
        let rows = TextLayout.rows(for: measured)
        var width = max(1, rows.map(\.count).max() ?? 1)
        var height = max(1, rows.count)
        if props.border != nil {
            width += 2
            height += 2
        }
        if let minimum {
            width = max(width, minimum.width)
            height = max(height, minimum.height)
        }
        return GridRect(x: origin.x, y: origin.y, width: width, height: height)
    }

    private static func contentRect(frame: GridRect, props: TextProps) -> GridRect {
        let bordered = props.border != nil && frame.width >= 2 && frame.height >= 2
        if bordered && props.textInsideBorder {
            let inset = frame.insetBy(1)
            if inset.width > 0, inset.height > 0 { return inset }
        }
        return frame
    }

    private static func blockOrigin(lines: [String], content: GridRect, props: TextProps) -> GridPoint {
        let blockWidth = lines.map(\.count).max() ?? 0
        let blockHeight = max(lines.count, 1)
        let x0: Int
        switch props.lineMovement {
        case .left:
            x0 = content.minX
        case .right:
            x0 = content.maxX - blockWidth
        case .none, .top, .bottom:
            switch props.alignment {
            case .left: x0 = content.minX
            case .right: x0 = content.maxX - blockWidth
            case .center: x0 = content.minX + (content.width - blockWidth) / 2
            }
        }
        let y0: Int
        switch props.lineMovement {
        case .top:
            y0 = content.minY
        case .bottom:
            y0 = content.maxY - blockHeight
        case .none, .left, .right:
            switch props.position {
            case .top: y0 = content.minY
            case .bottom: y0 = content.maxY - blockHeight
            case .middle: y0 = content.minY + (content.height - blockHeight) / 2
            }
        }
        return GridPoint(x: x0, y: y0)
    }

    private static func visualLine(_ source: Int, count: Int, sweep: LineSweep) -> Int {
        guard sweep == .up, count > 0 else { return source }
        return count - 1 - source
    }

    private static func visualColumn(line: String, column: Int, lines: [String], alignment: TextAlignment) -> Int {
        leftPad(line: line, lines: lines, alignment: alignment) + column
    }

    private static func leftPad(line: String, lines: [String], alignment: TextAlignment) -> Int {
        let blockWidth = lines.map(\.count).max() ?? 0
        let extra = max(0, blockWidth - line.count)
        switch alignment {
        case .left: return 0
        case .right: return extra
        case .center: return extra / 2
        }
    }
}
