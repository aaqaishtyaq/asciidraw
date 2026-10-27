import Foundation

public enum BorderStyle: String, Equatable, Codable, CaseIterable {
    case single
    case double
}

public struct ShadowStyle: Equatable, Codable {
    public var character: String
    public var dx: Int
    public var dy: Int

    public init(character: String, dx: Int, dy: Int) {
        self.character = character
        self.dx = dx
        self.dy = dy
    }

    public var glyph: Character? {
        guard let first = character.first, first != " " else { return nil }
        return first
    }
}

public struct BorderPoint: Equatable, Identifiable, Codable {
    public var id: UUID
    public var edge: RectEdge
    public var t: Double

    public init(id: UUID = UUID(), edge: RectEdge, t: Double) {
        self.id = id
        self.edge = edge
        self.t = min(1, max(0, t))
    }
}

public struct RectangleProps: Equatable, Codable {
    public var border: BorderStyle?
    public var fill: String?
    public var shadow: ShadowStyle?
    public var points: [BorderPoint]

    public init(border: BorderStyle? = .single, fill: String? = nil, shadow: ShadowStyle? = nil, points: [BorderPoint] = []) {
        self.border = border
        self.fill = fill
        self.shadow = shadow
        self.points = points
    }

    public var fillGlyph: Character? {
        guard let fill, let first = fill.first, first != " " else { return nil }
        return first
    }
}

public enum TextAlignment: String, Equatable, Codable, CaseIterable {
    case left, center, right
}

public enum TextVerticalPosition: String, Equatable, Codable, CaseIterable {
    case top, middle, bottom
}

/// Direction successive source lines are laid out.
public enum LineSweep: String, Equatable, Codable, CaseIterable {
    case down, up, right, left
}

/// Edge a text block stays glued to when its frame is resized.
public enum LineMovement: String, Equatable, Codable, CaseIterable {
    case none, top, bottom, left, right
}

public struct TextProps: Equatable, Codable {
    public var text: String
    public var alignment: TextAlignment
    public var position: TextVerticalPosition
    public var sweep: LineSweep
    public var lineMovement: LineMovement
    public var border: BorderStyle?

    public init(
        text: String,
        alignment: TextAlignment = .left,
        position: TextVerticalPosition = .top,
        sweep: LineSweep = .down,
        lineMovement: LineMovement = .none,
        border: BorderStyle? = nil
    ) {
        self.text = text
        self.alignment = alignment
        self.position = position
        self.sweep = sweep
        self.lineMovement = lineMovement
        self.border = border
    }
}

public enum LineRouting: String, Equatable, Codable, CaseIterable {
    case orthogonal
    case staircase
}

public enum CrowsFootStyle: String, Equatable, Codable, CaseIterable {
    case many
    case oneOrMany
    case zeroOrMany
}

public enum LineCap: Equatable, Codable {
    case none
    case arrow
    case crowsFoot(CrowsFootStyle)
}

public struct DashPattern: Equatable, Codable {
    public var on: Int
    public var off: Int

    public init(on: Int, off: Int) {
        self.on = max(1, on)
        self.off = max(0, off)
    }

    public static let solid = DashPattern(on: 1, off: 0)
}

public struct LineAnchor: Equatable, Codable {
    public var shapeID: UUID
    public var edge: RectEdge
    public var t: Double
    public var pointID: UUID?

    public init(shapeID: UUID, edge: RectEdge, t: Double, pointID: UUID? = nil) {
        self.shapeID = shapeID
        self.edge = edge
        self.t = t
        self.pointID = pointID
    }
}

public struct LineProps: Equatable, Codable {
    public var start: GridPoint
    public var end: GridPoint
    public var startAttachment: LineAnchor?
    public var endAttachment: LineAnchor?
    public var routing: LineRouting
    public var dash: DashPattern
    public var startCap: LineCap
    public var endCap: LineCap
    public var horizontalFirst: Bool

    public init(
        start: GridPoint,
        end: GridPoint,
        startAttachment: LineAnchor? = nil,
        endAttachment: LineAnchor? = nil,
        routing: LineRouting = .orthogonal,
        dash: DashPattern = .solid,
        startCap: LineCap = .none,
        endCap: LineCap = .none,
        horizontalFirst: Bool = true
    ) {
        self.start = start
        self.end = end
        self.startAttachment = startAttachment
        self.endAttachment = endAttachment
        self.routing = routing
        self.dash = dash
        self.startCap = startCap
        self.endCap = endCap
        self.horizontalFirst = horizontalFirst
    }
}

public struct BannerProps: Equatable, Codable {
    public var text: String
    public var fontName: String
    public var customFLF: String?
    public var alignment: TextAlignment
    public var position: TextVerticalPosition

    public init(
        text: String,
        fontName: String = "standard",
        customFLF: String? = nil,
        alignment: TextAlignment = .left,
        position: TextVerticalPosition = .top
    ) {
        self.text = text
        self.fontName = fontName
        self.customFLF = customFLF
        self.alignment = alignment
        self.position = position
    }
}

public enum DrawKind: Equatable, Codable {
    case rectangle(RectangleProps)
    case diamond
    case text(TextProps)
    case line(LineProps)
    case banner(BannerProps)
}

public struct DrawObject: Equatable, Identifiable, Codable {
    public var id: UUID
    public var name: String
    public var zIndex: Int
    public var locked: Bool
    public var hidden: Bool
    public var groupID: UUID?
    public var frame: GridRect
    public var kind: DrawKind

    public init(
        id: UUID = UUID(),
        name: String,
        zIndex: Int,
        locked: Bool = false,
        hidden: Bool = false,
        groupID: UUID? = nil,
        frame: GridRect,
        kind: DrawKind
    ) {
        self.id = id
        self.name = name
        self.zIndex = zIndex
        self.locked = locked
        self.hidden = hidden
        self.groupID = groupID
        self.frame = frame
        self.kind = kind
    }
}

public struct DrawGroup: Equatable, Identifiable, Codable {
    public var id: UUID
    public var name: String
    public var memberIDs: [UUID]

    public init(id: UUID = UUID(), name: String, memberIDs: [UUID]) {
        self.id = id
        self.name = name
        self.memberIDs = memberIDs
    }
}

public struct Stamp: Equatable, Codable {
    public var x: Int
    public var y: Int
    public var character: String

    public init(x: Int, y: Int, character: String) {
        self.x = x
        self.y = y
        self.character = character
    }

    public var point: GridPoint { GridPoint(x: x, y: y) }
}

public struct Document: Equatable, Codable {
    public var version: Int
    public var objects: [DrawObject]
    public var groups: [DrawGroup]
    public var stamps: [Stamp]

    public init(version: Int = 1, objects: [DrawObject] = [], groups: [DrawGroup] = [], stamps: [Stamp] = []) {
        self.version = version
        self.objects = objects
        self.groups = groups
        self.stamps = stamps
    }

    public init(data: Data) throws {
        let decoder = JSONDecoder()
        self = try decoder.decode(Document.self, from: data)
    }

    public func encoded() throws -> Data {
        var copy = self
        copy.stamps.sort { lhs, rhs in
            if lhs.y != rhs.y { return lhs.y < rhs.y }
            return lhs.x < rhs.x
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(copy)
    }

    public func object(_ id: UUID) -> DrawObject? {
        objects.first { $0.id == id }
    }

    mutating func objectIndex(_ id: UUID) -> Int? {
        objects.firstIndex { $0.id == id }
    }

    mutating func setStamp(_ point: GridPoint, _ character: Character) {
        if let index = stamps.firstIndex(where: { $0.x == point.x && $0.y == point.y }) {
            stamps[index].character = String(character)
        } else {
            stamps.append(Stamp(x: point.x, y: point.y, character: String(character)))
        }
    }

    func resolveAnchor(_ anchor: LineAnchor) -> GridPoint? {
        guard let shape = object(anchor.shapeID) else { return nil }
        if let pointID = anchor.pointID, case .rectangle(let props) = shape.kind,
           let point = props.points.first(where: { $0.id == pointID }) {
            return borderPoint(frame: shape.frame, edge: point.edge, t: point.t)
        }
        return borderPoint(frame: shape.frame, edge: anchor.edge, t: anchor.t)
    }

    mutating func refreshGeometry() {
        for index in objects.indices {
            guard case .line(var props) = objects[index].kind else { continue }
            if let anchor = props.startAttachment {
                if let point = resolveAnchor(anchor) {
                    props.start = point
                } else {
                    props.startAttachment = nil
                }
            }
            if let anchor = props.endAttachment {
                if let point = resolveAnchor(anchor) {
                    props.end = point
                } else {
                    props.endAttachment = nil
                }
            }
            objects[index].kind = .line(props)
            let cells = ShapeRaster.lineCells(props)
            if let bounds = boundsOf(points: cells.keys) {
                objects[index].frame = bounds
            }
        }
    }
}
