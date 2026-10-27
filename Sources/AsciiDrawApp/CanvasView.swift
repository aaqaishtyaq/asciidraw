import AsciiDrawCore
import AppKit
import SwiftUI

struct CanvasRepresentable: NSViewRepresentable {
    @ObservedObject var model: EditorModel

    func makeNSView(context: Context) -> DiagramCanvasView {
        let view = DiagramCanvasView()
        view.model = model
        return view
    }

    func updateNSView(_ view: DiagramCanvasView, context: Context) {
        view.model = model
        view.needsDisplay = true
        view.resetCursorRects()
    }
}

final class DiagramCanvasView: NSView {
    var model: EditorModel? {
        didSet { wireFocus() }
    }

    private var anchorCell = GridPoint(x: 0, y: 0)
    private var anchorPoint = NSPoint.zero
    private var anchorScroll = CGPoint.zero
    private var originalFrame = GridRect(x: 0, y: 0, width: 2, height: 2)
    private var resizeHandle: ResizeHandle?
    private var lineEndDrag = false
    private var gesture: GestureMode?
    private var draft: Draft?
    private var painting = false

    private enum Draft {
        case shape(GridRect)
        case line(GridPoint, GridPoint)
        case marquee(GridRect)
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.textArea)
        setAccessibilityIdentifier("character-canvas")
        setAccessibilityLabel("Character canvas")
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wireFocus()
        window?.makeFirstResponder(self)
    }

    override func layout() {
        super.layout()
        model?.noteViewport(bounds.size)
    }

    override func resetCursorRects() {
        guard let model else { return }
        let cursor: NSCursor
        if model.editor.spaceHeld || model.editor.tool == .pan {
            cursor = .openHand
        } else if model.editor.tool == .select {
            cursor = .arrow
        } else {
            cursor = .crosshair
        }
        addCursorRect(bounds, cursor: cursor)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let model else { return }
        let background = NSColor.textBackgroundColor
        background.setFill()
        dirtyRect.fill()

        let cellW = model.cellWidth * model.zoom
        let cellH = model.cellHeight * model.zoom
        guard cellW > 0.5, cellH > 0.5 else { return }

        drawDots(model: model, cellW: cellW, cellH: cellH, clip: dirtyRect)
        let grid = model.editor.render()
        drawGrid(grid, model: model, cellW: cellW, cellH: cellH)
        drawSelection(model: model, cellW: cellW, cellH: cellH)
        drawDraft(model: model, cellW: cellW, cellH: cellH)
        drawGuides(model: model, cellW: cellW, cellH: cellH)
        setAccessibilityValue(grid.plainText)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let model else { return }
        let point = convert(event.locationInWindow, from: nil)
        let cell = cell(at: point, model: model)
        anchorCell = cell
        anchorPoint = point
        anchorScroll = CGPoint(x: model.scrollX, y: model.scrollY)
        model.hover = cell

        if event.modifierFlags.contains(.option), model.editor.activeTool == .select {
            addBorderPoint(at: cell, model: model)
            return
        }

        switch model.editor.activeTool {
        case .pan:
            window?.disableCursorRects()
            NSCursor.closedHand.set()
        case .pencil:
            model.editor.beginGesture(.accumulate)
            gesture = .accumulate
            painting = true
            model.editor.pencil(at: cell)
        case .eraser:
            model.editor.beginGesture(.accumulate)
            gesture = .accumulate
            painting = true
            model.editor.erase(at: cell)
        case .bucket:
            model.editor.bucketFill(at: cell)
        case .picker:
            _ = model.editor.pickCharacter(at: cell)
            model.editor.selectTool(.pencil)
        case .select:
            if let handle = hitHandle(at: point, model: model), let id = model.selection.first, let object = model.editor.object(id) {
                resizeHandle = handle
                originalFrame = object.frame
                if case .line = object.kind {
                    lineEndDrag = handle == .right || handle == .bottomRight || handle == .topRight
                }
                model.editor.beginGesture(.replace)
                gesture = .replace
            } else if let hit = model.editor.hitTest(cell) {
                if event.modifierFlags.contains(.shift) {
                    if model.selection.contains(hit) { model.selection.remove(hit) } else { model.selection.insert(hit) }
                } else if !model.selection.contains(hit) {
                    model.selection = [hit]
                }
                model.editor.beginGesture(.replace)
                gesture = .replace
            } else {
                if !event.modifierFlags.contains(.shift) { model.selection = [] }
                draft = .marquee(GridRect(x: cell.x, y: cell.y, width: 1, height: 1))
            }
        case .rect, .diamond, .text, .banner:
            draft = .shape(GridRect(x: cell.x, y: cell.y, width: 1, height: 1))
        case .line:
            draft = .line(cell, cell)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let model else { return }
        let point = convert(event.locationInWindow, from: nil)
        let cell = cell(at: point, model: model)
        model.hover = cell
        let tool = model.editor.activeTool

        if tool == .pan {
            model.scrollX = anchorScroll.x + Double(point.x - anchorPoint.x)
            model.scrollY = anchorScroll.y + Double(point.y - anchorPoint.y)
            return
        }
        if painting {
            if tool == .eraser { model.editor.erase(at: cell) } else { model.editor.pencil(at: cell) }
            return
        }
        if let handle = resizeHandle, let id = model.selection.first {
            if case .line(let props) = model.editor.object(id)?.kind {
                model.editor.setLine(id) { line in
                    if lineEndDrag {
                        line.end = cell
                        line.endAttachment = model.nearestAnchor(to: cell)
                    } else {
                        line.start = cell
                        line.startAttachment = model.nearestAnchor(to: cell)
                    }
                    _ = props
                }
            } else {
                let proposed = model.editor.resizedFrame(original: originalFrame, handle: handle, to: cell)
                model.guides = model.editor.resizeObject(id, to: proposed)
            }
            return
        }
        if gesture == .replace, tool == .select, !model.selection.isEmpty {
            let delta = GridPoint(x: cell.x - anchorCell.x, y: cell.y - anchorCell.y)
            model.guides = model.editor.moveObjects(Array(model.selection), by: delta)
            return
        }
        switch draft {
        case .shape:
            draft = .shape(GridRect.normalized(from: anchorCell, to: cell, minimum: 1))
        case .line:
            var end = cell
            if event.modifierFlags.contains(.shift) {
                if abs(cell.x - anchorCell.x) >= abs(cell.y - anchorCell.y) {
                    end.y = anchorCell.y
                } else {
                    end.x = anchorCell.x
                }
            }
            draft = .line(anchorCell, end)
        case .marquee:
            draft = .marquee(GridRect.normalized(from: anchorCell, to: cell, minimum: 1))
        case nil:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            if gesture != nil {
                model?.editor.endGesture()
                gesture = nil
            }
            painting = false
            resizeHandle = nil
            lineEndDrag = false
            draft = nil
            model?.guides = []
            window?.enableCursorRects()
            needsDisplay = true
        }
        guard let model else { return }
        let point = convert(event.locationInWindow, from: nil)
        let cell = cell(at: point, model: model)
        switch draft {
        case .shape(let rect):
            commitShape(rect, tool: model.editor.tool, model: model)
        case .line(let start, let end):
            commitLine(from: start, to: end == start ? GridPoint(x: end.x + 4, y: end.y) : end, model: model)
        case .marquee(let rect):
            let hits = model.editor.document.objects.filter { object in
                !object.hidden && framesIntersect(object.frame, rect)
            }.map(\.id)
            if event.modifierFlags.contains(.shift) {
                model.selection.formUnion(hits)
            } else {
                model.selection = Set(hits)
            }
        case nil:
            break
        }
        _ = cell
    }

    override func mouseMoved(with event: NSEvent) {
        guard let model else { return }
        let point = convert(event.locationInWindow, from: nil)
        model.hover = cell(at: point, model: model)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let model else { return }
        let point = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.command) {
            let factor = event.scrollingDeltaY > 0 ? 1.08 : 0.92
            model.zoom(by: factor, anchor: point)
        } else {
            model.scrollX += event.scrollingDeltaX
            model.scrollY -= event.scrollingDeltaY
        }
    }

    override func magnify(with event: NSEvent) {
        guard let model else { return }
        let point = convert(event.locationInWindow, from: nil)
        model.zoom(by: 1 + event.magnification, anchor: point)
    }

    override func keyDown(with event: NSEvent) {
        guard let model else { return super.keyDown(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)
        let option = flags.contains(.option)
        let control = flags.contains(.control)
        let shift = flags.contains(.shift)
        guard let character = event.charactersIgnoringModifiers?.first else {
            super.keyDown(with: event)
            return
        }
        if let action = KeyBinding.interpret(KeyChord(
            character: character,
            command: command,
            option: option,
            control: control,
            shift: shift
        )) {
            switch action {
            case .selectTool(let tool):
                model.editor.selectTool(tool)
            case .beginSpacePan:
                model.editor.beginSpacePan()
                resetCursorRects()
            }
            return
        }
        if command || option || control {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 51, 117:
            model.deleteSelection()
        case 123: model.nudgeSelection(dx: shift ? -4 : -1, dy: 0)
        case 124: model.nudgeSelection(dx: shift ? 4 : 1, dy: 0)
        case 125: model.nudgeSelection(dx: 0, dy: shift ? 4 : 1)
        case 126: model.nudgeSelection(dx: 0, dy: shift ? -4 : -1)
        case 53:
            model.selection = []
        default:
            break
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.charactersIgnoringModifiers?.first == " " {
            model?.editor.endSpacePan()
            resetCursorRects()
            return
        }
        super.keyUp(with: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    private func wireFocus() {
        model?.focusCanvas = { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    private func cell(at point: NSPoint, model: EditorModel) -> GridPoint {
        let cellW = model.cellWidth * model.zoom
        let cellH = model.cellHeight * model.zoom
        let x = Int(floor((point.x - model.scrollX) / cellW))
        let y = Int(floor((point.y - model.scrollY) / cellH))
        return GridPoint(x: x, y: y)
    }

    private func viewRect(_ frame: GridRect, model: EditorModel, cellW: Double, cellH: Double) -> NSRect {
        NSRect(
            x: model.scrollX + Double(frame.minX) * cellW,
            y: model.scrollY + Double(frame.minY) * cellH,
            width: Double(frame.width) * cellW,
            height: Double(frame.height) * cellH
        )
    }

    private func drawDots(model: EditorModel, cellW: Double, cellH: Double, clip: NSRect) {
        let minX = Int(floor((clip.minX - model.scrollX) / cellW)) - 1
        let maxX = Int(ceil((clip.maxX - model.scrollX) / cellW)) + 1
        let minY = Int(floor((clip.minY - model.scrollY) / cellH)) - 1
        let maxY = Int(ceil((clip.maxY - model.scrollY) / cellH)) + 1
        NSColor.tertiaryLabelColor.withAlphaComponent(0.55).setFill()
        let radius = max(0.6, min(cellW, cellH) * 0.06)
        for y in minY...maxY {
            for x in minX...maxX {
                let cx = model.scrollX + (Double(x) + 0.5) * cellW
                let cy = model.scrollY + (Double(y) + 0.5) * cellH
                NSBezierPath(ovalIn: NSRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)).fill()
            }
        }
    }

    private func drawGrid(_ grid: RenderedGrid, model: EditorModel, cellW: Double, cellH: Double) {
        let fontSize = max(6, cellH * 0.72)
        let font = NSFont(name: "Menlo", size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style,
        ]
        for (rowIndex, row) in grid.rows.enumerated() {
            let y = grid.minY + rowIndex
            let viewY = model.scrollY + Double(y) * cellH
            if viewY > bounds.maxY || viewY + cellH < bounds.minY { continue }
            for (columnIndex, character) in row.enumerated() {
                if character == " " { continue }
                let x = grid.minX + columnIndex
                let rect = NSRect(
                    x: model.scrollX + Double(x) * cellW,
                    y: viewY,
                    width: cellW,
                    height: cellH
                )
                if rect.maxX < bounds.minX || rect.minX > bounds.maxX { continue }
                (String(character) as NSString).draw(in: rect, withAttributes: attributes)
            }
        }
    }

    private func drawSelection(model: EditorModel, cellW: Double, cellH: Double) {
        NSColor.controlAccentColor.setStroke()
        for id in model.selection {
            guard let object = model.editor.object(id), !object.hidden else { continue }
            let rect = viewRect(object.frame, model: model, cellW: cellW, cellH: cellH)
            let path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1.5
            path.stroke()
            if model.selection.count == 1, !object.locked {
                if case .line(let props) = object.kind {
                    drawHandle(at: point(props.start, model: model, cellW: cellW, cellH: cellH))
                    drawHandle(at: point(props.end, model: model, cellW: cellW, cellH: cellH))
                } else {
                    for handle in ResizeHandle.allCases {
                        drawHandle(at: handlePoint(handle, rect: rect))
                    }
                }
            }
        }
    }

    private func drawHandle(at center: NSPoint) {
        let size: CGFloat = 7
        let rect = NSRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        NSColor.textBackgroundColor.setFill()
        NSBezierPath(rect: rect).fill()
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1.5
        path.stroke()
    }

    private func drawDraft(model: EditorModel, cellW: Double, cellH: Double) {
        NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
        switch draft {
        case .shape(let frame), .marquee(let frame):
            let path = NSBezierPath(rect: viewRect(frame, model: model, cellW: cellW, cellH: cellH))
            path.lineWidth = 1
            path.setLineDash([4, 3], count: 2, phase: 0)
            path.stroke()
        case .line(let start, let end):
            let path = NSBezierPath()
            path.move(to: point(start, model: model, cellW: cellW, cellH: cellH))
            if model.editor.tool == .line {
                let elbow = GridPoint(x: end.x, y: start.y)
                path.line(to: point(elbow, model: model, cellW: cellW, cellH: cellH))
            }
            path.line(to: point(end, model: model, cellW: cellW, cellH: cellH))
            path.lineWidth = 1.5
            path.stroke()
        case nil:
            break
        }
    }

    private func drawGuides(model: EditorModel, cellW: Double, cellH: Double) {
        for guide in model.guides {
            let path = NSBezierPath()
            if guide.kind == .center {
                path.setLineDash([2, 3], count: 2, phase: 0)
                NSColor.systemOrange.setStroke()
            } else {
                NSColor.controlAccentColor.setStroke()
            }
            switch guide.axis {
            case .vertical:
                let x = model.scrollX + Double(guide.position) * cellW
                path.move(to: NSPoint(x: x, y: 0))
                path.line(to: NSPoint(x: x, y: bounds.height))
            case .horizontal:
                let y = model.scrollY + Double(guide.position) * cellH
                path.move(to: NSPoint(x: 0, y: y))
                path.line(to: NSPoint(x: bounds.width, y: y))
            }
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func point(_ cell: GridPoint, model: EditorModel, cellW: Double, cellH: Double) -> NSPoint {
        NSPoint(
            x: model.scrollX + (Double(cell.x) + 0.5) * cellW,
            y: model.scrollY + (Double(cell.y) + 0.5) * cellH
        )
    }

    private func handlePoint(_ handle: ResizeHandle, rect: NSRect) -> NSPoint {
        switch handle {
        case .topLeft: return NSPoint(x: rect.minX, y: rect.minY)
        case .top: return NSPoint(x: rect.midX, y: rect.minY)
        case .topRight: return NSPoint(x: rect.maxX, y: rect.minY)
        case .left: return NSPoint(x: rect.minX, y: rect.midY)
        case .right: return NSPoint(x: rect.maxX, y: rect.midY)
        case .bottomLeft: return NSPoint(x: rect.minX, y: rect.maxY)
        case .bottom: return NSPoint(x: rect.midX, y: rect.maxY)
        case .bottomRight: return NSPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    private func hitHandle(at point: NSPoint, model: EditorModel) -> ResizeHandle? {
        guard model.selection.count == 1, let id = model.selection.first, let object = model.editor.object(id), !object.locked else {
            return nil
        }
        let cellW = model.cellWidth * model.zoom
        let cellH = model.cellHeight * model.zoom
        if case .line(let props) = object.kind {
            let start = self.point(props.start, model: model, cellW: cellW, cellH: cellH)
            let end = self.point(props.end, model: model, cellW: cellW, cellH: cellH)
            if hypot(point.x - end.x, point.y - end.y) <= 8 { return .right }
            if hypot(point.x - start.x, point.y - start.y) <= 8 { return .left }
            return nil
        }
        let rect = viewRect(object.frame, model: model, cellW: cellW, cellH: cellH)
        for handle in ResizeHandle.allCases.reversed() {
            let center = handlePoint(handle, rect: rect)
            if hypot(point.x - center.x, point.y - center.y) <= 8 { return handle }
        }
        return nil
    }

    private func commitShape(_ raw: GridRect, tool: Tool, model: EditorModel) {
        let frame: GridRect
        if raw.width < 2 || raw.height < 2 {
            switch tool {
            case .text: frame = GridRect(x: raw.x, y: raw.y, width: 16, height: 3)
            case .banner: frame = GridRect(x: raw.x, y: raw.y, width: 24, height: 6)
            case .diamond: frame = GridRect(x: raw.x, y: raw.y, width: 7, height: 5)
            default: frame = GridRect(x: raw.x, y: raw.y, width: 10, height: 5)
            }
        } else {
            frame = raw
        }
        let id: UUID
        switch tool {
        case .rect:
            id = model.editor.addRectangle(frame: frame, border: .single, fill: nil, shadow: nil)
        case .diamond:
            id = model.editor.addDiamond(frame: frame)
        case .text:
            id = model.editor.addText(frame: frame, text: "Text")
        case .banner:
            id = model.editor.addBanner(frame: frame, text: "HI", fontName: "standard", alignment: .left)
        default:
            return
        }
        model.selection = [id]
        model.editor.selectTool(.select)
    }

    private func commitLine(from start: GridPoint, to end: GridPoint, model: EditorModel) {
        var props = LineProps(start: start, end: end, routing: .orthogonal, horizontalFirst: true)
        props.startAttachment = model.nearestAnchor(to: start)
        props.endAttachment = model.nearestAnchor(to: end)
        let id = model.editor.addLine(props)
        model.selection = [id]
        model.editor.selectTool(.select)
    }

    private func addBorderPoint(at cell: GridPoint, model: EditorModel) {
        guard let hit = model.editor.hitTest(cell), let object = model.editor.object(hit), case .rectangle = object.kind else { return }
        var best: (dist: Int, edge: RectEdge, t: Double)?
        for edge in RectEdge.allCases {
            let projected = model.project(cell, onto: edge, frame: object.frame)
            let dist = max(abs(projected.point.x - cell.x), abs(projected.point.y - cell.y))
            if best == nil || dist < best!.dist {
                best = (dist, edge, projected.t)
            }
        }
        guard let best, best.dist <= 1, let id = model.editor.addBorderPoint(hit, edge: best.edge, t: best.t) else { return }
        _ = id
        model.selection = [hit]
    }

    private func framesIntersect(_ lhs: GridRect, _ rhs: GridRect) -> Bool {
        lhs.minX < rhs.maxX && rhs.minX < lhs.maxX && lhs.minY < rhs.maxY && rhs.minY < lhs.maxY
    }
}
