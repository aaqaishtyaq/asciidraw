import Foundation

public struct RenderedGrid: Equatable {
    public let minX: Int
    public let minY: Int
    public let rows: [String]

    public var columnCount: Int { rows.first?.count ?? 0 }
    public var rowCount: Int { rows.count }
    public var plainText: String { rows.joined(separator: "\n") }

    public var bounds: GridRect? {
        guard columnCount > 0, rowCount > 0 else { return nil }
        return GridRect(x: minX, y: minY, width: columnCount, height: rowCount)
    }

    public func character(at point: GridPoint) -> Character {
        let column = point.x - minX
        let row = point.y - minY
        guard row >= 0, row < rows.count, column >= 0, column < rows[row].count else { return " " }
        let line = rows[row]
        let index = line.index(line.startIndex, offsetBy: column)
        return line[index]
    }

    static let empty = RenderedGrid(minX: 0, minY: 0, rows: [])
}

public enum Renderer {
    public static func render(_ document: Document) -> RenderedGrid {
        var working = document
        working.refreshGeometry()
        return renderResolved(working)
    }

    static func renderResolved(_ document: Document) -> RenderedGrid {
        let ordered = document.objects.enumerated()
            .filter { !$0.element.hidden }
            .sorted { lhs, rhs in
                if lhs.element.zIndex != rhs.element.zIndex {
                    return lhs.element.zIndex < rhs.element.zIndex
                }
                return lhs.offset < rhs.offset
            }

        var canvas: [GridPoint: Ink] = [:]
        for (_, object) in ordered {
            let drawn = ShapeRaster.cells(for: object)
            let blends = borderBlends(object)
            for (point, character) in drawn {
                let ink = Ink(character: character, z: object.zIndex, blends: blends)
                canvas[point] = composite(canvas[point], ink)
            }
        }

        var erased = Set<GridPoint>()
        var stamps: [GridPoint: Character] = [:]
        for stamp in document.stamps {
            let point = stamp.point
            let character = stamp.character.first ?? " "
            if character == " " {
                stamps[point] = nil
                erased.insert(point)
            } else {
                erased.remove(point)
                stamps[point] = character
            }
        }
        for point in erased {
            canvas[point] = nil
        }
        for (point, character) in stamps {
            canvas[point] = Ink(character: character, z: Int.max)
        }

        let ink = canvas.filter { $0.value.character != " " }
        var minX = Int.max
        var minY = Int.max
        var maxX = Int.min
        var maxY = Int.min
        var any = false
        func absorb(_ x: Int, _ y: Int) {
            any = true
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
        for point in ink.keys {
            absorb(point.x, point.y)
        }
        for object in document.objects where !object.hidden && object.frame.width > 0 && object.frame.height > 0 {
            absorb(object.frame.minX, object.frame.minY)
            absorb(object.frame.maxX - 1, object.frame.maxY - 1)
        }
        guard any else { return .empty }

        var rows: [String] = []
        for y in minY...maxY {
            var row = ""
            row.reserveCapacity(maxX - minX + 1)
            for x in minX...maxX {
                let character = ink[GridPoint(x: x, y: y)]?.character ?? " "
                row.append(AlphabetMap.display(character, alphabet: document.alphabet))
            }
            rows.append(row)
        }
        return RenderedGrid(minX: minX, minY: minY, rows: rows)
    }

    private static func borderBlends(_ object: DrawObject) -> Bool {
        switch object.kind {
        case .rectangle(let props):
            return props.blended
        case .text(let props):
            return props.blended
        case .diamond, .line, .banner:
            return true
        }
    }
}
