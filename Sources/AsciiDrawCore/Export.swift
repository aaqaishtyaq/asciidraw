import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ExportMetrics {
    public static let cellWidth = 8
    public static let cellHeight = 16
}

public struct RecoverableExport: Equatable, Codable {
    public var text: String
    public var document: Document

    public init(text: String, document: Document) {
        self.text = text
        self.document = document
    }
}

public struct FitResult: Equatable {
    public var zoom: Double
    public var scrollX: Double
    public var scrollY: Double

    public init(zoom: Double, scrollX: Double, scrollY: Double) {
        self.zoom = zoom
        self.scrollX = scrollX
        self.scrollY = scrollY
    }
}

public enum Exporter {
    public static func plainText(_ document: Document) -> String {
        Renderer.render(document).plainText
    }

    public static func shell(_ document: Document) -> String {
        wrap(plainText(document), header: ": <<'", footer: "'")
    }

    public static func ruby(_ document: Document) -> String {
        let text = plainText(document)
        return "=begin\n\(text)\n=end\n"
    }

    public static func python(_ document: Document) -> String {
        let text = plainText(document)
        let fence = text.contains("\"\"\"") ? "'''" : "\"\"\""
        return "\(fence)\n\(text)\n\(fence)\n"
    }

    public static func svg(_ document: Document) -> String {
        let grid = Renderer.render(document)
        let columns = max(grid.columnCount, 1)
        let rows = max(grid.rowCount, 1)
        let width = columns * ExportMetrics.cellWidth
        let height = rows * ExportMetrics.cellHeight
        var body = ""
        for (index, row) in grid.rows.enumerated() {
            let y = (index + 1) * ExportMetrics.cellHeight - 3
            body += "<text x=\"0\" y=\"\(y)\" xml:space=\"preserve\">\(xmlEscape(row))</text>\n"
        }
        if grid.rows.isEmpty {
            body = "<text x=\"0\" y=\"\(ExportMetrics.cellHeight - 3)\"></text>\n"
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="\(height)" viewBox="0 0 \(width) \(height)">
        <rect width="100%" height="100%" fill="white"/>
        <g font-family="Menlo, ui-monospace, monospace" font-size="14" fill="black">
        \(body)</g>
        </svg>
        """
    }

    public static func png(_ document: Document) -> Data {
        let grid = Renderer.render(document)
        let columns = max(grid.columnCount, 1)
        let rows = max(grid.rowCount, 1)
        let width = columns * ExportMetrics.cellWidth
        let height = rows * ExportMetrics.cellHeight
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return Data()
        }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Menlo" as CFString, 12, nil)
        let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let sourceRows = grid.rows.isEmpty ? [" "] : grid.rows
        for (index, row) in sourceRows.enumerated() {
            let baseline = CGFloat(height - (index + 1) * ExportMetrics.cellHeight + 3)
            draw(row, at: CGPoint(x: 0, y: baseline), font: font, color: black, context: context)
        }
        guard let image = context.makeImage() else { return Data() }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return Data()
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return Data() }
        return data as Data
    }

    public static func jsonData(_ document: Document) throws -> Data {
        let payload = RecoverableExport(text: plainText(document), document: document)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    public static func plainText(fromJSON data: Data) throws -> String {
        let payload = try JSONDecoder().decode(RecoverableExport.self, from: data)
        return Renderer.render(payload.document).plainText
    }

    public static func fit(
        document: Document,
        viewportWidth: Double,
        viewportHeight: Double,
        cellWidth: Double,
        cellHeight: Double,
        padding: Double = 24,
        minZoom: Double = 0.25,
        maxZoom: Double = 6
    ) -> FitResult? {
        guard cellWidth > 0, cellHeight > 0, viewportWidth > padding * 2, viewportHeight > padding * 2 else {
            return nil
        }
        guard let bounds = Renderer.render(document).bounds, bounds.width > 0, bounds.height > 0 else {
            return nil
        }
        let contentWidth = Double(bounds.width) * cellWidth
        let contentHeight = Double(bounds.height) * cellHeight
        let zoom = min(
            (viewportWidth - padding * 2) / contentWidth,
            (viewportHeight - padding * 2) / contentHeight
        )
        let clamped = min(maxZoom, max(minZoom, zoom))
        let usedWidth = contentWidth * clamped
        let usedHeight = contentHeight * clamped
        let scrollX = (viewportWidth - usedWidth) / 2 - Double(bounds.minX) * cellWidth * clamped
        let scrollY = (viewportHeight - usedHeight) / 2 - Double(bounds.minY) * cellHeight * clamped
        return FitResult(zoom: clamped, scrollX: scrollX, scrollY: scrollY)
    }

    private static func wrap(_ text: String, header: String, footer: String) -> String {
        var token = "ASCIIDRAW"
        while text.contains(token) {
            token += "_END"
        }
        return "\(header)\(token)'\n\(text)\n\(token)\n"
    }

    private static func xmlEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func draw(_ text: String, at point: CGPoint, font: CTFont, color: CGColor, context: CGContext) {
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: color,
        ]
        let attributed = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)
        let line = CTLineCreateWithAttributedString(attributed!)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: 1)
        context.textPosition = point
        CTLineDraw(line, context)
    }
}
