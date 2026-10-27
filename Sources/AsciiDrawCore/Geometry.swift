import Foundation

public struct GridPoint: Equatable, Hashable, Codable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    public func offset(by delta: GridPoint) -> GridPoint {
        GridPoint(x: x + delta.x, y: y + delta.y)
    }
}

public struct GridRect: Equatable, Hashable, Codable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Int { x }
    public var minY: Int { y }
    public var maxX: Int { x + width }
    public var maxY: Int { y + height }
    public var centerX: Int { x + width / 2 }
    public var centerY: Int { y + height / 2 }

    public func contains(_ point: GridPoint) -> Bool {
        point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
    }

    public func contains(_ other: GridRect) -> Bool {
        other.width > 0 && other.height > 0
            && other.minX >= minX && other.maxX <= maxX
            && other.minY >= minY && other.maxY <= maxY
    }

    public func insetBy(_ amount: Int) -> GridRect {
        GridRect(x: x + amount, y: y + amount, width: width - 2 * amount, height: height - 2 * amount)
    }

    public func offset(by delta: GridPoint) -> GridRect {
        GridRect(x: x + delta.x, y: y + delta.y, width: width, height: height)
    }

    public static func normalized(from start: GridPoint, to end: GridPoint, minimum: Int = 1) -> GridRect {
        let x = min(start.x, end.x)
        let y = min(start.y, end.y)
        let width = max(minimum, abs(end.x - start.x) + 1)
        let height = max(minimum, abs(end.y - start.y) + 1)
        return GridRect(x: x, y: y, width: width, height: height)
    }

    public func union(_ other: GridRect) -> GridRect {
        let minX = min(self.minX, other.minX)
        let minY = min(self.minY, other.minY)
        let maxX = max(self.maxX, other.maxX)
        let maxY = max(self.maxY, other.maxY)
        return GridRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

public enum RectEdge: String, Equatable, Codable, CaseIterable {
    case top, right, bottom, left
}

public func borderPoint(frame: GridRect, edge: RectEdge, t: Double) -> GridPoint {
    let clamped = min(1, max(0, t))
    switch edge {
    case .top, .bottom:
        let span = max(0, frame.width - 1)
        let offset = Int((Double(span) * clamped).rounded(.toNearestOrAwayFromZero))
        let y = edge == .top ? frame.minY : frame.maxY - 1
        return GridPoint(x: frame.minX + offset, y: y)
    case .left, .right:
        let span = max(0, frame.height - 1)
        let offset = Int((Double(span) * clamped).rounded(.toNearestOrAwayFromZero))
        let x = edge == .left ? frame.minX : frame.maxX - 1
        return GridPoint(x: x, y: frame.minY + offset)
    }
}

func boundsOf(points: some Sequence<GridPoint>) -> GridRect? {
    var minX = Int.max
    var minY = Int.max
    var maxX = Int.min
    var maxY = Int.min
    var any = false
    for point in points {
        any = true
        minX = min(minX, point.x)
        minY = min(minY, point.y)
        maxX = max(maxX, point.x)
        maxY = max(maxY, point.y)
    }
    guard any else { return nil }
    return GridRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}
