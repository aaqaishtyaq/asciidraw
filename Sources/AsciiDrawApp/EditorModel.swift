import AsciiDrawCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension Tool {
    var symbolName: String {
        switch self {
        case .select: return "cursorarrow"
        case .rect: return "rectangle"
        case .diamond: return "diamond"
        case .text: return "textformat"
        case .surface: return "square.grid.3x3.fill"
        case .line: return "line.diagonal"
        case .pencil: return "pencil"
        case .eraser: return "eraser"
        case .bucket: return "paintbrush.pointed.fill"
        case .picker: return "eyedropper"
        case .banner: return "bold"
        case .pan: return "hand.raised"
        }
    }

    var toolbarLabel: String {
        switch self {
        case .select: return "Select"
        case .pan: return "Pan"
        case .rect: return "Rect"
        case .text: return "Text"
        case .surface: return "Surface"
        case .diamond: return "Diamond"
        case .line: return "Line"
        case .banner: return "Banner"
        case .pencil: return "Pencil"
        case .bucket: return "Bucket"
        case .picker: return "Picker"
        case .eraser: return "Eraser"
        }
    }

    var shortcutLabel: String {
        guard let key = ToolShortcut.map.first(where: { $0.1 == self })?.0 else { return "" }
        return String(key).uppercased()
    }
}

@MainActor
final class EditorModel: ObservableObject {
    @Published var editor: Editor {
        didSet {
            notePicture(content: true)
            refreshDirty()
        }
    }
    @Published var selection: Set<UUID> = [] {
        didSet {
            notePicture(content: false)
            guard !committingText, let id = textEdit?.id, selection != [id] else { return }
            commitTextEdit(discardIfEmpty: true)
        }
    }
    @Published var guides: [SnapGuide] = [] {
        didSet { notePicture(content: false) }
    }
    @Published var scrollX: Double = 72 {
        didSet { notePicture(content: false) }
    }
    @Published var scrollY: Double = 48 {
        didSet { notePicture(content: false) }
    }
    @Published var zoom: Double = 1 {
        didSet { notePicture(content: false) }
    }
    @Published var fileURL: URL?
    @Published var hover = GridPoint(x: 0, y: 0)
    @Published var viewport = CGSize(width: 1100, height: 720)
    @Published var textEdit: TextSession? {
        didSet { notePicture(content: false) }
    }
    @Published private(set) var isDirty = false

    /// Bumps when the canvas picture changes. Hover updates the status line and does not bump it.
    private(set) var picture: Int = 0
    /// Bumps only when the rendered characters change, so scrolling can reuse the grid.
    private(set) var contentPicture: Int = 0

    private func notePicture(content: Bool) {
        if content { contentPicture &+= 1 }
        picture &+= 1
    }

    let cellWidth: Double = 12
    let cellHeight: Double = 22
    var focusCanvas: (() -> Void)?
    private var didFit = false
    private var savedDocument = Document()
    private var committingText = false

    init(editor: Editor = Editor()) {
        self.editor = editor
        savedDocument = editor.document
    }

    struct TextSession: Equatable {
        var id: UUID
        var caret: Int
        var columnHint: Int
        /// Created by this edit. An empty one is removed when editing ends.
        var created: Bool
        /// Nil grows and shrinks with the typed text. A value is the box the user already drew.
        var minimumFrame: GridRect?
    }

    var documentTitle: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }

    var layers: [DrawObject] {
        editor.document.objects.sorted { lhs, rhs in
            if lhs.zIndex != rhs.zIndex { return lhs.zIndex > rhs.zIndex }
            return lhs.name < rhs.name
        }
    }

    func focusDrawing() {
        focusCanvas?()
    }

    func selectTool(_ tool: Tool) {
        editor.selectTool(tool)
        focusDrawing()
    }

    func noteViewport(_ size: CGSize) {
        guard size.width > 80, size.height > 80 else { return }
        if abs(viewport.width - size.width) > 1 || abs(viewport.height - size.height) > 1 {
            viewport = size
        }
        fitIfNeeded()
    }

    func fitIfNeeded() {
        guard !didFit else { return }
        didFit = true
        zoomToFit()
    }

    func zoomToFit() {
        guard let fit = editor.fitVisible(
            viewportWidth: viewport.width,
            viewportHeight: viewport.height,
            cellWidth: cellWidth,
            cellHeight: cellHeight,
            padding: 36,
            minZoom: 0.2,
            maxZoom: 6
        ) else { return }
        zoom = fit.zoom
        scrollX = fit.scrollX
        scrollY = fit.scrollY
    }

    func zoom(by factor: Double, anchor: CGPoint) {
        let old = zoom
        let new = min(6, max(0.2, old * factor))
        guard new != old, old > 0 else { return }
        let cellX = (anchor.x - scrollX) / (cellWidth * old)
        let cellY = (anchor.y - scrollY) / (cellHeight * old)
        zoom = new
        scrollX = anchor.x - cellX * cellWidth * new
        scrollY = anchor.y - cellY * cellHeight * new
    }

    var viewportCenter: CGPoint {
        CGPoint(x: viewport.width / 2, y: viewport.height / 2)
    }

    func setZoom(_ newValue: Double) {
        let anchor = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        let factor = min(6, max(0.2, newValue)) / zoom
        zoom(by: factor, anchor: anchor)
    }

    func undo() {
        commitTextEdit(discardIfEmpty: false)
        _ = editor.undo()
        guides = []
    }

    func redo() {
        commitTextEdit(discardIfEmpty: false)
        _ = editor.redo()
        guides = []
    }

    func deleteSelection() {
        commitTextEdit(discardIfEmpty: false)
        guard !selection.isEmpty else { return }
        editor.deleteObjects(Array(selection))
        selection = []
        guides = []
    }

    func duplicateSelection() {
        let ids = Array(selection)
        guard !ids.isEmpty else { return }
        let before = Set(editor.document.objects.map(\.id))
        if let group = editor.document.groups.first(where: { Set($0.memberIDs) == Set(ids) }) {
            _ = editor.duplicateGroup(group.id, offset: GridPoint(x: 2, y: 2))
        } else {
            _ = editor.duplicateObjects(ids, offset: GridPoint(x: 2, y: 2))
        }
        let after = Set(editor.document.objects.map(\.id))
        let created = after.subtracting(before)
        if !created.isEmpty { selection = created }
    }

    func groupSelection() {
        guard let id = editor.group(Array(selection)) else { return }
        if let group = editor.document.groups.first(where: { $0.id == id }) {
            selection = Set(group.memberIDs)
        }
    }

    func ungroupSelection() {
        let groupIDs = Set(selection.compactMap { editor.object($0)?.groupID })
        for id in groupIDs {
            editor.ungroup(id)
        }
    }

    func alignSelection(_ edge: AlignEdge) {
        editor.align(Array(selection), to: edge)
    }

    func distributeSelection(_ axis: DistributeAxis) {
        editor.distribute(Array(selection), along: axis)
    }

    func bringSelectionToFront() {
        editor.bringToFront(Array(selection))
    }

    func sendSelectionToBack() {
        editor.sendToBack(Array(selection))
    }

    func toggleLockSelection() {
        let ids = Array(selection)
        guard !ids.isEmpty else { return }
        let lock = ids.contains { editor.object($0)?.locked == false }
        editor.setLocked(ids, lock)
    }

    func toggleHiddenSelection() {
        let ids = Array(selection)
        guard !ids.isEmpty else { return }
        let hide = ids.contains { editor.object($0)?.hidden == false }
        editor.setHidden(ids, hide)
    }

    var selectionLocked: Bool {
        !selection.isEmpty && selection.allSatisfy { editor.object($0)?.locked == true }
    }

    var selectionHidden: Bool {
        !selection.isEmpty && selection.allSatisfy { editor.object($0)?.hidden == true }
    }

    func nudgeSelection(dx: Int, dy: Int) {
        guard !selection.isEmpty else { return }
        guides = editor.moveObjects(Array(selection), by: GridPoint(x: dx, y: dy))
        guides = []
    }

    func toggleLock(_ id: UUID) {
        guard let object = editor.object(id) else { return }
        editor.setLocked(id, !object.locked)
    }

    func toggleHidden(_ id: UUID) {
        guard let object = editor.object(id) else { return }
        editor.setHidden(id, !object.hidden)
    }

    func copyPlainText() {
        let text = editor.exportPlainText()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func newDocument() {
        guard confirmDiscardIfNeeded() else { return }
        editor = Editor()
        selection = []
        guides = []
        fileURL = nil
        markClean()
        showBlankCanvas()
    }

    /// Save, drop, or keep the open diagram. Cancel returns false.
    func confirmDiscardIfNeeded() -> Bool {
        commitTextEdit(discardIfEmpty: true)
        guard isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes to \(documentTitle)?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            save()
            return !isDirty
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    func openDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.fileType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = fileURL?.deletingLastPathComponent() ?? LibraryStore.shared.folder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url: url)
    }

    func open(url: URL, prompting: Bool = true) {
        let standard = url.standardizedFileURL
        if fileURL?.standardizedFileURL == standard { return }
        if prompting, !confirmDiscardIfNeeded() { return }
        do {
            let data = try CoordinatedFile.read(standard)
            editor = try Editor(data: data)
            selection = []
            guides = []
            fileURL = standard
            markClean()
            if editor.document.objects.isEmpty && editor.document.stamps.isEmpty {
                showBlankCanvas()
            } else {
                didFit = false
                fitIfNeeded()
            }
            LibraryStore.shared.reveal(standard)
        } catch {
            presentError(error)
        }
    }

    func save() {
        commitTextEdit(discardIfEmpty: true)
        if let fileURL {
            write(to: fileURL)
        } else {
            saveAs()
        }
    }

    func saveAs() {
        commitTextEdit(discardIfEmpty: true)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.fileType]
        panel.directoryURL = fileURL?.deletingLastPathComponent() ?? LibraryStore.shared.folder
        panel.nameFieldStringValue = (fileURL?.lastPathComponent ?? "Diagram")
        if panel.nameFieldStringValue.hasSuffix(".asciidraw") == false {
            panel.nameFieldStringValue += ".asciidraw"
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        fileURL = url
        write(to: url)
    }

    func export(kind: ExportKind) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [kind.contentType]
        panel.nameFieldStringValue = kind.suggestedName(for: documentTitle)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            switch kind {
            case .plain, .shell, .ruby, .python, .svg:
                let text: String
                switch kind {
                case .plain: text = editor.exportPlainText()
                case .shell: text = editor.exportShell()
                case .ruby: text = editor.exportRuby()
                case .python: text = editor.exportPython()
                case .svg: text = editor.exportSVG()
                default: text = ""
                }
                try text.write(to: url, atomically: true, encoding: .utf8)
            case .png:
                try editor.exportPNG().write(to: url)
            case .json:
                try editor.exportJSON().write(to: url)
            }
        } catch {
            presentError(error)
        }
    }

    func loadFont(for id: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "flf") ?? .data]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try editor.loadBannerFont(id, from: url)
        } catch {
            presentError(error)
        }
    }

    func nearestAnchor(to point: GridPoint) -> LineAnchor? {
        var best: (dist: Int, anchor: LineAnchor)?
        func consider(_ dist: Int, _ anchor: LineAnchor) {
            guard dist <= 1 else { return }
            if best == nil || dist < best!.dist {
                best = (dist, anchor)
            }
        }
        for object in editor.document.objects where !object.hidden {
            guard case .rectangle(let props) = object.kind else { continue }
            let frame = object.frame
            for border in props.points {
                let resolved = borderPoint(frame: frame, edge: border.edge, t: border.t)
                let dist = max(abs(resolved.x - point.x), abs(resolved.y - point.y))
                consider(dist, LineAnchor(shapeID: object.id, edge: border.edge, t: border.t, pointID: border.id))
            }
            for edge in RectEdge.allCases {
                let projected = project(point, onto: edge, frame: frame)
                let dist = max(abs(projected.point.x - point.x), abs(projected.point.y - point.y))
                consider(dist, LineAnchor(shapeID: object.id, edge: edge, t: projected.t))
            }
        }
        return best?.anchor
    }

    func project(_ point: GridPoint, onto edge: RectEdge, frame: GridRect) -> (point: GridPoint, t: Double) {
        switch edge {
        case .top, .bottom:
            let span = max(frame.width - 1, 1)
            let x = min(max(point.x, frame.minX), frame.minX + span)
            let t = Double(x - frame.minX) / Double(span)
            return (borderPoint(frame: frame, edge: edge, t: t), t)
        case .left, .right:
            let span = max(frame.height - 1, 1)
            let y = min(max(point.y, frame.minY), frame.minY + span)
            let t = Double(y - frame.minY) / Double(span)
            return (borderPoint(frame: frame, edge: edge, t: t), t)
        }
    }

    func noteMoved(from: URL, to: URL) {
        if fileURL?.standardizedFileURL == from.standardizedFileURL {
            fileURL = to
        }
    }

    func noteFileRemoved(_ url: URL) {
        guard fileURL?.standardizedFileURL == url.standardizedFileURL else { return }
        fileURL = nil
        if editor.document.objects.isEmpty && editor.document.stamps.isEmpty {
            markClean()
        } else {
            savedDocument = Document(version: -1)
            refreshDirty()
        }
    }

    func textEditContains(_ cell: GridPoint) -> Bool {
        guard let session = textEdit, let object = editor.object(session.id), case .text(let props) = object.kind else {
            return false
        }
        if object.frame.contains(cell) { return true }
        return TextCaret.cell(text: props.text, index: session.caret, frame: object.frame, props: props) == cell
    }

    func beginEditingText(_ id: UUID, at cell: GridPoint?) {
        if textEdit?.id == id {
            if let cell { placeTextCaret(at: cell) }
            focusDrawing()
            return
        }
        guard let object = editor.object(id), case .text(let props) = object.kind, !object.locked else { return }
        openTextGesture()
        let index = cell.map { TextCaret.index(in: props.text, frame: object.frame, props: props, cell: $0) } ?? props.text.count
        textEdit = TextSession(
            id: id,
            caret: index,
            columnHint: TextCaret.location(props.text, index: index).column,
            created: false,
            minimumFrame: object.frame
        )
        selection = [id]
        editor.selectTool(.select)
        focusDrawing()
    }

    func insertText(at cell: GridPoint) {
        openTextGesture()
        let frame = GridRect(x: cell.x, y: cell.y, width: 1, height: 1)
        let id = editor.addText(frame: frame, text: "")
        textEdit = TextSession(id: id, caret: 0, columnHint: 0, created: true, minimumFrame: nil)
        selection = [id]
        editor.selectTool(.select)
        refreshDirty()
        focusDrawing()
    }

    /// The text-tool drag already opened a gesture and created the object.
    func adoptTextEdit(_ id: UUID, created: Bool, minimumFrame: GridRect?) {
        guard let props = textProps(id) else { return }
        let index = props.text.count
        textEdit = TextSession(
            id: id,
            caret: index,
            columnHint: TextCaret.location(props.text, index: index).column,
            created: created,
            minimumFrame: minimumFrame
        )
        refreshDirty()
        focusDrawing()
    }

    func openTextGesture() {
        commitTextEdit(discardIfEmpty: true)
        editor.beginGesture(.accumulate)
    }

    func commitTextEdit(discardIfEmpty: Bool) {
        guard !committingText, let session = textEdit else { return }
        committingText = true
        defer { committingText = false }
        let empty = textProps(session.id)?.text.isEmpty ?? true
        let drop = discardIfEmpty && session.created && empty
        if drop, editor.object(session.id) != nil {
            editor.deleteObjects([session.id])
        }
        textEdit = nil
        if drop, selection.contains(session.id) {
            var kept = selection
            kept.remove(session.id)
            selection = kept
        }
        editor.endGesture()
    }

    func placeTextCaret(at cell: GridPoint) {
        guard var session = textEdit, let object = editor.object(session.id), case .text(let props) = object.kind else { return }
        let index = TextCaret.index(in: props.text, frame: object.frame, props: props, cell: cell)
        session.caret = index
        session.columnHint = TextCaret.location(props.text, index: index).column
        textEdit = session
    }

    func insertText(_ string: String) {
        guard let session = textEdit, let props = textProps(session.id) else { return }
        let inserted = TextCaret.insert(props.text, at: session.caret, string)
        let spot = TextCaret.location(inserted.text, index: inserted.caret)
        applyEditingText(inserted.text, caret: inserted.caret, column: spot.column)
    }

    func deleteTextBackward() {
        guard let session = textEdit, let props = textProps(session.id) else { return }
        let next = TextCaret.deleteBackward(props.text, at: session.caret)
        guard next.text != props.text else { return }
        let spot = TextCaret.location(next.text, index: next.caret)
        applyEditingText(next.text, caret: next.caret, column: spot.column)
    }

    func deleteTextForward() {
        guard let session = textEdit, let props = textProps(session.id) else { return }
        let next = TextCaret.deleteForward(props.text, at: session.caret)
        guard next.text != props.text else { return }
        applyEditingText(next.text, caret: next.caret, column: session.columnHint)
    }

    func moveTextCaret(lines: Int = 0, columns: Int = 0) {
        guard var session = textEdit, let props = textProps(session.id) else { return }
        let text = props.text
        if lines == 0 {
            let next = min(max(0, session.caret + columns), text.count)
            session.caret = next
            session.columnHint = TextCaret.location(text, index: next).column
            textEdit = session
            return
        }
        let rows = text.components(separatedBy: "\n")
        var spot = TextCaret.location(text, index: session.caret)
        spot.line = min(max(0, spot.line + lines), max(0, rows.count - 1))
        let column = min(session.columnHint, rows[spot.line].count)
        session.caret = TextCaret.index(text, line: spot.line, column: column)
        textEdit = session
    }

    private func applyEditingText(_ text: String, caret: Int, column: Int) {
        guard var session = textEdit, let props = textProps(session.id), let object = editor.object(session.id) else { return }
        let frame = TextCaret.fittedFrame(text: text, props: props, origin: object.frame, minimum: session.minimumFrame)
        editor.setTextContent(session.id, text: text, frame: frame)
        session.caret = caret
        session.columnHint = column
        textEdit = session
    }

    private func textProps(_ id: UUID) -> TextProps? {
        guard case .text(let props) = editor.object(id)?.kind else { return nil }
        return props
    }

    private func write(to url: URL) {
        do {
            try CoordinatedFile.write(editor.saveData(), to: url)
            fileURL = url
            markClean()
            LibraryStore.shared.reload()
        } catch {
            presentError(error)
        }
    }

    private func showBlankCanvas() {
        zoom = 1
        scrollX = 72
        scrollY = 48
        didFit = true
    }

    private func markClean() {
        savedDocument = editor.document
        refreshDirty()
    }

    private func refreshDirty() {
        var dirty = editor.document != savedDocument
        if dirty, let session = textEdit, session.created,
           let object = editor.object(session.id), case .text(let props) = object.kind, props.text.isEmpty {
            var copy = editor.document
            copy.objects.removeAll { $0.id == session.id }
            if copy == savedDocument { dirty = false }
        }
        if isDirty != dirty { isDirty = dirty }
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "AsciiDraw"
        alert.informativeText = String(describing: error)
        alert.runModal()
    }

    static var fileType: UTType { AsciiDrawDocument.type }
}

enum ExportKind: String, CaseIterable, Identifiable {
    case plain, shell, ruby, python, png, svg, json
    var id: String { rawValue }

    var title: String {
        switch self {
        case .plain: return "Plain Text…"
        case .shell: return "Shell Comment…"
        case .ruby: return "Ruby Comment…"
        case .python: return "Python Comment…"
        case .png: return "PNG…"
        case .svg: return "SVG…"
        case .json: return "JSON…"
        }
    }

    var contentType: UTType {
        switch self {
        case .plain, .shell, .ruby, .python: return .plainText
        case .png: return .png
        case .svg: return .svg
        case .json: return .json
        }
    }

    func suggestedName(for title: String) -> String {
        let base = title.isEmpty ? "Diagram" : title
        switch self {
        case .plain: return "\(base).txt"
        case .shell: return "\(base).sh"
        case .ruby: return "\(base).rb"
        case .python: return "\(base).py"
        case .png: return "\(base).png"
        case .svg: return "\(base).svg"
        case .json: return "\(base).json"
        }
    }
}

struct EditorModelKey: FocusedValueKey {
    typealias Value = EditorModel
}

extension FocusedValues {
    var editorModel: EditorModel? {
        get { self[EditorModelKey.self] }
        set { self[EditorModelKey.self] = newValue }
    }
}
