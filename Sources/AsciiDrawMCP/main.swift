import Darwin
import Foundation

/// MCP server for the running AsciiDraw app. Claude and other clients speak
/// JSON-RPC on stdin. Each tool call is one line on the app's local socket.
@main
enum AsciiDrawMCP {
    static func main() {
        let input = FileHandle.standardInput
        let output = FileHandle.standardOutput
        var buffer = Data()
        while true {
            let chunk = input.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let message = takeMessage(&buffer) {
                guard let response = handle(message) else { continue }
                writeMessage(response, to: output)
            }
        }
    }

    static func handle(_ data: Data) -> Any? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let id = object["id"] else { return nil }
        let method = object["method"] as? String ?? ""
        let params = object["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            let requested = (params["protocolVersion"] as? String) ?? "2024-11-05"
            return result(id, [
                "protocolVersion": requested,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "asciidraw", "version": "1.0"],
            ])
        case "ping":
            return result(id, [:])
        case "tools/list":
            return result(id, ["tools": toolList])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            return call(id, name, arguments)
        default:
            return error(id, -32601, "Unknown method \(method).")
        }
    }

    static func call(_ id: Any, _ name: String, _ arguments: [String: Any]) -> Any {
        let method = bridgeMethod[name] ?? name
        do {
            let payload = try forward(method: method, params: arguments)
            if let message = payload["error"] as? String {
                return result(id, [
                    "content": [["type": "text", "text": message]],
                    "isError": true,
                ])
            }
            let value = payload["result"] ?? [:]
            let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            let text = String(data: data, encoding: .utf8) ?? "{}"
            return result(id, [
                "content": [["type": "text", "text": text]],
                "isError": false,
            ])
        } catch {
            return result(id, [
                "content": [["type": "text", "text": "\(error)"]],
                "isError": true,
            ])
        }
    }

    static let bridgeMethod = [
        "read_canvas": "read_canvas",
        "list_shapes": "list_shapes",
        "add_shape": "add_shape",
        "set_text": "set_text",
        "set_frame": "set_frame",
        "delete_shapes": "delete_shapes",
        "select_shapes": "select_shapes",
        "set_zoom": "set_zoom",
    ]

    static func forward(method: String, params: [String: Any]) throws -> [String: Any] {
        let path = socketPath()
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw MCPError("Could not open a socket.") }
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        let connected = path.withCString { source -> Int32 in
            withUnsafeMutablePointer(to: &addr.sun_path) { raw in
                raw.withMemoryRebound(to: CChar.self, capacity: capacity) { dest in
                    strncpy(dest, source, capacity - 1)
                    dest[capacity - 1] = 0
                }
            }
            return withUnsafePointer(to: &addr) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    connect(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
        }
        guard connected == 0 else {
            throw MCPError("AsciiDraw is not running. Open the app, then call this tool again.")
        }
        let request: [String: Any] = ["id": 1, "method": method, "params": params]
        var body = try JSONSerialization.data(withJSONObject: request)
        body.append(0x0A)
        try body.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var sent = 0
            while sent < raw.count {
                let wrote = write(fd, base.advanced(by: sent), raw.count - sent)
                if wrote <= 0 { throw MCPError("The AsciiDraw bridge closed the connection.") }
                sent += wrote
            }
        }
        var pending = Data()
        var chunk = [UInt8](repeating: 0, count: 8192)
        while pending.firstIndex(of: 0x0A) == nil {
            let count = read(fd, &chunk, chunk.count)
            if count <= 0 { throw MCPError("AsciiDraw closed the bridge before it answered.") }
            pending.append(chunk, count: count)
        }
        let newline = pending.firstIndex(of: 0x0A)!
        let line = pending.prefix(upTo: newline)
        guard let object = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
            throw MCPError("AsciiDraw returned a response that was not JSON.")
        }
        return object
    }

    static func socketPath() -> String {
        if let override = ProcessInfo.processInfo.environment["ASCIIDRAW_SOCKET"], !override.isEmpty {
            return override
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let pointer = base?.appendingPathComponent("AsciiDraw/bridge.json")
        if let pointer, let data = try? Data(contentsOf: pointer),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let path = object["socket"] as? String, !path.isEmpty {
            return path
        }
        return "/tmp/asciidraw-\(getuid()).sock"
    }

    static func result(_ id: Any, _ value: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": value]
    }

    static func error(_ id: Any, _ code: Int, _ message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    static func writeMessage(_ object: Any, to output: FileHandle) {
        guard let body = try? JSONSerialization.data(withJSONObject: object) else { return }
        let header = "Content-Length: \(body.count)\r\n\r\n"
        output.write(Data(header.utf8))
        output.write(body)
    }

    /// LSP-style framing used by MCP stdio clients.
    static func takeMessage(_ buffer: inout Data) -> Data? {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = buffer.subdata(in: 0..<headerEnd.lowerBound)
        let header = String(data: headerData, encoding: .utf8) ?? ""
        let length = header.split(separator: "\r\n").compactMap { line -> Int? in
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" else {
                return nil
            }
            return Int(parts[1].trimmingCharacters(in: .whitespaces))
        }.first
        guard let length, length >= 0 else { return nil }
        let start = headerEnd.upperBound
        guard buffer.count >= start + length else { return nil }
        let body = buffer.subdata(in: start..<(start + length))
        buffer.removeSubrange(0..<(start + length))
        return body
    }
}

private struct MCPError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}

private let toolList: [[String: Any]] = [
    tool("read_canvas", "Read the open AsciiDraw diagram as plain text.", [:]),
    tool("list_shapes", "List shapes in the open document, including ids, frames, and the current selection.", [:]),
    tool(
        "add_shape",
        "Add a rectangle, diamond, text, line, or banner to the open document and select it.",
        [
            "kind": schema("string", "rectangle, diamond, text, line, or banner"),
            "x": schema("integer", "Left cell"),
            "y": schema("integer", "Top cell"),
            "width": schema("integer", "Width in cells"),
            "height": schema("integer", "Height in cells"),
            "text": schema("string", "Text for a text shape or banner"),
            "font": schema("string", "FIGlet font for a banner. standard, slim, or block"),
            "endX": schema("integer", "Line end column"),
            "endY": schema("integer", "Line end row"),
        ],
        required: ["kind", "x", "y"]
    ),
    tool(
        "set_text",
        "Replace the text of a text shape or banner.",
        [
            "id": schema("string", "Shape id from list_shapes"),
            "text": schema("string", "New text"),
        ],
        required: ["id", "text"]
    ),
    tool(
        "set_frame",
        "Move or resize a shape. Omitted edges keep their current value.",
        [
            "id": schema("string", "Shape id"),
            "x": schema("integer", "Left cell"),
            "y": schema("integer", "Top cell"),
            "width": schema("integer", "Width in cells"),
            "height": schema("integer", "Height in cells"),
        ],
        required: ["id"]
    ),
    tool(
        "delete_shapes",
        "Delete shapes by id.",
        ["ids": ["type": "array", "items": ["type": "string"], "description": "Shape ids"]],
        required: ["ids"]
    ),
    tool(
        "select_shapes",
        "Select shapes by id. Pass an empty list to clear the selection.",
        ["ids": ["type": "array", "items": ["type": "string"], "description": "Shape ids"]],
        required: ["ids"]
    ),
    tool(
        "set_zoom",
        "Set the canvas zoom. 1 is actual size.",
        ["zoom": schema("number", "Zoom factor from 0.2 to 6")],
        required: ["zoom"]
    ),
]

private func tool(_ name: String, _ description: String, _ properties: [String: Any], required: [String] = []) -> [String: Any] {
    var schema: [String: Any] = ["type": "object", "properties": properties]
    if !required.isEmpty { schema["required"] = required }
    return [
        "name": name,
        "description": description,
        "inputSchema": schema,
    ]
}

private func schema(_ type: String, _ description: String) -> [String: Any] {
    ["type": type, "description": description]
}
