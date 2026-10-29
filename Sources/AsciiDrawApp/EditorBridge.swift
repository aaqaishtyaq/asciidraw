import AppKit
import AsciiDrawCore
import Darwin
import Foundation
import SwiftUI

enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
}

@MainActor
final class AppearanceController: ObservableObject {
    static let shared = AppearanceController()
    static let defaultsKey = "asciidraw.appearance"

    @Published var choice: AppearanceChoice {
        didSet {
            guard choice != oldValue else { return }
            UserDefaults.standard.set(choice.rawValue, forKey: Self.defaultsKey)
            apply()
        }
    }

    /// Always a concrete scheme. `nil` leaves a window stuck on the last override.
    var colorScheme: ColorScheme {
        switch choice {
        case .light: return .light
        case .dark: return .dark
        case .system: return Self.systemIsDark ? .dark : .light
        }
    }

    var nsAppearance: NSAppearance? {
        let name: NSAppearance.Name = switch choice {
        case .light: .aqua
        case .dark: .darkAqua
        case .system: Self.systemIsDark ? .darkAqua : .aqua
        }
        return NSAppearance(named: name)
    }

    private var themeObserver: NSObjectProtocol?

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? AppearanceChoice.system.rawValue
        choice = AppearanceChoice(rawValue: raw) ?? .system
        themeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    AppearanceController.shared.systemThemeChanged()
                }
            }
        }
    }

    func systemThemeChanged() {
        guard choice == .system else { return }
        objectWillChange.send()
        apply()
    }

    func apply() {
        let name: NSAppearance.Name = switch choice {
        case .light: .aqua
        case .dark: .darkAqua
        case .system: Self.systemIsDark ? .darkAqua : .aqua
        }
        let appearance = NSAppearance(named: name)
        NSApp.appearance = choice == .system ? nil : appearance
        for window in NSApp.windows {
            window.appearance = appearance
            window.contentView?.needsDisplay = true
        }
    }

    private static var systemIsDark: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }
}

/// The document the bridge edits. The front window registers itself.
@MainActor
enum FrontDocument {
    static weak var model: EditorModel?
}

/// Local socket other processes use to drive the open document.
/// `asciidraw-mcp` speaks MCP on stdio and forwards each tool call here.
final class EditorBridge: @unchecked Sendable {
    static let shared = EditorBridge()

    static var socketPath: String { "/tmp/asciidraw-\(getuid()).sock" }

    private let queue = DispatchQueue(label: "asciidraw.bridge")
    private let lock = NSLock()
    private var listenFD: Int32 = -1
    private var started = false

    func start() {
        queue.async { [weak self] in
            self?.listen()
        }
    }

    /// Closes the listening socket from the caller. Waiting on the bridge queue would deadlock if a tool call is on its way back to the main thread.
    func stop() {
        lock.lock()
        let fd = listenFD
        listenFD = -1
        started = false
        lock.unlock()
        if fd >= 0 {
            shutdown(fd, SHUT_RDWR)
            close(fd)
        }
        unlink(Self.socketPath)
        try? FileManager.default.removeItem(at: Self.pointerURL())
    }

    static func pointerURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("AsciiDraw", isDirectory: true).appendingPathComponent("bridge.json")
    }

    private func listen() {
        if started { return }
        let path = Self.socketPath
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            note("socket() failed \(errno)")
            return
        }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        path.withCString { source in
            withUnsafeMutablePointer(to: &addr.sun_path) { raw in
                raw.withMemoryRebound(to: CChar.self, capacity: capacity) { dest in
                    strncpy(dest, source, capacity - 1)
                    dest[capacity - 1] = 0
                }
            }
        }
        let used = socklen_t(MemoryLayout<UInt8>.size + MemoryLayout<sa_family_t>.size + path.utf8.count + 1)
        addr.sun_len = UInt8(used)
        let bound = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(fd, sa, used)
            }
        }
        guard bound == 0, Darwin.listen(fd, 8) == 0 else {
            note("bind/listen failed \(errno) path \(path)")
            close(fd)
            return
        }
        note("listening \(path)")
        _ = chmod(path, 0o600)
        lock.lock()
        listenFD = fd
        started = true
        lock.unlock()
        writePointer(path)
        while true {
            lock.lock()
            let open = listenFD >= 0
            lock.unlock()
            if !open { break }
            let client = accept(fd, nil, nil)
            if client < 0 { break }
            serve(client)
        }
    }

    private func note(_ message: String) {
        let path = "/tmp/asciidraw-bridge.log"
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        handle.seekToEndOfFile()
        handle.write(Data("asciidraw bridge: \(message)\n".utf8))
        try? handle.close()
    }

    private func writePointer(_ path: String) {
        let url = Self.pointerURL()
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let payload: [String: Any] = ["socket": path, "pid": Int(getpid())]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) else { return }
        try? data.write(to: url)
    }

    private func serve(_ client: Int32) {
        defer { close(client) }
        var pending = Data()
        var chunk = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = read(client, &chunk, chunk.count)
            if count <= 0 { break }
            pending.append(chunk, count: count)
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = pending.prefix(upTo: newline)
                pending.removeSubrange(...newline)
                guard !line.isEmpty else { continue }
                let response = answer(Data(line))
                _ = response.withUnsafeBytes { raw in
                    guard let base = raw.baseAddress else { return 0 }
                    return write(client, base, raw.count)
                }
            }
        }
    }

    private func answer(_ line: Data) -> Data {
        let fallbackID: Any = NSNull()
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            return jsonLine(["id": fallbackID, "error": "Expected one JSON object per line."])
        }
        let id = object["id"] ?? fallbackID
        let method = object["method"] as? String ?? ""
        let params = object["params"] as? [String: Any] ?? [:]
        let outcome: [String: Any] = DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                guard let model = FrontDocument.model else {
                    return ["id": id, "error": "AsciiDraw has no open document."]
                }
                return model.bridge(method: method, params: params, id: id)
            }
        }
        return jsonLine(outcome)
    }

    private func jsonLine(_ object: [String: Any]) -> Data {
        var data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        data.append(0x0A)
        return data
    }
}

extension EditorModel {
    func bridge(method: String, params: [String: Any], id: Any) -> [String: Any] {
        switch method {
        case "read_canvas":
            return ok(id, ["title": documentTitle, "text": editor.exportPlainText()])
        case "list_shapes":
            return ok(id, [
                "title": documentTitle,
                "zoom": zoom,
                "selection": selection.map(\.uuidString).sorted(),
                "shapes": editor.document.objects.map(shapeRecord),
            ])
        case "add_shape":
            return addShape(id, params)
        case "set_text":
            return setShapeText(id, params)
        case "set_frame":
            return setShapeFrame(id, params)
        case "delete_shapes":
            let ids = uuidList(params["ids"])
            editor.deleteObjects(ids)
            selection.subtract(ids)
            return ok(id, ["deleted": ids.map(\.uuidString)])
        case "select_shapes":
            let ids = uuidList(params["ids"]).filter { editor.object($0) != nil }
            selection = Set(ids)
            return ok(id, ["selection": ids.map(\.uuidString)])
        case "set_zoom":
            guard let value = doubleValue(params["zoom"]) else {
                return fail(id, "set_zoom needs a zoom number.")
            }
            setZoom(value)
            return ok(id, ["zoom": zoom])
        default:
            return fail(id, "Unknown method \(method).")
        }
    }

    private func addShape(_ id: Any, _ params: [String: Any]) -> [String: Any] {
        let kind = (params["kind"] as? String)?.lowercased() ?? "rectangle"
        let x = intValue(params["x"]) ?? 0
        let y = intValue(params["y"]) ?? 0
        let width = max(2, intValue(params["width"]) ?? 12)
        let height = max(2, intValue(params["height"]) ?? 4)
        let text = params["text"] as? String ?? "Text"
        let frame = GridRect(x: x, y: y, width: width, height: height)
        let created: UUID
        switch kind {
        case "diamond":
            created = editor.addDiamond(frame: frame)
        case "text":
            created = editor.addText(frame: frame, text: text)
        case "banner":
            created = editor.addBanner(frame: frame, text: text, fontName: params["font"] as? String ?? "standard")
        case "line":
            let endX = intValue(params["endX"]) ?? x + width
            let endY = intValue(params["endY"]) ?? y
            created = editor.addLine(LineProps(start: GridPoint(x: x, y: y), end: GridPoint(x: endX, y: endY)))
        case "rectangle", "rect":
            created = editor.addRectangle(frame: frame, border: .single, fill: nil, shadow: nil)
        default:
            return fail(id, "kind must be rectangle, diamond, text, line, or banner.")
        }
        selection = [created]
        return ok(id, ["id": created.uuidString])
    }

    private func setShapeText(_ id: Any, _ params: [String: Any]) -> [String: Any] {
        guard let shapeID = uuidValue(params["id"]) else { return fail(id, "set_text needs an id.") }
        guard let text = params["text"] as? String else { return fail(id, "set_text needs text.") }
        guard let object = editor.object(shapeID) else { return fail(id, "No shape \(shapeID.uuidString).") }
        switch object.kind {
        case .text:
            editor.setText(shapeID) { $0.text = text }
        case .banner:
            editor.setBanner(shapeID) { $0.text = text }
        default:
            return fail(id, "\(object.name) has no text.")
        }
        return ok(id, ["id": shapeID.uuidString])
    }

    private func setShapeFrame(_ id: Any, _ params: [String: Any]) -> [String: Any] {
        guard let shapeID = uuidValue(params["id"]), let object = editor.object(shapeID) else {
            return fail(id, "set_frame needs an id of a shape in this document.")
        }
        let frame = GridRect(
            x: intValue(params["x"]) ?? object.frame.x,
            y: intValue(params["y"]) ?? object.frame.y,
            width: max(2, intValue(params["width"]) ?? object.frame.width),
            height: max(2, intValue(params["height"]) ?? object.frame.height)
        )
        editor.setFrame(shapeID, frame)
        return ok(id, ["id": shapeID.uuidString])
    }

    private func shapeRecord(_ object: DrawObject) -> [String: Any] {
        var record: [String: Any] = [
            "id": object.id.uuidString,
            "name": object.name,
            "kind": kindName(object),
            "x": object.frame.x,
            "y": object.frame.y,
            "width": object.frame.width,
            "height": object.frame.height,
            "locked": object.locked,
            "hidden": object.hidden,
        ]
        switch object.kind {
        case .text(let props):
            record["text"] = props.text
        case .banner(let props):
            record["text"] = props.text
            record["font"] = props.fontName
        case .line(let props):
            record["x"] = props.start.x
            record["y"] = props.start.y
            record["endX"] = props.end.x
            record["endY"] = props.end.y
        case .rectangle, .diamond:
            break
        }
        return record
    }

    private func kindName(_ object: DrawObject) -> String {
        switch object.kind {
        case .rectangle: return "rectangle"
        case .diamond: return "diamond"
        case .text: return "text"
        case .line: return "line"
        case .banner: return "banner"
        }
    }

    private func ok(_ id: Any, _ result: [String: Any]) -> [String: Any] {
        ["id": id, "result": result]
    }

    private func fail(_ id: Any, _ message: String) -> [String: Any] {
        ["id": id, "error": message]
    }
}

private func uuidValue(_ value: Any?) -> UUID? {
    guard let string = value as? String else { return nil }
    return UUID(uuidString: string)
}

private func uuidList(_ value: Any?) -> [UUID] {
    let strings = value as? [String] ?? []
    return strings.compactMap(UUID.init(uuidString:))
}

private func intValue(_ value: Any?) -> Int? {
    switch value {
    case let number as Int: return number
    case let number as Double: return Int(number)
    case let number as NSNumber: return number.intValue
    case let text as String: return Int(text)
    default: return nil
    }
}

private func doubleValue(_ value: Any?) -> Double? {
    switch value {
    case let number as Double: return number
    case let number as Int: return Double(number)
    case let number as NSNumber: return number.doubleValue
    case let text as String: return Double(text)
    default: return nil
    }
}
