import Foundation

public enum Tool: String, Equatable, Codable, CaseIterable {
    case select, rect, diamond, text, line, pencil, eraser, bucket, picker, banner, pan

    public var title: String {
        switch self {
        case .select: return "Select"
        case .rect: return "Rectangle"
        case .diamond: return "Diamond"
        case .text: return "Text"
        case .line: return "Line"
        case .pencil: return "Pencil"
        case .eraser: return "Eraser"
        case .bucket: return "Bucket"
        case .picker: return "Picker"
        case .banner: return "Banner"
        case .pan: return "Pan"
        }
    }
}

public struct KeyChord: Equatable {
    public var character: Character
    public var command: Bool
    public var option: Bool
    public var control: Bool
    public var shift: Bool

    public init(character: Character, command: Bool = false, option: Bool = false, control: Bool = false, shift: Bool = false) {
        self.character = character
        self.command = command
        self.option = option
        self.control = control
        self.shift = shift
    }
}

public enum KeyAction: Equatable {
    case selectTool(Tool)
    case beginSpacePan
}

public enum ToolShortcut {
    public static let map: [(Character, Tool)] = [
        ("v", .select),
        ("r", .rect),
        ("d", .diamond),
        ("t", .text),
        ("l", .line),
        ("p", .pencil),
        ("e", .eraser),
        ("b", .bucket),
        ("k", .picker),
        ("a", .banner),
        ("h", .pan),
    ]

    public static func tool(for key: Character) -> Tool? {
        let folded = Character(String(key).lowercased())
        return map.first { $0.0 == folded }?.1
    }
}

public enum KeyBinding {
    /// Unmodified letter keys select tools. Command, option, and control do not.
    /// Space begins a temporary pan. Shift is allowed so uppercase letters still select.
    public static func interpret(_ chord: KeyChord) -> KeyAction? {
        if chord.command || chord.option || chord.control { return nil }
        if chord.character == " " { return .beginSpacePan }
        if let tool = ToolShortcut.tool(for: chord.character) {
            return .selectTool(tool)
        }
        return nil
    }
}

public enum ResizeHandle: String, Equatable, CaseIterable {
    case left, right, top, bottom
    case topLeft, topRight, bottomLeft, bottomRight
}

public enum GestureMode: Equatable {
    case accumulate
    case replace
}

public struct Editor: Equatable {
    public private(set) var document: Document
    public private(set) var tool: Tool
    public private(set) var spaceHeld: Bool
    public var pencilCharacter: Character
    public var snapThreshold: Int

    private var undoStack: [Document]
    private var redoStack: [Document]
    private var gestureBaseline: Document?
    private var gestureMode: GestureMode
    private var gesturePushed: Bool

    public var activeTool: Tool { spaceHeld ? .pan : tool }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public init(document: Document = Document()) {
        self.document = document
        tool = .select
        spaceHeld = false
        pencilCharacter = "x"
        snapThreshold = 1
        undoStack = []
        redoStack = []
        gestureBaseline = nil
        gestureMode = .accumulate
        gesturePushed = false
    }

    public init(data: Data) throws {
        self.init(document: try Document(data: data))
    }

    public func object(_ id: UUID) -> DrawObject? {
        document.object(id)
    }

    public func render() -> RenderedGrid {
        Renderer.render(document)
    }

    public func saveData() throws -> Data {
        try document.encoded()
    }

    public mutating func selectTool(_ tool: Tool) {
        self.tool = tool
    }

    @discardableResult
    public mutating func selectTool(key: Character) -> Bool {
        guard let tool = ToolShortcut.tool(for: key) else { return false }
        self.tool = tool
        return true
    }

    public mutating func beginSpacePan() {
        spaceHeld = true
    }

    public mutating func endSpacePan() {
        spaceHeld = false
    }

    public mutating func beginGesture(_ mode: GestureMode) {
        gestureBaseline = document
        gestureMode = mode
        gesturePushed = false
    }

    public mutating func endGesture() {
        if gesturePushed, let baseline = gestureBaseline, document == baseline {
            _ = undoStack.popLast()
        }
        gestureBaseline = nil
        gesturePushed = false
    }

    public mutating func clearHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
    }

    @discardableResult
    public mutating func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        redoStack.append(document)
        document = previous
        return true
    }

    @discardableResult
    public mutating func redo() -> Bool {
        guard let next = redoStack.popLast() else { return false }
        undoStack.append(document)
        document = next
        return true
    }

    @discardableResult
    public mutating func addRectangle(
        frame: GridRect,
        border: BorderStyle? = .single,
        fill: String? = nil,
        shadow: ShadowStyle? = nil
    ) -> UUID {
        let id = UUID()
        perform { document in
            document.objects.append(DrawObject(
                id: id,
                name: nextName("Rectangle", in: document),
                zIndex: nextZ(document),
                frame: frame,
                kind: .rectangle(RectangleProps(border: border, fill: fill, shadow: shadow))
            ))
        }
        return id
    }

    @discardableResult
    public mutating func addDiamond(frame: GridRect) -> UUID {
        let id = UUID()
        perform { document in
            document.objects.append(DrawObject(
                id: id,
                name: nextName("Diamond", in: document),
                zIndex: nextZ(document),
                frame: frame,
                kind: .diamond
            ))
        }
        return id
    }

    @discardableResult
    public mutating func addText(frame: GridRect, text: String, style: TextProps? = nil) -> UUID {
        let id = UUID()
        var props = style ?? TextProps(text: text)
        props.text = text
        perform { document in
            document.objects.append(DrawObject(
                id: id,
                name: nextName("Text", in: document),
                zIndex: nextZ(document),
                frame: frame,
                kind: .text(props)
            ))
        }
        return id
    }

    @discardableResult
    public mutating func addLine(_ props: LineProps) -> UUID {
        let id = UUID()
        perform { document in
            document.objects.append(DrawObject(
                id: id,
                name: nextName("Line", in: document),
                zIndex: nextZ(document),
                frame: GridRect(x: min(props.start.x, props.end.x), y: min(props.start.y, props.end.y), width: 1, height: 1),
                kind: .line(props)
            ))
        }
        return id
    }

    @discardableResult
    public mutating func addBanner(
        frame: GridRect,
        text: String,
        fontName: String = "standard",
        alignment: TextAlignment = .left,
        position: TextVerticalPosition = .top
    ) -> UUID {
        let id = UUID()
        perform { document in
            document.objects.append(DrawObject(
                id: id,
                name: nextName("Banner", in: document),
                zIndex: nextZ(document),
                frame: frame,
                kind: .banner(BannerProps(text: text, fontName: fontName, alignment: alignment, position: position))
            ))
        }
        return id
    }

    @discardableResult
    public mutating func addBorderPoint(_ shapeID: UUID, edge: RectEdge, t: Double) -> UUID? {
        guard case .rectangle = document.object(shapeID)?.kind else { return nil }
        let pointID = UUID()
        perform { document in
            guard let index = document.objectIndex(shapeID), case .rectangle(var props) = document.objects[index].kind else { return }
            props.points.append(BorderPoint(id: pointID, edge: edge, t: t))
            document.objects[index].kind = .rectangle(props)
        }
        return pointID
    }

    public mutating func setRectangle(_ id: UUID, _ body: (inout RectangleProps) -> Void) {
        perform { document in
            guard let index = document.objectIndex(id), case .rectangle(var props) = document.objects[index].kind else { return }
            body(&props)
            document.objects[index].kind = .rectangle(props)
        }
    }

    public mutating func setText(_ id: UUID, _ body: (inout TextProps) -> Void) {
        perform { document in
            guard let index = document.objectIndex(id), case .text(var props) = document.objects[index].kind else { return }
            body(&props)
            document.objects[index].kind = .text(props)
        }
    }

    public mutating func setLine(_ id: UUID, _ body: (inout LineProps) -> Void) {
        perform { document in
            guard let index = document.objectIndex(id), case .line(var props) = document.objects[index].kind else { return }
            body(&props)
            document.objects[index].kind = .line(props)
        }
    }

    public mutating func setBanner(_ id: UUID, _ body: (inout BannerProps) -> Void) {
        perform { document in
            guard let index = document.objectIndex(id), case .banner(var props) = document.objects[index].kind else { return }
            body(&props)
            document.objects[index].kind = .banner(props)
        }
    }

    public mutating func setFrame(_ id: UUID, _ frame: GridRect) {
        _ = resizeObject(id, to: frame, snap: false)
    }

    public mutating func loadBannerFont(_ id: UUID, from url: URL) throws {
        let data = try Data(contentsOf: url)
        let font = try FigletFont.load(data: data, name: url.deletingPathExtension().lastPathComponent)
        let source = String(data: data, encoding: .utf8) ?? ""
        guard !source.isEmpty else { throw AsciiDrawError.invalidFont("empty font file") }
        _ = font
        setBanner(id) { props in
            props.customFLF = source
            props.fontName = font.name
        }
    }

    public mutating func setName(_ id: UUID, _ name: String) {
        perform { document in
            guard let index = document.objectIndex(id) else { return }
            document.objects[index].name = name
        }
    }

    public mutating func setLocked(_ id: UUID, _ locked: Bool) {
        perform { document in
            guard let index = document.objectIndex(id) else { return }
            document.objects[index].locked = locked
        }
    }

    public mutating func setHidden(_ id: UUID, _ hidden: Bool) {
        perform { document in
            guard let index = document.objectIndex(id) else { return }
            document.objects[index].hidden = hidden
        }
    }

    public mutating func setZIndex(_ id: UUID, _ zIndex: Int) {
        perform { document in
            guard let index = document.objectIndex(id) else { return }
            document.objects[index].zIndex = zIndex
        }
    }

    public mutating func bringToFront(_ id: UUID) {
        let maxZ = document.objects.map(\.zIndex).max() ?? 0
        setZIndex(id, maxZ + 1)
    }

    public mutating func sendToBack(_ id: UUID) {
        let minZ = document.objects.map(\.zIndex).min() ?? 0
        setZIndex(id, minZ - 1)
    }

    @discardableResult
    public mutating func group(_ ids: [UUID]) -> UUID? {
        let members = ids.filter { document.object($0) != nil }
        guard members.count >= 2 else { return nil }
        let groupID = UUID()
        perform { document in
            document.groups.append(DrawGroup(id: groupID, name: nextName("Group", in: document, groups: true), memberIDs: members))
            for index in document.objects.indices where members.contains(document.objects[index].id) {
                document.objects[index].groupID = groupID
            }
            pruneGroups(&document, keeping: groupID)
        }
        return groupID
    }

    public mutating func ungroup(_ groupID: UUID) {
        perform { document in
            document.groups.removeAll { $0.id == groupID }
            for index in document.objects.indices where document.objects[index].groupID == groupID {
                document.objects[index].groupID = nil
            }
        }
    }

    @discardableResult
    public mutating func duplicateGroup(_ groupID: UUID, offset: GridPoint) -> UUID? {
        guard let group = document.groups.first(where: { $0.id == groupID }) else { return nil }
        return duplicateObjects(group.memberIDs, offset: offset, name: group.name + " copy")
    }

    @discardableResult
    public mutating func duplicateObjects(_ ids: [UUID], offset: GridPoint, name: String? = nil) -> UUID? {
        let sourceIDs = ids.filter { document.object($0) != nil }
        guard !sourceIDs.isEmpty else { return nil }
        var newGroupID: UUID?
        perform { document in
            var idMap: [UUID: UUID] = [:]
            var pointMap: [UUID: UUID] = [:]
            for id in sourceIDs { idMap[id] = UUID() }
            for id in sourceIDs {
                guard let object = document.object(id), case .rectangle(let props) = object.kind else { continue }
                for point in props.points { pointMap[point.id] = UUID() }
            }
            var members: [UUID] = []
            let zBoost = (document.objects.map(\.zIndex).max() ?? 0) + 1
            for (offsetIndex, id) in sourceIDs.enumerated() {
                guard var object = document.object(id), let newID = idMap[id] else { continue }
                object.id = newID
                object.groupID = nil
                object.frame.x += offset.x
                object.frame.y += offset.y
                object.zIndex = zBoost + offsetIndex
                switch object.kind {
                case .rectangle(var props):
                    for index in props.points.indices {
                        if let mapped = pointMap[props.points[index].id] {
                            props.points[index].id = mapped
                        }
                    }
                    object.kind = .rectangle(props)
                case .line(var props):
                    props.start = props.start.offset(by: offset)
                    props.end = props.end.offset(by: offset)
                    props.startAttachment = remap(props.startAttachment, ids: idMap, points: pointMap)
                    props.endAttachment = remap(props.endAttachment, ids: idMap, points: pointMap)
                    object.kind = .line(props)
                default:
                    break
                }
                members.append(newID)
                document.objects.append(object)
            }
            if members.count >= 2 {
                let groupID = UUID()
                let groupName = name ?? "Group copy"
                document.groups.append(DrawGroup(id: groupID, name: groupName, memberIDs: members))
                for index in document.objects.indices where members.contains(document.objects[index].id) {
                    document.objects[index].groupID = groupID
                }
                newGroupID = groupID
            }
        }
        return newGroupID
    }

    @discardableResult
    public mutating func moveObjects(_ ids: [UUID], by delta: GridPoint) -> [SnapGuide] {
        let threshold = snapThreshold
        var guides: [SnapGuide] = []
        perform { document in
            guides = applyMove(&document, ids: ids, delta: delta, threshold: threshold)
        }
        return guides
    }

    @discardableResult
    public mutating func resizeObject(_ id: UUID, to proposed: GridRect, snap: Bool = true) -> [SnapGuide] {
        let threshold = snap ? snapThreshold : -1
        var guides: [SnapGuide] = []
        perform { document in
            guides = applyResize(&document, id: id, proposed: proposed, threshold: threshold)
        }
        return guides
    }

    public func resizedFrame(original: GridRect, handle: ResizeHandle, to cell: GridPoint) -> GridRect {
        var minX = original.minX
        var minY = original.minY
        var maxX = original.maxX
        var maxY = original.maxY
        switch handle {
        case .left, .topLeft, .bottomLeft: minX = cell.x
        case .right, .topRight, .bottomRight: maxX = cell.x + 1
        case .top, .bottom: break
        }
        switch handle {
        case .top, .topLeft, .topRight: minY = cell.y
        case .bottom, .bottomLeft, .bottomRight: maxY = cell.y + 1
        case .left, .right: break
        }
        let x = min(minX, maxX - 1)
        let y = min(minY, maxY - 1)
        return GridRect(x: x, y: y, width: max(2, abs(maxX - minX)), height: max(2, abs(maxY - minY)))
    }

    public mutating func deleteObjects(_ ids: [UUID]) {
        let remove = Set(ids)
        guard !remove.isEmpty else { return }
        perform { document in
            document.objects.removeAll { remove.contains($0.id) }
            for index in document.groups.indices {
                document.groups[index].memberIDs.removeAll { remove.contains($0) }
            }
            document.groups.removeAll { $0.memberIDs.count < 2 }
            let liveGroups = Set(document.groups.map(\.id))
            for index in document.objects.indices {
                if let groupID = document.objects[index].groupID, !liveGroups.contains(groupID) {
                    document.objects[index].groupID = nil
                }
            }
        }
    }

    public mutating func pencil(at point: GridPoint, character: Character? = nil) {
        let glyph = character ?? pencilCharacter
        perform { document in
            document.setStamp(point, glyph)
        }
    }

    public mutating func erase(at point: GridPoint) {
        perform { document in
            document.setStamp(point, " ")
        }
    }

    public mutating func bucketFill(at point: GridPoint, character: Character? = nil) {
        let fill = character ?? pencilCharacter
        let grid = Renderer.render(document)
        guard let bounds = grid.bounds, bounds.contains(point) else { return }
        let target = grid.character(at: point)
        if target == fill { return }
        var stack = [point]
        var seen = Set<GridPoint>()
        var region: [GridPoint] = []
        while let current = stack.popLast() {
            if seen.contains(current) || !bounds.contains(current) { continue }
            if grid.character(at: current) != target { continue }
            seen.insert(current)
            region.append(current)
            stack.append(GridPoint(x: current.x + 1, y: current.y))
            stack.append(GridPoint(x: current.x - 1, y: current.y))
            stack.append(GridPoint(x: current.x, y: current.y + 1))
            stack.append(GridPoint(x: current.x, y: current.y - 1))
        }
        perform { document in
            for cell in region {
                document.setStamp(cell, fill)
            }
        }
    }

    @discardableResult
    public mutating func pickCharacter(at point: GridPoint) -> Character {
        let character = Renderer.render(document).character(at: point)
        pencilCharacter = character
        return character
    }

    public func hitTest(_ point: GridPoint) -> UUID? {
        let ordered = document.objects.enumerated()
            .filter { !$0.element.hidden }
            .sorted { lhs, rhs in
                if lhs.element.zIndex != rhs.element.zIndex { return lhs.element.zIndex > rhs.element.zIndex }
                return lhs.offset > rhs.offset
            }
        for (_, object) in ordered {
            if case .line(let props) = object.kind {
                if ShapeRaster.lineCells(props)[point] != nil { return object.id }
            } else if object.frame.contains(point) {
                return object.id
            }
        }
        return nil
    }

    public func fitVisible(
        viewportWidth: Double,
        viewportHeight: Double,
        cellWidth: Double,
        cellHeight: Double,
        padding: Double = 24,
        minZoom: Double = 0.25,
        maxZoom: Double = 6
    ) -> FitResult? {
        Exporter.fit(
            document: document,
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight,
            cellWidth: cellWidth,
            cellHeight: cellHeight,
            padding: padding,
            minZoom: minZoom,
            maxZoom: maxZoom
        )
    }

    public func exportPlainText() -> String { Exporter.plainText(document) }
    public func exportShell() -> String { Exporter.shell(document) }
    public func exportRuby() -> String { Exporter.ruby(document) }
    public func exportPython() -> String { Exporter.python(document) }
    public func exportSVG() -> String { Exporter.svg(document) }
    public func exportPNG() -> Data { Exporter.png(document) }
    public func exportJSON() throws -> Data { try Exporter.jsonData(document) }

    public static func welcome() -> Editor {
        var editor = Editor()
        let box = editor.addRectangle(
            frame: GridRect(x: 2, y: 1, width: 34, height: 9),
            border: .double,
            fill: nil,
            shadow: ShadowStyle(character: "░", dx: 2, dy: 1)
        )
        _ = editor.addText(
            frame: GridRect(x: 4, y: 3, width: 30, height: 3),
            text: "AsciiDraw",
            style: TextProps(text: "AsciiDraw", alignment: .center, position: .middle, sweep: .down, lineMovement: .none, border: nil)
        )
        _ = editor.addText(
            frame: GridRect(x: 4, y: 6, width: 30, height: 2),
            text: "a native diagram canvas",
            style: TextProps(text: "a native diagram canvas", alignment: .center, position: .top)
        )
        _ = editor.addLine(LineProps(
            start: GridPoint(x: 36, y: 5),
            end: GridPoint(x: 48, y: 5),
            startAttachment: LineAnchor(shapeID: box, edge: .right, t: 0.5),
            routing: .orthogonal,
            endCap: .arrow,
            horizontalFirst: true
        ))
        _ = editor.addDiamond(frame: GridRect(x: 50, y: 2, width: 11, height: 7))
        _ = editor.addBanner(
            frame: GridRect(x: 2, y: 12, width: 42, height: 6),
            text: "HI",
            fontName: "standard",
            alignment: .left
        )
        editor.clearHistory()
        return editor
    }

    private mutating func perform(_ body: (inout Document) -> Void) {
        let baseline = gestureBaseline
        let replacing = gestureBaseline != nil && gestureMode == .replace
        if gestureBaseline != nil {
            if !gesturePushed {
                undoStack.append(baseline ?? document)
                redoStack.removeAll()
                gesturePushed = true
            }
        } else {
            undoStack.append(document)
            redoStack.removeAll()
        }
        if undoStack.count > 200 {
            undoStack.removeFirst(undoStack.count - 200)
        }
        var working = replacing ? (baseline ?? document) : document
        body(&working)
        working.refreshGeometry()
        document = working
    }
}

private func nextZ(_ document: Document) -> Int {
    (document.objects.map(\.zIndex).max() ?? -1) + 1
}

private func nextName(_ prefix: String, in document: Document, groups: Bool = false) -> String {
    let count: Int
    if groups {
        count = document.groups.filter { $0.name.hasPrefix(prefix) }.count + 1
    } else {
        count = document.objects.filter { $0.name.hasPrefix(prefix) }.count + 1
    }
    return "\(prefix) \(count)"
}

private func remap(_ anchor: LineAnchor?, ids: [UUID: UUID], points: [UUID: UUID]) -> LineAnchor? {
    guard var anchor else { return nil }
    if let mapped = ids[anchor.shapeID] {
        anchor.shapeID = mapped
    }
    if let pointID = anchor.pointID, let mapped = points[pointID] {
        anchor.pointID = mapped
    }
    return anchor
}

private func pruneGroups(_ document: inout Document, keeping: UUID) {
    let grouped = Set(document.objects.compactMap(\.groupID))
    document.groups.removeAll { $0.id != keeping && !grouped.contains($0.id) }
}

private func expandedUnlocked(_ document: Document, _ ids: [UUID]) -> [UUID] {
    var result: [UUID] = []
    var seen = Set<UUID>()
    for id in ids {
        guard let object = document.object(id) else { continue }
        let members: [UUID]
        if let groupID = object.groupID, let group = document.groups.first(where: { $0.id == groupID }) {
            members = group.memberIDs
        } else {
            members = [id]
        }
        for member in members where seen.insert(member).inserted {
            if let shape = document.object(member), !shape.locked {
                result.append(member)
            }
        }
    }
    return result
}

private func unionFrame(_ document: Document, _ ids: [UUID]) -> GridRect? {
    let frames = ids.compactMap { document.object($0)?.frame }
    guard let first = frames.first else { return nil }
    return frames.dropFirst().reduce(first) { $0.union($1) }
}

private func applyMove(_ document: inout Document, ids: [UUID], delta: GridPoint, threshold: Int) -> [SnapGuide] {
    let moving = expandedUnlocked(document, ids)
    guard !moving.isEmpty, let bounds = unionFrame(document, moving) else { return [] }
    let movingSet = Set(moving)
    let others = document.objects.compactMap { object -> GridRect? in
        guard !object.hidden, !movingSet.contains(object.id) else { return nil }
        if case .line(let props) = object.kind {
            let anchors = [props.startAttachment?.shapeID, props.endAttachment?.shapeID].compactMap { $0 }
            if anchors.contains(where: movingSet.contains) { return nil }
        }
        if bounds.contains(object.frame) { return nil }
        return object.frame
    }
    let snapped = Snap.move(bounds: bounds, proposedDelta: delta, others: others, threshold: threshold)
    let shift = snapped.delta
    for id in moving {
        guard let index = document.objectIndex(id) else { continue }
        document.objects[index].frame.x += shift.x
        document.objects[index].frame.y += shift.y
        if case .line(var props) = document.objects[index].kind {
            if let anchor = props.startAttachment, !movingSet.contains(anchor.shapeID) {
                props.startAttachment = nil
                props.start = props.start.offset(by: shift)
            } else if props.startAttachment == nil {
                props.start = props.start.offset(by: shift)
            }
            if let anchor = props.endAttachment, !movingSet.contains(anchor.shapeID) {
                props.endAttachment = nil
                props.end = props.end.offset(by: shift)
            } else if props.endAttachment == nil {
                props.end = props.end.offset(by: shift)
            }
            document.objects[index].kind = .line(props)
        }
    }
    return snapped.guides
}

private func applyResize(_ document: inout Document, id: UUID, proposed: GridRect, threshold: Int) -> [SnapGuide] {
    guard let index = document.objectIndex(id), !document.objects[index].locked else { return [] }
    if case .line = document.objects[index].kind {
        return []
    }
    let original = document.objects[index].frame
    let others = document.objects.filter { $0.id != id && !$0.hidden }.map(\.frame)
    let snapped = Snap.resize(original: original, proposed: proposed, others: others, threshold: threshold)
    document.objects[index].frame = snapped.rect
    return snapped.guides
}
