import AsciiDrawCore
import AppKit
import SwiftUI

enum AboutWindow {
    private static var panel: NSWindow?

    @MainActor
    static func show() {
        let window: NSWindow
        if let panel {
            window = panel
        } else {
            // A preferred content size that depends on the titlebar safe area
            // resizes the window, which changes the safe area, until AppKit
            // aborts the constraint pass. The size stays fixed.
            let host = NSHostingController(rootView: AboutView())
            window = NSWindow(contentViewController: host)
            window.title = "About AsciiDraw"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.isMovableByWindowBackground = true
            window.setContentSize(NSSize(width: 440, height: 468))
            panel = window
            window.center()
        }
        window.appearance = AppearanceController.shared.nsAppearance
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct AboutView: View {
    @ObservedObject private var appearance = AppearanceController.shared

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 84, height: 84)
                Text("AsciiDraw")
                    .font(.title2.weight(.semibold))
                Text("Version \(ProductVersion.semantic)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Text("A native Mac editor for ASCII diagrams. Rectangles, lines, diamonds, text, and FIGlet banners share one character grid. The picture is the text.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                fact("Author", ProductVersion.author)
                linkFact("GitHub", "github.com/aaqaishtyaq/asciidraw", ProductVersion.github)
                linkFact("Website", "v1.aaqa.dev/asciidraw", ProductVersion.website)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)

            VStack(spacing: 8) {
                Text("Copy the canvas as plain text, or export a shell, Ruby, or Python comment, plus PNG or SVG.")
                Text("The asciidraw command prints a saved document. asciidraw-mcp edits the open document over a local socket.")
            }
            .font(.caption)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Text("Requires macOS 26 or later  ·  \(ProductVersion.copyright)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
        .padding(28)
        .frame(width: 440, height: 468, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(appearance.colorScheme)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .frame(width: 72, alignment: .trailing)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
        .font(.callout)
    }

    private func linkFact(_ label: String, _ title: String, _ url: URL) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .frame(width: 72, alignment: .trailing)
                .foregroundStyle(.secondary)
            Link(title, destination: url)
                .textSelection(.enabled)
        }
        .font(.callout)
    }
}
