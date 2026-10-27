import Foundation

enum ShapeRaster {
    static func cells(for object: DrawObject) -> [GridPoint: Character] {
        switch object.kind {
        case .rectangle(let props):
            return rectangle(frame: object.frame, props: props)
        case .diamond:
            return diamond(frame: object.frame)
        case .text(let props):
            return text(frame: object.frame, props: props)
        case .line(let props):
            return lineCells(props)
        case .banner(let props):
            return banner(frame: object.frame, props: props)
        }
    }

    static func rectangle(frame: GridRect, props: RectangleProps) -> [GridPoint: Character] {
        guard frame.width >= 1, frame.height >= 1 else { return [:] }
        var cells: [GridPoint: Character] = [:]
        if let fill = props.fillGlyph {
            for y in frame.minY..<frame.maxY {
                for x in frame.minX..<frame.maxX {
                    cells[GridPoint(x: x, y: y)] = fill
                }
            }
        }
        if let border = props.border, frame.width >= 2, frame.height >= 2 {
            paintBorder(frame: frame, style: border, into: &cells)
        }
        if let shadow = props.shadow, let glyph = shadow.glyph {
            for y in frame.minY..<frame.maxY {
                for x in frame.minX..<frame.maxX {
                    let destination = GridPoint(x: x + shadow.dx, y: y + shadow.dy)
                    if frame.contains(destination) { continue }
                    if cells[destination] == nil {
                        cells[destination] = glyph
                    }
                }
            }
        }
        return cells
    }

    static func paintBorder(frame: GridRect, style: BorderStyle, into cells: inout [GridPoint: Character]) {
        let glyphs = BoxDrawing.glyphs(for: style)
        let maxX = frame.maxX - 1
        let maxY = frame.maxY - 1
        for x in frame.minX...maxX {
            let horizontal = (x == frame.minX || x == maxX) ? nil : glyphs.horizontal
            if x == frame.minX {
                cells[GridPoint(x: x, y: frame.minY)] = glyphs.topLeft
                cells[GridPoint(x: x, y: maxY)] = glyphs.bottomLeft
            } else if x == maxX {
                cells[GridPoint(x: x, y: frame.minY)] = glyphs.topRight
                cells[GridPoint(x: x, y: maxY)] = glyphs.bottomRight
            } else if let horizontal {
                cells[GridPoint(x: x, y: frame.minY)] = horizontal
                cells[GridPoint(x: x, y: maxY)] = horizontal
            }
        }
        if frame.height > 2 {
            for y in (frame.minY + 1)..<maxY {
                cells[GridPoint(x: frame.minX, y: y)] = glyphs.vertical
                cells[GridPoint(x: maxX, y: y)] = glyphs.vertical
            }
        }
    }

    static func diamond(frame: GridRect) -> [GridPoint: Character] {
        guard frame.width >= 3, frame.height >= 3 else {
            return [GridPoint(x: frame.minX, y: frame.minY): "+"]
        }
        let top = GridPoint(x: frame.minX + (frame.width - 1) / 2, y: frame.minY)
        let bottom = GridPoint(x: frame.minX + (frame.width - 1) / 2, y: frame.maxY - 1)
        let left = GridPoint(x: frame.minX, y: frame.minY + (frame.height - 1) / 2)
        let right = GridPoint(x: frame.maxX - 1, y: frame.minY + (frame.height - 1) / 2)
        var cells: [GridPoint: Character] = [:]
        func plot(_ start: GridPoint, _ end: GridPoint, _ character: Character) {
            for point in bresenham(start, end) {
                cells[point] = character
            }
        }
        plot(top, right, "\\")
        plot(right, bottom, "/")
        plot(bottom, left, "\\")
        plot(left, top, "/")
        cells[top] = "+"
        cells[right] = "+"
        cells[bottom] = "+"
        cells[left] = "+"
        return cells
    }

    static func text(frame: GridRect, props: TextProps) -> [GridPoint: Character] {
        var cells: [GridPoint: Character] = [:]
        var content = frame
        if let border = props.border, frame.width >= 2, frame.height >= 2 {
            paintBorder(frame: frame, style: border, into: &cells)
            content = frame.insetBy(1)
        }
        guard content.width > 0, content.height > 0 else { return cells }
        let rows = textRows(props.text, sweep: props.sweep, alignment: props.alignment)
        place(rows: rows, in: content, alignment: props.alignment, position: props.position, movement: props.lineMovement, into: &cells)
        return cells
    }

    static func banner(frame: GridRect, props: BannerProps) -> [GridPoint: Character] {
        let font: FigletFont?
        if let custom = props.customFLF, let data = custom.data(using: .utf8) {
            font = try? FigletFont.load(data: data, name: props.fontName)
        } else {
            font = try? FigletFont.bundled(props.fontName)
        }
        let rows = font?.render(props.text) ?? props.text.components(separatedBy: "\n")
        var cells: [GridPoint: Character] = [:]
        place(rows: rows, in: frame, alignment: props.alignment, position: props.position, movement: .none, into: &cells)
        return cells
    }

    static func lineCells(_ props: LineProps) -> [GridPoint: Character] {
        let path = route(props)
        var glyphs = props.routing == .staircase ? staircaseGlyphs(path) : orthogonalGlyphs(path)
        glyphs = applyDash(glyphs, path: path, dash: props.dash)
        applyCap(props.startCap, path: path, atEnd: false, into: &glyphs)
        applyCap(props.endCap, path: path, atEnd: true, into: &glyphs)
        return glyphs
    }

    static func route(_ props: LineProps) -> [GridPoint] {
        switch props.routing {
        case .orthogonal:
            return orthogonalPath(from: props.start, to: props.end, horizontalFirst: props.horizontalFirst)
        case .staircase:
            return bresenham(props.start, props.end)
        }
    }

    static func orthogonalPath(from start: GridPoint, to end: GridPoint, horizontalFirst: Bool) -> [GridPoint] {
        if start == end { return [start] }
        var points = [start]
        func walkX(from x0: Int, to x1: Int, y: Int) {
            if x0 == x1 { return }
            let step = x0 < x1 ? 1 : -1
            var x = x0
            while x != x1 {
                x += step
                points.append(GridPoint(x: x, y: y))
            }
        }
        func walkY(from y0: Int, to y1: Int, x: Int) {
            if y0 == y1 { return }
            let step = y0 < y1 ? 1 : -1
            var y = y0
            while y != y1 {
                y += step
                points.append(GridPoint(x: x, y: y))
            }
        }
        if horizontalFirst {
            walkX(from: start.x, to: end.x, y: start.y)
            walkY(from: start.y, to: end.y, x: end.x)
        } else {
            walkY(from: start.y, to: end.y, x: start.x)
            walkX(from: start.x, to: end.x, y: end.y)
        }
        return points
    }

    static func bresenham(_ start: GridPoint, _ end: GridPoint) -> [GridPoint] {
        var points: [GridPoint] = []
        var x = start.x
        var y = start.y
        let dx = abs(end.x - start.x)
        let dy = abs(end.y - start.y)
        let sx = start.x < end.x ? 1 : -1
        let sy = start.y < end.y ? 1 : -1
        var error = dx - dy
        while true {
            points.append(GridPoint(x: x, y: y))
            if x == end.x && y == end.y { break }
            let doubled = 2 * error
            if doubled > -dy {
                error -= dy
                x += sx
            }
            if doubled < dx {
                error += dx
                y += sy
            }
        }
        return points
    }

    static func orthogonalGlyphs(_ points: [GridPoint]) -> [GridPoint: Character] {
        var result: [GridPoint: Character] = [:]
        for index in points.indices {
            let point = points[index]
            var north = false, east = false, south = false, west = false
            func mark(_ other: GridPoint) {
                if other.x == point.x && other.y < point.y { north = true }
                if other.x == point.x && other.y > point.y { south = true }
                if other.y == point.y && other.x > point.x { east = true }
                if other.y == point.y && other.x < point.x { west = true }
            }
            if index > 0 { mark(points[index - 1]) }
            if index + 1 < points.count { mark(points[index + 1]) }
            result[point] = BoxDrawing.lightGlyph(north: north, east: east, south: south, west: west)
        }
        return result
    }

    static func staircaseGlyphs(_ points: [GridPoint]) -> [GridPoint: Character] {
        var result: [GridPoint: Character] = [:]
        if points.count == 1 {
            result[points[0]] = "+"
            return result
        }
        for index in points.indices {
            let dx: Int
            let dy: Int
            if index > 0 && index + 1 < points.count {
                dx = points[index + 1].x - points[index - 1].x
                dy = points[index + 1].y - points[index - 1].y
            } else if index + 1 < points.count {
                dx = points[index + 1].x - points[index].x
                dy = points[index + 1].y - points[index].y
            } else {
                dx = points[index].x - points[index - 1].x
                dy = points[index].y - points[index - 1].y
            }
            result[points[index]] = stairCharacter(dx: dx, dy: dy)
        }
        return result
    }

    static func stairCharacter(dx: Int, dy: Int) -> Character {
        if dx != 0 && dy != 0 {
            let sameSign = (dx > 0 && dy > 0) || (dx < 0 && dy < 0)
            return sameSign ? "\\" : "/"
        }
        if dx != 0 { return "─" }
        if dy != 0 { return "│" }
        return "+"
    }

    static func applyDash(_ cells: [GridPoint: Character], path: [GridPoint], dash: DashPattern) -> [GridPoint: Character] {
        guard dash.off > 0 else { return cells }
        let period = dash.on + dash.off
        var kept: [GridPoint: Character] = [:]
        for (index, point) in path.enumerated() where index % period < dash.on {
            if let character = cells[point] {
                kept[point] = character
            }
        }
        return kept
    }

    static func applyCap(_ cap: LineCap, path: [GridPoint], atEnd: Bool, into cells: inout [GridPoint: Character]) {
        guard path.count >= 2, cap != .none else { return }
        let point = atEnd ? path[path.count - 1] : path[0]
        let before = atEnd ? path[path.count - 2] : path[1]
        let rawDX = point.x - before.x
        let rawDY = point.y - before.y
        let direction = dominant(dx: rawDX, dy: rawDY)
        switch cap {
        case .none:
            break
        case .arrow:
            cells[point] = arrow(direction)
        case .crowsFoot(let style):
            for (offset, character) in crowsFoot(style, direction: direction) {
                cells[GridPoint(x: point.x + offset.x, y: point.y + offset.y)] = character
            }
        }
    }

    static func dominant(dx: Int, dy: Int) -> GridPoint {
        if abs(dx) >= abs(dy) {
            return GridPoint(x: dx == 0 ? 1 : (dx > 0 ? 1 : -1), y: 0)
        }
        return GridPoint(x: 0, y: dy >= 0 ? 1 : -1)
    }

    static func arrow(_ direction: GridPoint) -> Character {
        switch (direction.x, direction.y) {
        case (1, _): return ">"
        case (-1, _): return "<"
        case (_, 1): return "v"
        default: return "^"
        }
    }

    /// Crow's foot opens toward `direction`. The bar or circle sits on the line, one cell before the toes.
    static func crowsFoot(_ style: CrowsFootStyle, direction: GridPoint) -> [(GridPoint, Character)] {
        let toes: [(GridPoint, Character)]
        let back = GridPoint(x: -direction.x, y: -direction.y)
        switch (direction.x, direction.y) {
        case (1, 0):
            toes = [
                (GridPoint(x: 0, y: -1), "┐"),
                (GridPoint(x: 0, y: 0), "┤"),
                (GridPoint(x: 0, y: 1), "┘"),
            ]
        case (-1, 0):
            toes = [
                (GridPoint(x: 0, y: -1), "┌"),
                (GridPoint(x: 0, y: 0), "├"),
                (GridPoint(x: 0, y: 1), "└"),
            ]
        case (0, 1):
            toes = [
                (GridPoint(x: -1, y: 0), "└"),
                (GridPoint(x: 0, y: 0), "┴"),
                (GridPoint(x: 1, y: 0), "┘"),
            ]
        default:
            toes = [
                (GridPoint(x: -1, y: 0), "┌"),
                (GridPoint(x: 0, y: 0), "┬"),
                (GridPoint(x: 1, y: 0), "┐"),
            ]
        }
        var marks = toes
        switch style {
        case .many:
            break
        case .oneOrMany:
            let bar: Character = direction.y == 0 ? "│" : "─"
            if direction.y == 0 {
                marks.append((GridPoint(x: back.x, y: -1), bar))
                marks.append((GridPoint(x: back.x, y: 0), bar))
                marks.append((GridPoint(x: back.x, y: 1), bar))
            } else {
                marks.append((GridPoint(x: -1, y: back.y), bar))
                marks.append((GridPoint(x: 0, y: back.y), bar))
                marks.append((GridPoint(x: 1, y: back.y), bar))
            }
        case .zeroOrMany:
            marks.append((back, "o"))
        }
        return marks
    }

    static func textRows(_ text: String, sweep: LineSweep, alignment: TextAlignment) -> [String] {
        let source = text.components(separatedBy: "\n")
        let rows: [String]
        switch sweep {
        case .down:
            rows = source
        case .up:
            rows = source.reversed()
        case .right:
            rows = columns(source, reversed: false)
        case .left:
            rows = columns(source, reversed: true)
        }
        return pad(rows, alignment: alignment)
    }

    static func columns(_ source: [String], reversed: Bool) -> [String] {
        var cols = source.map { Array($0) }
        if reversed { cols.reverse() }
        let height = cols.map(\.count).max() ?? 0
        var rows: [String] = []
        for row in 0..<height {
            var line = ""
            for column in cols {
                if row < column.count {
                    line.append(column[row])
                } else {
                    line.append(" ")
                }
            }
            rows.append(line)
        }
        return rows
    }

    static func pad(_ rows: [String], alignment: TextAlignment) -> [String] {
        let width = rows.map(\.count).max() ?? 0
        return rows.map { row in
            let extra = max(0, width - row.count)
            switch alignment {
            case .left:
                return row + String(repeating: " ", count: extra)
            case .right:
                return String(repeating: " ", count: extra) + row
            case .center:
                let left = extra / 2
                return String(repeating: " ", count: left) + row + String(repeating: " ", count: extra - left)
            }
        }
    }

    static func place(
        rows: [String],
        in content: GridRect,
        alignment: TextAlignment,
        position: TextVerticalPosition,
        movement: LineMovement,
        into cells: inout [GridPoint: Character]
    ) {
        guard content.width > 0, content.height > 0 else { return }
        let blockHeight = rows.count
        let blockWidth = rows.map(\.count).max() ?? 0
        guard blockHeight > 0, blockWidth > 0 else { return }

        let x0: Int
        switch movement {
        case .left:
            x0 = content.minX
        case .right:
            x0 = content.maxX - blockWidth
        case .none, .top, .bottom:
            switch alignment {
            case .left: x0 = content.minX
            case .right: x0 = content.maxX - blockWidth
            case .center: x0 = content.minX + (content.width - blockWidth) / 2
            }
        }

        let y0: Int
        switch movement {
        case .top:
            y0 = content.minY
        case .bottom:
            y0 = content.maxY - blockHeight
        case .none, .left, .right:
            switch position {
            case .top: y0 = content.minY
            case .bottom: y0 = content.maxY - blockHeight
            case .middle: y0 = content.minY + (content.height - blockHeight) / 2
            }
        }

        for (rowIndex, row) in rows.enumerated() {
            let y = y0 + rowIndex
            guard y >= content.minY && y < content.maxY else { continue }
            for (columnIndex, character) in row.enumerated() {
                let x = x0 + columnIndex
                guard x >= content.minX && x < content.maxX else { continue }
                if character != " " {
                    cells[GridPoint(x: x, y: y)] = character
                }
            }
        }
    }
}
