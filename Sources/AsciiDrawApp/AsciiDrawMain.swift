import AsciiDrawCore
import AppKit
import SwiftUI

@main
struct AsciiDrawMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("AsciiDraw") {
            DocumentScreen()
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            AsciiDrawCommands()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        NotificationCenter.default.post(name: .asciiDrawOpenFile, object: url)
    }
}

extension Notification.Name {
    static let asciiDrawOpenFile = Notification.Name("asciiDrawOpenFile")
}

struct AsciiDrawCommands: Commands {
    @FocusedValue(\.editorModel) private var model

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New") { model?.newDocument() }
                .keyboardShortcut("n", modifiers: .command)
            Button("Open…") { model?.openDocument() }
                .keyboardShortcut("o", modifiers: .command)
            Divider()
            Button("Save") { model?.save() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(model == nil)
            Button("Save As…") { model?.saveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(model == nil)
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { model?.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(model?.editor.canUndo != true)
            Button("Redo") { model?.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(model?.editor.canRedo != true)
        }
        CommandGroup(after: .pasteboard) {
            Button("Copy as Text") { model?.copyPlainText() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(model == nil)
        }
        CommandMenu("Shape") {
            Button("Duplicate") { model?.duplicateSelection() }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(model?.selection.isEmpty != false)
            Button("Delete") { model?.deleteSelection() }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(model?.selection.isEmpty != false)
            Divider()
            Button("Group") { model?.groupSelection() }
                .disabled((model?.selection.count ?? 0) < 2)
            Button("Ungroup") { model?.ungroupSelection() }
            Divider()
            Button("Zoom to Fit") { model?.zoomToFit() }
                .keyboardShortcut("0", modifiers: .command)
            Button("Actual Size") { model?.setZoom(1) }
                .keyboardShortcut("1", modifiers: .command)
        }
        CommandMenu("Export") {
            ForEach(ExportKind.allCases) { kind in
                Button(kind.title) { model?.export(kind: kind) }
                    .disabled(model == nil)
            }
        }
    }
}
