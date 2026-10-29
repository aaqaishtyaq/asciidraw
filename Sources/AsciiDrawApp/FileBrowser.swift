import AppKit
import SwiftUI

struct FileBrowser: View {
    @ObservedObject var model: EditorModel
    @ObservedObject private var library = LibraryStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if library.entries.isEmpty {
                Text(library.canGoUp ? "This folder is empty." : "No diagrams yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                Spacer(minLength: 0)
            } else {
                List {
                    ForEach(library.entries) { entry in
                        row(entry)
                            .contentShape(Rectangle())
                            .onTapGesture { activate(entry) }
                            .contextMenu { menu(entry) }
                    }
                }
                .listStyle(.sidebar)
                .accessibilityIdentifier("file-browser")
                .accessibilityLabel("Diagram library")
            }
        }
        .onAppear { library.reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            library.reload()
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            if library.canGoUp {
                Button(action: library.goUp) {
                    Image(systemName: "chevron.left")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(HoverPlateButtonStyle())
                .help("Enclosing folder")
                .accessibilityLabel("Enclosing folder")
            }
            Text(library.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            headerButton("doc.badge.plus", "New diagram", newDiagram)
            headerButton("folder.badge.plus", "New folder", newFolder)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    private func headerButton(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(HoverPlateButtonStyle())
        .help(help)
        .accessibilityLabel(help)
    }

    private func row(_ entry: LibraryEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: entry.isFolder ? "folder" : "doc.text")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .lineLimit(1)
                Text(entry.isFolder ? "Folder" : entry.modified.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if isOpen(entry) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                    .accessibilityLabel("Open")
            }
        }
        .padding(.vertical, 1)
        .accessibilityLabel(entry.isFolder ? "Folder \(entry.title)" : "Diagram \(entry.title)")
    }

    @ViewBuilder
    private func menu(_ entry: LibraryEntry) -> some View {
        Button("Open") { activate(entry) }
        Button("Rename…") { promptRename(entry) }
        Button("Move to Trash") {
            library.trash(entry) { url in
                model.noteFileRemoved(url)
            }
        }
        Divider()
        Button("Show in Finder") { library.revealInFinder(entry) }
    }

    private func isOpen(_ entry: LibraryEntry) -> Bool {
        !entry.isFolder && model.fileURL?.standardizedFileURL == entry.url.standardizedFileURL
    }

    private func activate(_ entry: LibraryEntry) {
        if entry.isFolder {
            library.enter(entry)
        } else {
            model.open(url: entry.url)
        }
    }

    private func newDiagram() {
        guard model.confirmDiscardIfNeeded() else { return }
        do {
            let url = try library.makeDiagram()
            model.open(url: url, prompting: false)
        } catch {
            library.report(error)
        }
    }

    private func newFolder() {
        do {
            _ = try library.makeFolder()
        } catch {
            library.report(error)
        }
    }

    private func promptRename(_ entry: LibraryEntry) {
        let alert = NSAlert()
        alert.messageText = "Rename \(entry.title)"
        alert.informativeText = entry.isFolder ? "Folder name." : "The file stays a .asciidraw diagram."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = entry.title
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let dest = try library.rename(entry, to: field.stringValue)
            model.noteMoved(from: entry.url, to: dest)
        } catch {
            library.report(error)
        }
    }
}
