import AppKit
import AsciiDrawCore
import Foundation
import UniformTypeIdentifiers

enum AsciiDrawDocument {
    static let typeIdentifier = "com.aaqaishtyaq.asciidraw.document"

    static var type: UTType {
        UTType(typeIdentifier) ?? UTType(filenameExtension: "asciidraw") ?? .json
    }
}

/// Reads and writes through file coordination so a later iCloud folder can use the same calls.
enum CoordinatedFile {
    static func read(_ url: URL) throws -> Data {
        try coordinate(url, writing: false)
    }

    static func write(_ data: Data, to url: URL) throws {
        _ = try coordinate(url, writing: true, data: data)
    }

    private static func coordinate(_ url: URL, writing: Bool, data: Data? = nil) throws -> Data {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result = Data()
        var failure: Error?
        let options: NSFileCoordinator.ReadingOptions = []
        if writing {
            coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
                do {
                    try data?.write(to: target, options: .atomic)
                } catch {
                    failure = error
                }
            }
        } else {
            coordinator.coordinate(readingItemAt: url, options: options, error: &coordinationError) { target in
                do {
                    result = try Data(contentsOf: target)
                } catch {
                    failure = error
                }
            }
        }
        if let coordinationError { throw coordinationError }
        if let failure { throw failure }
        return result
    }
}

enum LibraryLocation {
    /// One folder of diagrams and subfolders. iCloud sync, later, points this
    /// at the ubiquity container's Documents directory. Nothing else has to change.
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("AsciiDraw/Library", isDirectory: true)
    }
}

struct LibraryEntry: Identifiable, Equatable {
    var url: URL
    var isFolder: Bool
    var modified: Date

    var id: String { url.path }

    var title: String {
        isFolder ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
    }
}

enum LibraryError: LocalizedError {
    case outsideLibrary
    case invalidName
    case alreadyExists

    var errorDescription: String? {
        switch self {
        case .outsideLibrary: return "That item is outside the library."
        case .invalidName: return "Use a name without slashes, colons, or a leading dot."
        case .alreadyExists: return "Something in this folder already has that name."
        }
    }
}

@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    let root: URL
    @Published private(set) var folder: URL
    @Published private(set) var entries: [LibraryEntry] = []

    var canGoUp: Bool {
        folder.standardizedFileURL.path != root.standardizedFileURL.path
    }

    var title: String {
        canGoUp ? folder.lastPathComponent : "Library"
    }

    init(root: URL? = nil) {
        let base = root ?? LibraryLocation.directory
        self.root = base
        folder = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        reload()
    }

    func reload() {
        do {
            entries = try loadEntries()
        } catch {
            report(error)
        }
    }

    func goUp() {
        guard canGoUp else { return }
        let parent = folder.deletingLastPathComponent()
        guard contains(parent) else { return }
        folder = parent
        reload()
    }

    func enter(_ entry: LibraryEntry) {
        guard entry.isFolder, contains(entry.url) else { return }
        folder = entry.url
        reload()
    }

    func reveal(_ url: URL) {
        let parent = url.deletingLastPathComponent()
        guard contains(parent) else { return }
        if folder.standardizedFileURL != parent.standardizedFileURL {
            folder = parent
        }
        reload()
    }

    @discardableResult
    func makeDiagram() throws -> URL {
        let name = uniqueName(base: "Diagram", ext: "asciidraw")
        let url = try destination(name)
        try CoordinatedFile.write(Document().encoded(), to: url)
        reload()
        return url
    }

    @discardableResult
    func makeFolder() throws -> URL {
        let name = uniqueName(base: "Folder", ext: nil)
        let url = try destination(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        reload()
        return url
    }

    @discardableResult
    func rename(_ entry: LibraryEntry, to raw: String) throws -> URL {
        guard contains(entry.url) else { throw LibraryError.outsideLibrary }
        let name = try sanitized(raw, file: !entry.isFolder)
        let dest = folder.appendingPathComponent(name)
        guard contains(dest) else { throw LibraryError.outsideLibrary }
        if dest.standardizedFileURL == entry.url.standardizedFileURL { return entry.url }
        if FileManager.default.fileExists(atPath: dest.path),
           dest.path.compare(entry.url.path, options: .caseInsensitive) != .orderedSame {
            throw LibraryError.alreadyExists
        }
        if dest.path.compare(entry.url.path, options: .caseInsensitive) == .orderedSame {
            let temporary = folder.appendingPathComponent(".rename-\(UUID().uuidString)")
            try FileManager.default.moveItem(at: entry.url, to: temporary)
            try FileManager.default.moveItem(at: temporary, to: dest)
        } else {
            try FileManager.default.moveItem(at: entry.url, to: dest)
        }
        reload()
        return dest
    }

    func trash(_ entry: LibraryEntry, then: @escaping @MainActor (URL) -> Void) {
        guard contains(entry.url) else { return }
        let url = entry.url
        NSWorkspace.shared.recycle([url]) { _, error in
            Task { @MainActor in
                if let error {
                    self.report(error)
                    return
                }
                then(url)
                self.reload()
            }
        }
    }

    func revealInFinder(_ entry: LibraryEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([entry.url])
    }

    func report(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Library"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    func contains(_ url: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }

    private func loadEntries() throws -> [LibraryEntry] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        var loaded: [LibraryEntry] = []
        for url in urls {
            guard contains(url) else { continue }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            let isFolder = values.isDirectory == true
            if !isFolder && url.pathExtension.lowercased() != "asciidraw" { continue }
            loaded.append(LibraryEntry(
                url: url,
                isFolder: isFolder,
                modified: values.contentModificationDate ?? .distantPast
            ))
        }
        loaded.sort { lhs, rhs in
            if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        return loaded
    }

    private func destination(_ name: String) throws -> URL {
        let url = folder.appendingPathComponent(name)
        guard contains(url) else { throw LibraryError.outsideLibrary }
        return url
    }

    private func uniqueName(base: String, ext: String?) -> String {
        func candidate(_ number: Int) -> String {
            let stem = number == 1 ? base : "\(base) \(number)"
            guard let ext else { return stem }
            return "\(stem).\(ext)"
        }
        var number = 1
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(candidate(number)).path) {
            number += 1
        }
        return candidate(number)
    }

    private func sanitized(_ raw: String, file: Bool) throws -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if file, name.lowercased().hasSuffix(".asciidraw") {
            name = String(name.dropLast(".asciidraw".count))
        }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == "." || name == ".." || name.hasPrefix(".") { throw LibraryError.invalidName }
        if name.contains("/") || name.contains(":") || name.contains("\\") { throw LibraryError.invalidName }
        if name.count > 200 { throw LibraryError.invalidName }
        if file { name += ".asciidraw" }
        return name
    }
}
