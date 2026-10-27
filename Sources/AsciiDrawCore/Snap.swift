import Foundation

public struct SnapGuide: Equatable, Codable {
    public enum Kind: String, Equatable, Codable {
        case edge
        case center
    }

    public enum Axis: String, Equatable, Codable {
        case horizontal
        case vertical
    }

    public var axis: Axis
    /// Vertical guides share an x coordinate. Horizontal guides share a y coordinate.
    public var position: Int
    public var kind: Kind

    public init(axis: Axis, position: Int, kind: Kind) {
        self.axis = axis
        self.position = position
        self.kind = kind
    }
}

public enum Snap {
    public static func move(
        bounds: GridRect,
        proposedDelta: GridPoint,
        others: [GridRect],
        threshold: Int
    ) -> (delta: GridPoint, guides: [SnapGuide]) {
        guard threshold >= 0 else { return (proposedDelta, []) }
        let proposed = bounds.offset(by: proposedDelta)
        let xSnap = snapAxis(
            movingEdges: [proposed.minX, proposed.maxX],
            movingCenter: proposed.centerX,
            targetEdges: others.flatMap { [$0.minX, $0.maxX] },
            targetCenters: others.map(\.centerX),
            threshold: threshold
        )
        let ySnap = snapAxis(
            movingEdges: [proposed.minY, proposed.maxY],
            movingCenter: proposed.centerY,
            targetEdges: others.flatMap { [$0.minY, $0.maxY] },
            targetCenters: others.map(\.centerY),
            threshold: threshold
        )
        var guides: [SnapGuide] = []
        if let xSnap {
            guides.append(SnapGuide(axis: .vertical, position: xSnap.position, kind: xSnap.kind))
        }
        if let ySnap {
            guides.append(SnapGuide(axis: .horizontal, position: ySnap.position, kind: ySnap.kind))
        }
        return (
            GridPoint(x: proposedDelta.x + (xSnap?.delta ?? 0), y: proposedDelta.y + (ySnap?.delta ?? 0)),
            guides
        )
    }

    public static func resize(
        original: GridRect,
        proposed: GridRect,
        others: [GridRect],
        threshold: Int
    ) -> (rect: GridRect, guides: [SnapGuide]) {
        var rect = GridRect(
            x: proposed.x,
            y: proposed.y,
            width: max(2, proposed.width),
            height: max(2, proposed.height)
        )
        guard threshold >= 0 else { return (rect, []) }
        var guides: [SnapGuide] = []
        let xEdges = others.flatMap { [$0.minX, $0.maxX] }
        let xCenters = others.map(\.centerX)
        let yEdges = others.flatMap { [$0.minY, $0.maxY] }
        let yCenters = others.map(\.centerY)

        if rect.minX != original.minX, let snap = snapValue(rect.minX, edges: xEdges, centers: xCenters, threshold: threshold) {
            let shift = snap.position - rect.minX
            rect.x += shift
            rect.width -= shift
            guides.append(SnapGuide(axis: .vertical, position: snap.position, kind: snap.kind))
        }
        if rect.maxX != original.maxX, let snap = snapValue(rect.maxX, edges: xEdges, centers: xCenters, threshold: threshold) {
            rect.width += snap.position - rect.maxX
            guides.append(SnapGuide(axis: .vertical, position: snap.position, kind: snap.kind))
        }
        if rect.minY != original.minY, let snap = snapValue(rect.minY, edges: yEdges, centers: yCenters, threshold: threshold) {
            let shift = snap.position - rect.minY
            rect.y += shift
            rect.height -= shift
            guides.append(SnapGuide(axis: .horizontal, position: snap.position, kind: snap.kind))
        }
        if rect.maxY != original.maxY, let snap = snapValue(rect.maxY, edges: yEdges, centers: yCenters, threshold: threshold) {
            rect.height += snap.position - rect.maxY
            guides.append(SnapGuide(axis: .horizontal, position: snap.position, kind: snap.kind))
        }
        if rect.width < 2 { rect.width = 2 }
        if rect.height < 2 { rect.height = 2 }
        return (rect, guides)
    }

    private struct AxisSnap {
        var delta: Int
        var position: Int
        var kind: SnapGuide.Kind
    }

    private static func snapAxis(
        movingEdges: [Int],
        movingCenter: Int,
        targetEdges: [Int],
        targetCenters: [Int],
        threshold: Int
    ) -> AxisSnap? {
        var best: AxisSnap?
        func consider(from: Int, to: Int, kind: SnapGuide.Kind) {
            let delta = to - from
            guard abs(delta) <= threshold else { return }
            if let current = best {
                if abs(delta) > abs(current.delta) { return }
                if abs(delta) == abs(current.delta) && kind == .center && current.kind == .edge { return }
            }
            best = AxisSnap(delta: delta, position: to, kind: kind)
        }
        for edge in movingEdges {
            for target in targetEdges {
                consider(from: edge, to: target, kind: .edge)
            }
        }
        for target in targetCenters {
            consider(from: movingCenter, to: target, kind: .center)
        }
        return best
    }

    private static func snapValue(_ value: Int, edges: [Int], centers: [Int], threshold: Int) -> AxisSnap? {
        snapAxis(movingEdges: [value], movingCenter: value, targetEdges: edges, targetCenters: centers, threshold: threshold)
    }
}
