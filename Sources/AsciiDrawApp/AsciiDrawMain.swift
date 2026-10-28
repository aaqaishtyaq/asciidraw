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
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            AsciiDrawCommands()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        AppearanceController.shared.apply()
        EditorBridge.shared.start()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        EditorBridge.shared.stop()
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
    @ObservedObject private var appearance = AppearanceController.shared

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
                .keyboardShortcut("g", modifiers: .command)
                .disabled((model?.selection.count ?? 0) < 2)
            Button("Ungroup") { model?.ungroupSelection() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Divider()
            Button("Bring to Front") { model?.bringSelectionToFront() }
                .disabled(model?.selection.isEmpty != false)
            Button("Send to Back") { model?.sendSelectionToBack() }
                .disabled(model?.selection.isEmpty != false)
            Button(model?.selectionLocked == true ? "Unlock" : "Lock") { model?.toggleLockSelection() }
                .disabled(model?.selection.isEmpty != false)
            Button(model?.selectionHidden == true ? "Show" : "Hide") { model?.toggleHiddenSelection() }
                .disabled(model?.selection.isEmpty != false)
            Divider()
            Button("Align Left") { model?.alignSelection(.left) }
                .disabled((model?.selection.count ?? 0) < 2)
            Button("Align Center") { model?.alignSelection(.centerX) }
                .disabled((model?.selection.count ?? 0) < 2)
            Button("Align Right") { model?.alignSelection(.right) }
                .disabled((model?.selection.count ?? 0) < 2)
            Button("Align Top") { model?.alignSelection(.top) }
                .disabled((model?.selection.count ?? 0) < 2)
            Button("Align Middle") { model?.alignSelection(.centerY) }
                .disabled((model?.selection.count ?? 0) < 2)
            Button("Align Bottom") { model?.alignSelection(.bottom) }
                .disabled((model?.selection.count ?? 0) < 2)
            Button("Distribute Horizontally") { model?.distributeSelection(.horizontal) }
                .disabled((model?.selection.count ?? 0) < 3)
            Button("Distribute Vertically") { model?.distributeSelection(.vertical) }
                .disabled((model?.selection.count ?? 0) < 3)
            Divider()
            Button("Zoom to Fit") { model?.zoomToFit() }
                .keyboardShortcut("0", modifiers: .command)
            Button("Actual Size") { model?.setZoom(1) }
                .keyboardShortcut("1", modifiers: .command)
        }
        CommandGroup(after: .toolbar) {
            Picker("Appearance", selection: $appearance.choice) {
                Text("System").tag(AppearanceChoice.system)
                Text("Light").tag(AppearanceChoice.light)
                Text("Dark").tag(AppearanceChoice.dark)
            }
        }
        CommandMenu("Export") {
            ForEach(ExportKind.allCases) { kind in
                Button(kind.title) { model?.export(kind: kind) }
                    .disabled(model == nil)
            }
        }
    }
}
