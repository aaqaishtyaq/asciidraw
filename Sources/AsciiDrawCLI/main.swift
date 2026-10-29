import AsciiDrawCore
import Foundation

@main
enum AsciiDrawCLI {
    static func main() {
        exit(run(Array(CommandLine.arguments.dropFirst())))
    }

    static func run(_ arguments: [String]) -> Int32 {
        if arguments.contains("--version") {
            FileHandle.standardOutput.write(Data("\(ProductVersion.semantic)\n".utf8))
            return 0
        }
        let wantsJSON = arguments.contains("--json")
        let paths = arguments.filter { $0 != "--json" }
        guard paths.count == 1, let path = paths.first else {
            let message = "usage: asciidraw [--json] <file.asciidraw>\n       asciidraw --version\n"
            FileHandle.standardError.write(Data(message.utf8))
            return 2
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let document = try Document(data: data)
            if wantsJSON {
                let payload = try Exporter.jsonData(document)
                FileHandle.standardOutput.write(payload)
                if !payload.hasSuffixNewline {
                    FileHandle.standardOutput.write(Data([0x0A]))
                }
            } else {
                var text = Exporter.plainText(document)
                if !text.hasSuffix("\n") {
                    text.append("\n")
                }
                FileHandle.standardOutput.write(Data(text.utf8))
            }
            return 0
        } catch {
            let message = "asciidraw: \(error)\n"
            FileHandle.standardError.write(Data(message.utf8))
            return 1
        }
    }
}

private extension Data {
    var hasSuffixNewline: Bool { last == 0x0A }
}
