import Foundation

public struct FigletFont: Equatable {
    public let name: String
    public let height: Int
    public let hardblank: Character
    public let glyphs: [Character: [String]]

    public func render(_ text: String) -> [String] {
        let parts = text.components(separatedBy: "\n")
        var rows: [String] = []
        for part in parts {
            rows.append(contentsOf: renderLine(part))
        }
        return rows
    }

    public func renderLine(_ line: String) -> [String] {
        if line.isEmpty {
            return Array(repeating: "", count: height)
        }
        var combined = Array(repeating: "", count: height)
        for character in line {
            let glyph = glyphs[character] ?? glyphs["?"] ?? Array(repeating: String(character), count: height)
            for index in 0..<height {
                combined[index] += index < glyph.count ? glyph[index] : ""
            }
        }
        return combined
    }

    public static func load(data: Data, name: String) throws -> FigletFont {
        guard let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw AsciiDrawError.invalidFont("\(name) is not text")
        }
        let lines = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        guard let header = lines.first else {
            throw AsciiDrawError.invalidFont("\(name) is empty")
        }
        guard header.hasPrefix("flf2a"), header.count >= 6 else {
            throw AsciiDrawError.invalidFont("\(name) is missing an flf2a header")
        }
        let hardblank = header[header.index(header.startIndex, offsetBy: 5)]
        let numbers = header.dropFirst(6).split(separator: " ").map(String.init)
        guard numbers.count >= 5,
              let height = Int(numbers[0]), height > 0,
              let commentLines = Int(numbers[4]), commentLines >= 0 else {
            throw AsciiDrawError.invalidFont("\(name) has a bad header")
        }
        var cursor = 1 + commentLines
        var glyphs: [Character: [String]] = [:]
        for code in 32...126 {
            var glyph: [String] = []
            for row in 0..<height {
                guard cursor < lines.count else {
                    throw AsciiDrawError.invalidFont("\(name) ended before character \(code)")
                }
                glyph.append(strip(lines[cursor], hardblank: hardblank, isLast: row == height - 1))
                cursor += 1
            }
            glyphs[Character(UnicodeScalar(code)!)] = glyph
        }
        return FigletFont(name: name, height: height, hardblank: hardblank, glyphs: glyphs)
    }

    public static func load(contentsOf url: URL) throws -> FigletFont {
        let data = try Data(contentsOf: url)
        let name = url.deletingPathExtension().lastPathComponent
        return try load(data: data, name: name)
    }

    public static func bundled(_ name: String) throws -> FigletFont {
        try BundledFonts.load(name)
    }

    private static func strip(_ line: String, hardblank: Character, isLast: Bool) -> String {
        var value = line
        if value.hasSuffix("\r") { value.removeLast() }
        if isLast {
            if value.hasSuffix("@@") {
                value.removeLast(2)
            } else if value.hasSuffix("@") {
                value.removeLast()
            }
        } else if value.hasSuffix("@") {
            value.removeLast()
        }
        return value.replacingOccurrences(of: String(hardblank), with: " ")
    }
}

public enum BundledFonts {
    public static let fileNames = ["block.flf", "slim.flf", "standard.flf"]
    public static let names = ["block", "slim", "standard"]

    public static func load(_ name: String) throws -> FigletFont {
        let base = name.hasSuffix(".flf") ? String(name.dropLast(4)) : name
        guard let data = EmbeddedFonts.data(named: base) else {
            throw AsciiDrawError.invalidFont("bundled font \(base) was not found")
        }
        return try FigletFont.load(data: data, name: base)
    }
}

public enum AsciiDrawError: Error, Equatable, CustomStringConvertible {
    case invalidDocument(String)
    case invalidFont(String)
    case unreadable(String)

    public var description: String {
        switch self {
        case .invalidDocument(let message), .invalidFont(let message), .unreadable(let message):
            return message
        }
    }
}
