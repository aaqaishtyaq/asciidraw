import AsciiDrawCore
import AppKit
import SwiftUI

/// Monodraw's canvas is white with a #ebebeb line on each cell edge.
/// Dark mode uses the same weight: a light hairline on the dark paper.
private enum CanvasPaper {
    static let grid = NSColor(name: NSColor.Name("AsciiDrawCanvasGrid"), dynamicProvider: { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if dark {
            return NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.14)
        }
        return NSColor(srgbRed: 235 / 255, green: 235 / 255, blue: 235 / 255, alpha: 1)
    })
}

struct CanvasRepresentable: NSViewRepresentable {
    @ObservedObject var model: EditorModel

    func makeNSView(context: Context) -> DiagramCanvasView {
        let view = DiagramCanvasView()
        view.model = model
        return view
    }

    func updateNSView(_ view: DiagramCanvasView, context: Context) {
        view.model = model
        // Hover updates the status readout on every move. Redrawing the whole
        // cell field for that, at 20% zoom, is what makes the canvas stall.
        if view.drawnPicture != model.picture {
            view.drawnPicture = model.picture
            view.needsDisplay = true
            view.resetCursorRects()
        }
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
    private var trackingMouse = false
    var drawnPicture = -1
    private var cachedContent = -1
    private var cachedGrid: RenderedGrid?

    /// Pinned gutters. Row numbers run down the left, column numbers across the top.
    /// Wide enough for a three-digit row number in the canvas font.
    private let rowRulerWidth: CGFloat = 42
    /// One grid row at 100%. Column numbers then share the canvas line height.
    private let columnRulerHeight: CGFloat = 22

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
        } else if model.textEdit != nil {
            cursor = .iBeam
        } else if model.editor.tool == .select {
            cursor = .arrow
        } else {
            cursor = .crosshair
        }
        addCursorRect(bounds, cursor: cursor)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            drawCanvas(dirtyRect)
        }
    }

    private func drawCanvas(_ dirtyRect: NSRect) {
        guard let model else { return }
        let background = NSColor.textBackgroundColor
        background.setFill()
        dirtyRect.fill()

        let cellW = model.cellWidth * model.zoom
        let cellH = model.cellHeight * model.zoom
        guard cellW > 0.5, cellH > 0.5 else { return }

        let grid = renderedGrid(for: model)
        NSGraphicsContext.saveGraphicsState()
        NSRect(
            x: rowRulerWidth,
            y: columnRulerHeight,
            width: max(0, bounds.width - rowRulerWidth),
            height: max(0, bounds.height - columnRulerHeight)
        ).clip()
        drawPaper(model: model, cellW: cellW, cellH: cellH, clip: dirtyRect)
        drawGrid(grid, model: model, cellW: cellW, cellH: cellH, clip: dirtyRect)
        drawSelection(model: model, cellW: cellW, cellH: cellH)
        drawTextCaret(model: model, cellW: cellW, cellH: cellH)
        drawDraft(model: model, cellW: cellW, cellH: cellH)
        drawGuides(model: model, cellW: cellW, cellH: cellH)
        NSGraphicsContext.restoreGraphicsState()
        drawRulers(model: model, cellW: cellW, cellH: cellH)
    }

    private func renderedGrid(for model: EditorModel) -> RenderedGrid {
        if cachedContent == model.contentPicture, let cachedGrid { return cachedGrid }
        let grid = model.editor.render()
        cachedContent = model.contentPicture
        cachedGrid = grid
        setAccessibilityValue(grid.plainText)
        return grid
    }

    private func isOnRuler(_ point: NSPoint) -> Bool {
        point.x < rowRulerWidth || point.y < columnRulerHeight
    }

    override func mouseDown(with event: NSEvent) {
        if clickLandsOnChrome(event) {
            trackingMouse = false
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        if isOnRuler(point) {
            trackingMouse = false
            window?.makeFirstResponder(self)
            return
        }
        trackingMouse = true
        window?.makeFirstResponder(self)
        guard let model else { return }
        let cell = cell(at: point, model: model)
        anchorCell = cell
        anchorPoint = point
        anchorScroll = CGPoint(x: model.scrollX, y: model.scrollY)
        model.hover = cell

        if model.textEdit != nil {
            if model.textEditContains(cell) {
                model.placeTextCaret(at: cell)
                trackingMouse = false
                return
            }
            model.commitTextEdit(discardIfEmpty: true)
        }
        if event.clickCount >= 2, model.editor.activeTool == .select {
            if let hit = model.editor.hitTest(cell),
               let object = model.editor.object(hit),
               case .text = object.kind,
               !object.locked {
                model.beginEditingText(hit, at: cell)
                trackingMouse = false
                return
            }
            if model.editor.hitTest(cell) == nil {
                model.insertText(at: cell)
                trackingMouse = false
                return
            }
        }

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
        case .rect, .surface, .diamond, .text, .banner:
            draft = .shape(GridRect(x: cell.x, y: cell.y, width: 1, height: 1))
        case .line:
            draft = .line(cell, cell)
        }
        needsDisplay = true
    }

    /// The floating bar sits above the canvas. A click there must not start a canvas gesture.
    private func clickLandsOnChrome(_ event: NSEvent) -> Bool {
        guard let content = window?.contentView else { return false }
        var view = content.hitTest(event.locationInWindow)
        while let current = view {
            if current.identifier?.rawValue == "canvas-chrome" { return true }
            view = current.superview
        }
        return false
    }

    override func mouseDragged(with event: NSEvent) {
        guard trackingMouse, let model else { return }
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
        guard trackingMouse else { return }
        defer {
            trackingMouse = false
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
        if isOnRuler(point) { return }
        let cell = cell(at: point, model: model)
        if model.hover != cell { model.hover = cell }
    }

    override func scrollWheel(with event: NSEvent) {
        guard let model else { return }
        let point = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.command) {
            let factor = event.scrollingDeltaY > 0 ? 1.08 : 0.92
            model.zoom(by: factor, anchor: point)
        } else {
            model.scrollX += event.scrollingDeltaX
            model.scrollY += event.scrollingDeltaY
        }
    }

    override func magnify(with event: NSEvent) {
        guard let model else { return }
        let point = convert(event.locationInWindow, from: nil)
        model.zoom(by: 1 + event.magnification, anchor: point)
    }

    override func keyDown(with event: NSEvent) {
        guard let model else { return super.keyDown(with: event) }
        if model.textEdit != nil {
            handleTextKey(event, model: model)
            return
        }
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
        if model?.textEdit != nil { return }
        if event.charactersIgnoringModifiers?.first == " " {
            model?.editor.endSpacePan()
            resetCursorRects()
            return
        }
        super.keyUp(with: event)
    }

    private func handleTextKey(_ event: NSEvent, model: EditorModel) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.control) {
            model.commitTextEdit(discardIfEmpty: false)
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 53:
            model.commitTextEdit(discardIfEmpty: true)
            model.selection = []
        case 36, 76:
            model.insertText("\n")
        case 51:
            model.deleteTextBackward()
        case 117:
            model.deleteTextForward()
        case 123:
            model.moveTextCaret(columns: -1)
        case 124:
            model.moveTextCaret(columns: 1)
        case 125:
            model.moveTextCaret(lines: 1)
        case 126:
            model.moveTextCaret(lines: -1)
        case 48:
            break
        default:
            guard let chars = event.characters, !chars.isEmpty else { return }
            if chars.unicodeScalars.contains(where: { $0.value < 32 }) { return }
            model.insertText(chars)
        }
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

    /// Column and row indexes are stored from zero. The ruler shows them from one, like Monodraw.
    private func drawRulers(model: EditorModel, cellW: Double, cellH: Double) {
        let left = rowRulerWidth
        let top = columnRulerHeight
        NSColor.windowBackgroundColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: top).fill()
        NSRect(x: 0, y: 0, width: left, height: bounds.height).fill()

        NSColor.separatorColor.setStroke()
        let border = NSBezierPath()
        border.move(to: NSPoint(x: left, y: top))
        border.line(to: NSPoint(x: bounds.width, y: top))
        border.move(to: NSPoint(x: left, y: top))
        border.line(to: NSPoint(x: left, y: bounds.height))
        border.lineWidth = 1
        border.stroke()

        // Monodraw keeps the ruler type one size. Zoom changes how many cells
        // you see, not how big the numbers are. A number scaled with the cell
        // is clipped at the ruler when zoomed in, and clipped to nothing when
        // the cell is shorter than the glyph.
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let tickColor = NSColor.tertiaryLabelColor
        let sample = ("000" as NSString).size(withAttributes: attributes)
        let labelPitch = sample.height + 2

        let columnStep = rulerStep(span: cellW, minimum: sample.width + 8)
        let firstColumn = Int(floor((Double(left) - model.scrollX) / cellW)) - 1
        let lastColumn = Int(ceil((bounds.maxX - model.scrollX) / cellW)) + 1
        // A tick on every column at 20% zoom is a solid bar, and hundreds of strokes.
        let dense = cellW < 4
        let ticks = NSBezierPath()
        for index in firstColumn...lastColumn {
            let edge = model.scrollX + Double(index) * cellW
            guard edge >= Double(left) - 0.5, edge <= bounds.maxX + 0.5 else { continue }
            let number = index + 1
            let labeled = number % columnStep == 0
            let medium = number % max(1, columnStep / 2) == 0
            if dense && !medium { continue }
            let tick = labeled ? top * 0.55 : (medium ? top * 0.35 : top * 0.2)
            ticks.move(to: NSPoint(x: edge, y: top - tick))
            ticks.line(to: NSPoint(x: edge, y: top))
            if labeled {
                let label = "\(number)" as NSString
                let size = label.size(withAttributes: attributes)
                // Tick on the column line. The digits sit just to its right,
                // centered in the ruler, which is one row tall at 100%.
                let rect = NSRect(
                    x: edge + 2,
                    y: (top - size.height) / 2,
                    width: size.width,
                    height: size.height
                )
                if rect.maxX < bounds.maxX && rect.minX > left {
                    label.draw(in: rect, withAttributes: attributes)
                }
            }
        }
        tickColor.setStroke()
        ticks.lineWidth = 1
        ticks.stroke()

        let rowStep = rulerStep(span: cellH, minimum: labelPitch)
        let firstRow = Int(floor((Double(top) - model.scrollY) / cellH)) - 1
        let lastRow = Int(ceil((bounds.maxY - model.scrollY) / cellH)) + 1
        for index in firstRow...lastRow {
            let edge = model.scrollY + Double(index) * cellH
            guard edge + cellH > Double(top), edge < bounds.maxY else { continue }
            let number = index + 1
            guard number % rowStep == 0 else { continue }
            let label = "\(number)" as NSString
            let size = label.size(withAttributes: attributes)
            // Centered on the row, so the digits line up with that line of the grid.
            let rect = NSRect(
                x: left - size.width - 6,
                y: edge + (cellH - size.height) / 2,
                width: size.width,
                height: size.height
            )
            guard rect.minX >= 1, rect.minY >= top, rect.maxY <= bounds.maxY else { continue }
            label.draw(in: rect, withAttributes: attributes)
        }
    }

    /// Smallest 1/2/5/10… step whose labels do not collide at this cell size.
    private func rulerStep(span: Double, minimum: Double) -> Int {
        for step in [1, 2, 5, 10, 20, 50, 100] where Double(step) * span >= minimum {
            return step
        }
        return 100
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

    /// Graph paper, the same idea as Monodraw: white cells, one light line on
    /// every cell edge. One stroke for the whole visible field. At 20% a dot per
    /// cell was about a hundred thousand fills; the lines are a few hundred.
    private func drawPaper(model: EditorModel, cellW: Double, cellH: Double, clip: NSRect) {
        let minX = Int(floor((clip.minX - model.scrollX) / cellW)) - 1
        let maxX = Int(ceil((clip.maxX - model.scrollX) / cellW)) + 1
        let minY = Int(floor((clip.minY - model.scrollY) / cellH)) - 1
        let maxY = Int(ceil((clip.maxY - model.scrollY) / cellH)) + 1
        guard minX <= maxX, minY <= maxY else { return }
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        // A 1pt line on a 12×22 cell matches the weight of Monodraw's grid.
        // Zoomed out, a full point would fill the cell, so the stroke thins
        // down to one pixel and skips edges that would sit on top of each other.
        let scale = window?.backingScaleFactor ?? 2
        let hairline = 1 / scale
        let lineWidth = min(cellW, cellH) >= 8 ? 1.0 : hairline
        let strideX = max(1, Int((lineWidth / cellW).rounded(.up)))
        let strideY = max(1, Int((lineWidth / cellH).rounded(.up)))
        let startX = minX - alignedRemainder(minX, strideX)
        let startY = minY - alignedRemainder(minY, strideY)
        cg.saveGState()
        let ink = (CanvasPaper.grid.usingColorSpace(.sRGB) ?? CanvasPaper.grid)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        ink.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        cg.setStrokeColor(red: red, green: green, blue: blue, alpha: alpha)
        cg.setLineWidth(lineWidth)
        cg.beginPath()
        var x = startX
        while x <= maxX + 1 {
            let edge = model.scrollX + Double(x) * cellW
            cg.move(to: CGPoint(x: edge, y: clip.minY))
            cg.addLine(to: CGPoint(x: edge, y: clip.maxY))
            x += strideX
        }
        var y = startY
        while y <= maxY + 1 {
            let edge = model.scrollY + Double(y) * cellH
            cg.move(to: CGPoint(x: clip.minX, y: edge))
            cg.addLine(to: CGPoint(x: clip.maxX, y: edge))
            y += strideY
        }
        cg.strokePath()
        cg.restoreGState()
    }

    private func alignedRemainder(_ value: Int, _ step: Int) -> Int {
        let remainder = value % step
        if remainder >= 0 { return remainder }
        return remainder + step
    }

    private func drawGrid(_ grid: RenderedGrid, model: EditorModel, cellW: Double, cellH: Double, clip: NSRect) {
        // At a normal size each glyph is centered in its cell. Zoomed out, that
        // is one text layout per character across the whole window, and the old
        // 6pt floor paints glyphs larger than the cell. A fitted line is one layout.
        if cellH < 10 || cellW < 6 {
            drawGridLines(grid, model: model, cellW: cellW, cellH: cellH, clip: clip)
        } else {
            drawGridCells(grid, model: model, cellW: cellW, cellH: cellH, clip: clip)
        }
    }

    private func drawGridCells(_ grid: RenderedGrid, model: EditorModel, cellW: Double, cellH: Double, clip: NSRect) {
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
            if viewY > clip.maxY || viewY + cellH < clip.minY { continue }
            for (columnIndex, character) in row.enumerated() {
                if character == " " { continue }
                let x = grid.minX + columnIndex
                let rect = NSRect(
                    x: model.scrollX + Double(x) * cellW,
                    y: viewY,
                    width: cellW,
                    height: cellH
                )
                if rect.maxX < clip.minX || rect.minX > clip.maxX { continue }
                (String(character) as NSString).draw(in: rect, withAttributes: attributes)
            }
        }
    }

    private func drawGridLines(_ grid: RenderedGrid, model: EditorModel, cellW: Double, cellH: Double, clip: NSRect) {
        guard grid.columnCount > 0 else { return }
        let unit = menloAdvance(at: 100) / 100
        guard unit > 0 else { return }
        let fontSize = max(0.5, min(cellH * 0.72, cellW / Double(unit)))
        let font = NSFont(name: "Menlo", size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let advance = menloAdvance(at: fontSize)
        let style = NSMutableParagraphStyle()
        style.alignment = .left
        style.lineBreakMode = .byClipping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style,
            .kern: CGFloat(cellW) - advance,
        ]
        let firstRow = max(grid.minY, Int(floor((clip.minY - model.scrollY) / cellH)) - 1)
        let lastRow = min(grid.minY + grid.rowCount - 1, Int(ceil((clip.maxY - model.scrollY) / cellH)) + 1)
        let firstCol = max(grid.minX, Int(floor((clip.minX - model.scrollX) / cellW)) - 1)
        let lastCol = min(grid.minX + grid.columnCount - 1, Int(ceil((clip.maxX - model.scrollX) / cellW)) + 1)
        guard firstRow <= lastRow, firstCol <= lastCol else { return }
        for y in firstRow...lastRow {
            let row = grid.rows[y - grid.minY]
            guard let line = visibleLine(row, gridMinX: grid.minX, firstCol: firstCol, lastCol: lastCol) else { continue }
            let viewY = model.scrollY + Double(y) * cellH
            let rect = NSRect(
                x: model.scrollX + Double(line.column) * cellW + (cellW - Double(advance)) / 2,
                y: viewY,
                width: Double(line.text.count) * cellW + cellW,
                height: cellH
            )
            (line.text as NSString).draw(in: rect, withAttributes: attributes)
        }
    }

    private func menloAdvance(at size: CGFloat) -> CGFloat {
        let font = NSFont(name: "Menlo", size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        return ("0" as NSString).size(withAttributes: [.font: font]).width
    }

    /// The visible slice of a row, with blank ends removed. Nil when nothing is inked.
    private func visibleLine(_ row: String, gridMinX: Int, firstCol: Int, lastCol: Int) -> (column: Int, text: String)? {
        let start = max(0, firstCol - gridMinX)
        let end = min(row.count, lastCol - gridMinX + 1)
        guard start < end else { return nil }
        let lower = row.index(row.startIndex, offsetBy: start)
        let upper = row.index(lower, offsetBy: end - start)
        var sliceStart = lower
        var sliceEnd = upper
        while sliceStart < sliceEnd && row[sliceStart] == " " {
            sliceStart = row.index(after: sliceStart)
        }
        while sliceEnd > sliceStart && row[row.index(before: sliceEnd)] == " " {
            sliceEnd = row.index(before: sliceEnd)
        }
        guard sliceStart < sliceEnd else { return nil }
        let skipped = row.distance(from: lower, to: sliceStart)
        return (gridMinX + start + skipped, String(row[sliceStart..<sliceEnd]))
    }

    private func drawSelection(model: EditorModel, cellW: Double, cellH: Double) {
        NSColor.controlAccentColor.setStroke()
        for id in model.selection {
            guard let object = model.editor.object(id), !object.hidden else { continue }
            let rect = viewRect(object.frame, model: model, cellW: cellW, cellH: cellH)
            let path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1.5
            path.stroke()
            if model.selection.count == 1, !object.locked, model.textEdit?.id != id {
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

    private func drawTextCaret(model: EditorModel, cellW: Double, cellH: Double) {
        guard let session = model.textEdit,
              let object = model.editor.object(session.id),
              case .text(let props) = object.kind else { return }
        let caret = min(session.caret, props.text.count)
        let cell = TextCaret.cell(text: props.text, index: caret, frame: object.frame, props: props)
        let rect = viewRect(GridRect(x: cell.x, y: cell.y, width: 1, height: 1), model: model, cellW: cellW, cellH: cellH)
        let width = max(1, min(2, cellW * 0.16))
        let bar = NSRect(x: rect.minX + 0.5, y: rect.minY + 1, width: width, height: max(1, rect.height - 2))
        NSColor.controlAccentColor.setFill()
        bar.fill()
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
        case .surface:
            let glyph = String(model.editor.pencilCharacter)
            let fill = glyph == " " ? "░" : glyph
            id = model.editor.addRectangle(frame: frame, border: nil, fill: fill, name: "Surface")
        case .diamond:
            id = model.editor.addDiamond(frame: frame)
        case .text:
            let clicked = raw.width < 2 && raw.height < 2
            let box = clicked ? GridRect(x: raw.x, y: raw.y, width: 1, height: 1) : frame
            model.openTextGesture()
            let createdID = model.editor.addText(frame: box, text: clicked ? "" : "Text")
            model.adoptTextEdit(createdID, created: clicked, minimumFrame: clicked ? nil : box)
            model.selection = [createdID]
            model.editor.selectTool(.select)
            return
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
