import Foundation

enum StrokeWeight: Equatable {
    case light
    case heavy
}

struct Connections: Equatable {
    var north: StrokeWeight? = nil
    var east: StrokeWeight? = nil
    var south: StrokeWeight? = nil
    var west: StrokeWeight? = nil

    func union(_ other: Connections) -> Connections {
        Connections(
            north: Self.merge(north, other.north),
            east: Self.merge(east, other.east),
            south: Self.merge(south, other.south),
            west: Self.merge(west, other.west)
        )
    }

    private static func merge(_ lhs: StrokeWeight?, _ rhs: StrokeWeight?) -> StrokeWeight? {
        switch (lhs, rhs) {
        case (nil, nil):
            return nil
        case (nil, let value?), (let value?, nil):
            return value
        case (.heavy, _), (_, .heavy):
            return .heavy
        default:
            return .light
        }
    }
}

enum BoxDrawing {
    static func connections(for character: Character) -> Connections? {
        switch character {
        case "─": return Connections(east: .light, west: .light)
        case "│": return Connections(north: .light, south: .light)
        case "┌": return Connections(east: .light, south: .light)
        case "┐": return Connections(south: .light, west: .light)
        case "└": return Connections(north: .light, east: .light)
        case "┘": return Connections(north: .light, west: .light)
        case "├": return Connections(north: .light, east: .light, south: .light)
        case "┤": return Connections(north: .light, south: .light, west: .light)
        case "┬": return Connections(east: .light, south: .light, west: .light)
        case "┴": return Connections(north: .light, east: .light, west: .light)
        case "┼": return Connections(north: .light, east: .light, south: .light, west: .light)
        case "═": return Connections(east: .heavy, west: .heavy)
        case "║": return Connections(north: .heavy, south: .heavy)
        case "╔": return Connections(east: .heavy, south: .heavy)
        case "╗": return Connections(south: .heavy, west: .heavy)
        case "╚": return Connections(north: .heavy, east: .heavy)
        case "╝": return Connections(north: .heavy, west: .heavy)
        case "╠": return Connections(north: .heavy, east: .heavy, south: .heavy)
        case "╣": return Connections(north: .heavy, south: .heavy, west: .heavy)
        case "╦": return Connections(east: .heavy, south: .heavy, west: .heavy)
        case "╩": return Connections(north: .heavy, east: .heavy, west: .heavy)
        case "╬": return Connections(north: .heavy, east: .heavy, south: .heavy, west: .heavy)
        case "╪": return Connections(north: .light, east: .heavy, south: .light, west: .heavy)
        case "╫": return Connections(north: .heavy, east: .light, south: .heavy, west: .light)
        default: return nil
        }
    }

    static func glyph(_ connections: Connections) -> Character {
        let horizontal = axis(connections.east, connections.west)
        let vertical = axis(connections.north, connections.south)
        let mask = directionMask(connections)
        if horizontal == .heavy && vertical == .light {
            return mixedDoubleHorizontal(mask)
        }
        if horizontal == .light && vertical == .heavy {
            return mixedDoubleVertical(mask)
        }
        if horizontal == .heavy || vertical == .heavy {
            return heavyGlyph(mask)
        }
        return lightGlyph(mask)
    }

    static func lightGlyph(north: Bool, east: Bool, south: Bool, west: Bool) -> Character {
        var mask = 0
        if north { mask |= 1 }
        if east { mask |= 2 }
        if south { mask |= 4 }
        if west { mask |= 8 }
        return lightGlyph(mask)
    }

    private static func axis(_ a: StrokeWeight?, _ b: StrokeWeight?) -> StrokeWeight? {
        if a == .heavy || b == .heavy { return .heavy }
        if a == .light || b == .light { return .light }
        return nil
    }

    private static func directionMask(_ connections: Connections) -> Int {
        var mask = 0
        if connections.north != nil { mask |= 1 }
        if connections.east != nil { mask |= 2 }
        if connections.south != nil { mask |= 4 }
        if connections.west != nil { mask |= 8 }
        return mask
    }

    private static func lightGlyph(_ mask: Int) -> Character {
        switch mask {
        case 2, 8, 10: return "─"
        case 1, 4, 5: return "│"
        case 6: return "┌"   // E+S
        case 12: return "┐"  // S+W
        case 3: return "└"   // N+E
        case 9: return "┘"   // N+W
        case 7: return "├"   // N+E+S
        case 13: return "┤"  // N+S+W
        case 14: return "┬"  // E+S+W
        case 11: return "┴"  // N+E+W
        case 15: return "┼"
        default: return "┼"
        }
    }

    private static func heavyGlyph(_ mask: Int) -> Character {
        switch mask {
        case 2, 8, 10: return "═"
        case 1, 4, 5: return "║"
        case 6: return "╔"
        case 12: return "╗"
        case 3: return "╚"
        case 9: return "╝"
        case 7: return "╠"
        case 13: return "╣"
        case 14: return "╦"
        case 11: return "╩"
        case 15: return "╬"
        default: return "╬"
        }
    }

    private static func mixedDoubleHorizontal(_ mask: Int) -> Character {
        switch mask {
        case 2, 8, 10: return "═"
        case 15: return "╪"
        case 14: return "╤"
        case 11: return "╧"
        case 7: return "╞"
        case 13: return "╡"
        default: return "╪"
        }
    }

    private static func mixedDoubleVertical(_ mask: Int) -> Character {
        switch mask {
        case 1, 4, 5: return "║"
        case 15: return "╫"
        case 6: return "╓"
        case 12: return "╖"
        case 3: return "╙"
        case 9: return "╜"
        default: return "╫"
        }
    }

    static let single = BorderGlyphs(topLeft: "┌", topRight: "┐", bottomLeft: "└", bottomRight: "┘", horizontal: "─", vertical: "│")
    static let double = BorderGlyphs(topLeft: "╔", topRight: "╗", bottomLeft: "╚", bottomRight: "╝", horizontal: "═", vertical: "║")

    static func glyphs(for style: BorderStyle) -> BorderGlyphs {
        style == .double ? double : single
    }
}

struct BorderGlyphs {
    var topLeft: Character
    var topRight: Character
    var bottomLeft: Character
    var bottomRight: Character
    var horizontal: Character
    var vertical: Character
}

struct Ink {
    var character: Character
    var z: Int
}

func composite(_ existing: Ink?, _ incoming: Ink) -> Ink {
    guard let existing else { return incoming }
    if let left = BoxDrawing.connections(for: existing.character),
       let right = BoxDrawing.connections(for: incoming.character) {
        let merged = left.union(right)
        return Ink(character: BoxDrawing.glyph(merged), z: max(existing.z, incoming.z))
    }
    if incoming.z >= existing.z { return incoming }
    return existing
}
