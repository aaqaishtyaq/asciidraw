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
        case .line: return "line.diagonal"
        case .pencil: return "pencil"
        case .eraser: return "eraser"
        case .bucket: return "paintbucket"
        case .picker: return "eyedropper"
        case .banner: return "bold"
        case .pan: return "hand.raised"
        }
    }

    var shortcutLabel: String {
        guard let key = ToolShortcut.map.first(where: { $0.1 == self })?.0 else { return "" }
        return String(key).uppercased()
    }
}

@MainActor
final class EditorModel: ObservableObject {
    @Published var editor: Editor
    @Published var selection: Set<UUID> = []
    @Published var guides: [SnapGuide] = []
    @Published var scrollX: Double = 72
    @Published var scrollY: Double = 48
    @Published var zoom: Double = 1
    @Published var fileURL: URL?
    @Published var hover = GridPoint(x: 0, y: 0)
    @Published var viewport = CGSize(width: 1100, height: 720)

    let cellWidth: Double = 12
    let cellHeight: Double = 22
    var focusCanvas: (() -> Void)?
    private var didFit = false

    init(editor: Editor = Editor.welcome()) {
        self.editor = editor
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

    func setZoom(_ newValue: Double) {
        let anchor = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        let factor = min(6, max(0.2, newValue)) / zoom
        zoom(by: factor, anchor: anchor)
    }

    func undo() {
        _ = editor.undo()
        guides = []
    }

    func redo() {
        _ = editor.redo()
        guides = []
    }

    func deleteSelection() {
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
        editor = Editor()
        selection = []
        guides = []
        fileURL = nil
        didFit = false
        fitIfNeeded()
    }

    func openDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.fileType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url: url)
    }

    func open(url: URL) {
        do {
            let data = try Data(contentsOf: url)
            editor = try Editor(data: data)
            selection = []
            guides = []
            fileURL = url
            didFit = false
            fitIfNeeded()
        } catch {
            presentError(error)
        }
    }

    func save() {
        if let fileURL {
            write(to: fileURL)
        } else {
            saveAs()
        }
    }

    func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.fileType]
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

    private func write(to url: URL) {
        do {
            try editor.saveData().write(to: url)
            fileURL = url
        } catch {
            presentError(error)
        }
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "AsciiDraw"
        alert.informativeText = String(describing: error)
        alert.runModal()
    }

    static let fileType = UTType(filenameExtension: "asciidraw") ?? .json
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
