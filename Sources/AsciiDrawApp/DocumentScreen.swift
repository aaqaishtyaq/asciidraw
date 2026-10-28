import AppKit
import AsciiDrawCore
import SwiftUI

struct DocumentScreen: View {
    @StateObject private var model = EditorModel()
    @ObservedObject private var appearance = AppearanceController.shared
    @State private var inspectorPresented = true
    @State private var charactersPresented = false

    private static let toolbarTools: [Tool] = [
        .select, .pan, .rect, .text, .surface, .diamond, .line, .banner, .pencil, .bucket, .picker, .eraser,
    ]

    var body: some View {
        NavigationSplitView {
            ShapeList(model: model)
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
        } detail: {
            CanvasRepresentable(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    CanvasChrome(model: model, glyph: glyph)
                }
                .navigationTitle(model.documentTitle)
                .toolbar(removing: .title)
                .toolbar { documentToolbar }
        }
        .inspector(isPresented: $inspectorPresented) {
            InspectorPane(model: model)
                .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        }
        .focusedSceneValue(\.editorModel, model)
        .preferredColorScheme(appearance.colorScheme)
        .onAppear {
            FrontDocument.model = model
            model.focusDrawing()
        }
        .frame(minWidth: 960, minHeight: 640)
    }

    @ToolbarContentBuilder
    private var documentToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            documentTitleControl
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .principal) {
            toolCluster
        }
        ToolbarItem(placement: .primaryAction) {
            ToolbarGlass(size: CGSize(width: 32, height: 32)) {
                Button {
                    charactersPresented = true
                } label: {
                    Image(systemName: "square.on.circle")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
            .help("Geometric shapes")
            .accessibilityLabel("Geometric shapes")
            .popover(isPresented: $charactersPresented, arrowEdge: .bottom) {
                CharacterPaletteView(character: glyph)
                    .frame(width: 320, height: 360)
            }
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            ToolbarGlass(size: CGSize(width: 32, height: 32)) {
                Button(action: model.copyPlainText) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
            .help("Copy the diagram as plain text")
            .accessibilityLabel("Copy text")
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            ToolbarGlass(size: CGSize(width: 52, height: 32)) {
                Button {
                    ExportMenu.present(model: model)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 52, height: 32)
                }
                .buttonStyle(.plain)
            }
            .help("Export")
            .accessibilityLabel("Export")
        }
        .sharedBackgroundVisibility(.hidden)
    }

    private var toolCluster: some View {
        HStack(spacing: 1) {
            toolToggle(.select)
            toolToggle(.pan)
            Divider()
                .frame(height: 16)
                .padding(.horizontal, 4)
            ForEach(Self.toolbarTools.dropFirst(2), id: \.self) { tool in
                toolToggle(tool)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tool-chooser")
        .accessibilityLabel("Tool chooser")
    }

    private var documentTitleControl: some View {
        ToolbarGlass {
            Button {
                DocumentTitleMenu.present(model: model)
            } label: {
                HStack(spacing: 5) {
                    Text(model.documentTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .frame(height: 32)
            }
            .buttonStyle(.plain)
        }
        .help("Document")
        .accessibilityLabel("Document \(model.documentTitle)")
    }

    private func toolToggle(_ tool: Tool) -> some View {
        let selected = model.editor.tool == tool
        return Button {
            model.selectTool(tool)
        } label: {
            Image(systemName: tool.symbolName)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 28, height: 28)
                .foregroundStyle(selected ? Color(nsColor: .controlBackgroundColor) : Color.primary)
                .background {
                    if selected {
                        Circle().fill(Color.primary)
                    }
                }
        }
        .buttonStyle(HoverPlateButtonStyle(selected: selected))
        .help("\(tool.title) (\(tool.shortcutLabel)). Space pans temporarily.")
        .accessibilityLabel("\(tool.title) \(tool.shortcutLabel)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var glyph: Binding<String> {
        Binding(
            get: { String(model.editor.pencilCharacter) },
            set: { model.editor.pencilCharacter = $0.first ?? "x" }
        )
    }
}

/// AppKit menu. A SwiftUI popover attached to this toolbar button never received clicks.
@MainActor
private enum DocumentTitleMenu {
    static func present(model: EditorModel) {
        guard let event = NSApp.currentEvent, let view = event.window?.contentView else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.showsStateColumn = true
        func add(_ title: String, _ run: @escaping @MainActor () -> Void) {
            menu.addItem(ActionMenuItem(title: title, run: run))
        }
        add("New") { model.newDocument() }
        add("Open…") { model.openDocument() }
        add("Save") { model.save() }
        add("Save As…") { model.saveAs() }
        menu.addItem(.separator())
        func zoom(_ title: String, _ value: Double) {
            let item = ActionMenuItem(title: title) { model.setZoom(value) }
            item.state = abs(model.zoom - value) < 0.03 ? .on : .off
            menu.addItem(item)
        }
        zoom("50%", 0.5)
        zoom("75%", 0.75)
        zoom("100%", 1)
        zoom("150%", 1.5)
        zoom("200%", 2)
        add("Zoom to Fit") { model.zoomToFit() }
        let point = menuPoint(for: event, in: view)
        // Pop after the click ends. Opening inside mouseUp makes the menu treat that click as a dismissal.
        DispatchQueue.main.async {
            menu.popUp(positioning: nil, at: point, in: view)
        }
    }
}

/// The click lands in the middle of the glass control. Anchoring there covers the title, so the menu hangs just under it.
@MainActor
private func menuPoint(for event: NSEvent, in content: NSView) -> NSPoint {
    let click = content.convert(event.locationInWindow, from: nil)
    let y = content.isFlipped ? click.y + 22 : click.y - 22
    return NSPoint(x: click.x - 46, y: y)
}

/// Same popup path as the title. A SwiftUI `Menu` draws its own highlight and drops the hover plate.
@MainActor
private enum ExportMenu {
    static func present(model: EditorModel) {
        guard let event = NSApp.currentEvent, let view = event.window?.contentView else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for kind in ExportKind.allCases {
            menu.addItem(ActionMenuItem(title: kind.title) { model.export(kind: kind) })
        }
        let point = menuPoint(for: event, in: view)
        DispatchQueue.main.async {
            menu.popUp(positioning: nil, at: point, in: view)
        }
    }
}

private final class ActionMenuItem: NSMenuItem {
    private let run: @MainActor () -> Void

    init(title: String, run: @escaping @MainActor () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func invoke() {
        let run = run
        DispatchQueue.main.async {
            MainActor.assumeIsolated(run)
        }
    }
}

/// Floating liquid-glass controls, the way Freeform parks zoom and tool options on the canvas.
private struct ChromeTip: Equatable {
    var title: String
    var frame: CGRect
}

private struct CanvasChrome: View {
    @ObservedObject var model: EditorModel
    @Binding var glyph: String
    @State private var tip: ChromeTip?

    private var stamps: Bool {
        switch model.editor.tool {
        case .pencil, .bucket, .eraser, .picker: return true
        default: return false
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            zoomPill
            Spacer(minLength: 12)
                .allowsHitTesting(false)
            if !model.selection.isEmpty {
                selectionPill
            } else if stamps {
                glyphPill
            }
            Spacer(minLength: 12)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .overlay { chromeTip }
    }

    /// Name of the icon under the pointer. Drawn outside the glass so the pill does not clip it.
    @ViewBuilder
    private var chromeTip: some View {
        GeometryReader { proxy in
            if let tip {
                let origin = proxy.frame(in: .global)
                Text(tip.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
                    }
                    .fixedSize()
                    .position(
                        x: tip.frame.midX - origin.minX,
                        y: tip.frame.minY - origin.minY - 18
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .bottom)))
            }
        }
        .allowsHitTesting(false)
        .animation(.spring(duration: 0.16, bounce: 0.2), value: tip)
    }

    private var zoomPill: some View {
        GlassPill {
            HStack(spacing: 2) {
                chromeIcon("minus", "Zoom Out", false) {
                    model.zoom(by: 1 / 1.15, anchor: model.viewportCenter)
                }
                ChromeControl(title: "Actual size", tip: $tip) {
                    model.setZoom(1)
                } label: {
                    Text("\(Int((model.zoom * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .frame(minWidth: 44, minHeight: 26)
                }
                chromeIcon("plus", "Zoom In", false) {
                    model.zoom(by: 1.15, anchor: model.viewportCenter)
                }
                Divider().frame(height: 14)
                chromeIcon("arrow.up.left.and.arrow.down.right", "Zoom to Fit", false) {
                    model.zoomToFit()
                }
                Divider().frame(height: 14)
                Text("\(model.hover.x + 1), \(model.hover.y + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 64)
                    .accessibilityLabel("Cell \(model.hover.x + 1), \(model.hover.y + 1)")
            }
            .padding(.horizontal, 6)
        }
    }

    private var glyphPill: some View {
        GlassPill {
            HStack(spacing: 6) {
                Text(model.editor.tool.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Glyph", text: $glyph)
                    .font(.system(.body, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .frame(width: 36)
                    .textFieldStyle(.roundedBorder)
                    .accentHover(.rounded(6), cursor: nil)
                    .accessibilityLabel("Pencil character")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
    }

    private var selectionPill: some View {
        GlassPill {
            HStack(spacing: 2) {
                chromeIcon("plus.square.on.square", "Duplicate", false, model.duplicateSelection)
                chromeIcon("trash", "Delete", false, model.deleteSelection)
                chromeIcon("rectangle.3.group", "Group", model.selection.count < 2, model.groupSelection)
                chromeIcon("rectangle.split.2x1", "Ungroup", model.selection.compactMap { model.editor.object($0)?.groupID }.isEmpty, model.ungroupSelection)
                chromeIcon("square.2.layers.3d.top.filled", "Bring to Front", false, model.bringSelectionToFront)
                chromeIcon("square.2.layers.3d.bottom.filled", "Send to Back", false, model.sendSelectionToBack)
                chromeIcon(model.selectionLocked ? "lock.fill" : "lock.open", model.selectionLocked ? "Unlock" : "Lock", false, model.toggleLockSelection)
                chromeIcon(model.selectionHidden ? "eye.slash" : "eye", model.selectionHidden ? "Show" : "Hide", false, model.toggleHiddenSelection)
                Divider().frame(height: 14).padding(.horizontal, 2)
                chromeIcon("align.horizontal.left", "Align Left", model.selection.count < 2) { model.alignSelection(.left) }
                chromeIcon("align.horizontal.center", "Align Center", model.selection.count < 2) { model.alignSelection(.centerX) }
                chromeIcon("align.horizontal.right", "Align Right", model.selection.count < 2) { model.alignSelection(.right) }
                chromeIcon("align.vertical.top", "Align Top", model.selection.count < 2) { model.alignSelection(.top) }
                chromeIcon("align.vertical.center", "Align Middle", model.selection.count < 2) { model.alignSelection(.centerY) }
                chromeIcon("align.vertical.bottom", "Align Bottom", model.selection.count < 2) { model.alignSelection(.bottom) }
                chromeIcon("distribute.horizontal.center", "Distribute Horizontally", model.selection.count < 3) { model.distributeSelection(.horizontal) }
                chromeIcon("distribute.vertical.center", "Distribute Vertically", model.selection.count < 3) { model.distributeSelection(.vertical) }
            }
            .padding(.horizontal, 6)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("action-toolbar")
            .accessibilityLabel("Actions")
        }
    }

    private func chromeIcon(_ symbol: String, _ help: String, _ disabled: Bool, _ action: @escaping () -> Void) -> some View {
        ChromeControl(title: help, disabled: disabled, tip: $tip, action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 26)
        }
    }
}

/// Bottom-bar button. Stays hittable when disabled so the click never falls through to the canvas.
private struct ChromeControl<Label: View>: View {
    var title: String
    var disabled: Bool = false
    @Binding var tip: ChromeTip?
    var action: () -> Void
    @ViewBuilder var label: () -> Label
    @State private var frame: CGRect = .zero

    var body: some View {
        Button(action: { if !disabled { action() } }) {
            label()
        }
        .buttonStyle(HoverPlateButtonStyle(onHoverChange: updateTip))
        .opacity(disabled ? 0.35 : 1)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { frame = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, new in frame = new }
            }
            .allowsHitTesting(false)
        }
        .onHover(perform: updateTip)
        .help(title)
        .accessibilityLabel(title)
    }

    private func updateTip(_ inside: Bool) {
        guard frame.width > 1 else { return }
        if inside {
            tip = ChromeTip(title: title, frame: frame)
        } else if tip?.title == title {
            tip = nil
        }
    }
}

/// Compact toolbar glass. The system capsule stretches to the full title-bar height, which turns a single icon into a tall oval.
private struct ToolbarGlass<Content: View>: NSViewRepresentable {
    var size: CGSize?
    var content: Content

    init(size: CGSize? = nil, @ViewBuilder content: () -> Content) {
        self.size = size
        self.content = content()
    }

    func makeNSView(context: Context) -> ToolbarGlassView {
        ToolbarGlassView(root: AnyView(content), fixedSize: size)
    }

    func updateNSView(_ view: ToolbarGlassView, context: Context) {
        view.fixedSize = size
        view.host.rootView = AnyView(content)
        view.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ToolbarGlassView, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
}

private final class ToolbarGlassView: NSView {
    let glass = NSGlassEffectView()
    let host: NSHostingView<AnyView>
    var fixedSize: CGSize?

    init(root: AnyView, fixedSize: CGSize?) {
        self.fixedSize = fixedSize
        host = NSHostingView(rootView: root)
        host.sizingOptions = [.intrinsicContentSize]
        super.init(frame: NSRect(x: 0, y: 0, width: fixedSize?.width ?? 80, height: 32))
        glass.style = .regular
        glass.cornerRadius = 16
        enableInteractiveGlass(glass)
        glass.contentView = host
        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        if let fixedSize { return NSSize(width: fixedSize.width, height: fixedSize.height) }
        let fit = host.intrinsicContentSize
        let width = fit.width > 1 && fit.width < 280 ? fit.width : 96
        return NSSize(width: width, height: 32)
    }

    override func layout() {
        super.layout()
        glass.cornerRadius = min(16, bounds.height / 2)
        if host.frame.size != glass.bounds.size {
            host.frame = glass.bounds
        }
    }
}

/// macOS 27 adds `effectIsInteractive`. The macOS 26 SDK does not declare it,
/// so the GitHub runner can still compile, and the setter is a no-op before 27.
private func enableInteractiveGlass(_ glass: NSGlassEffectView) {
    let setter = NSSelectorFromString("setEffectIsInteractive:")
    guard glass.responds(to: setter) else { return }
    typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
    let apply = unsafeBitCast(glass.method(for: setter), to: Setter.self)
    apply(glass, setter, true)
}

/// Content-sized liquid glass. SwiftUI glass styles inside a split column loop Auto Layout.
private struct GlassPill<Content: View>: NSViewRepresentable {
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> GlassPillView {
        GlassPillView(root: AnyView(content))
    }

    func updateNSView(_ view: GlassPillView, context: Context) {
        view.host.rootView = AnyView(content)
        view.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: GlassPillView, context: Context) -> CGSize? {
        let fit = nsView.intrinsicContentSize
        let width = fit.width > 1 && fit.width < 2400 ? fit.width : (proposal.width ?? 160)
        return CGSize(width: width, height: 36)
    }
}

private final class GlassPillView: NSView {
    let glass = NSGlassEffectView()
    let host: NSHostingView<AnyView>

    init(root: AnyView) {
        host = NSHostingView(rootView: root)
        host.sizingOptions = [.intrinsicContentSize]
        super.init(frame: NSRect(x: 0, y: 0, width: 160, height: 36))
        glass.style = .regular
        glass.cornerRadius = 18
        enableInteractiveGlass(glass)
        glass.contentView = host
        glass.translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.masksToBounds = false
        let drop = NSShadow()
        drop.shadowColor = NSColor.black.withAlphaComponent(0.22)
        drop.shadowOffset = NSSize(width: 0, height: -2)
        drop.shadowBlurRadius = 12
        shadow = drop
        identifier = NSUserInterfaceItemIdentifier("canvas-chrome")
        addSubview(glass)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        let fit = host.intrinsicContentSize
        let width = fit.width > 1 && fit.width < 2400 ? fit.width : 160
        return NSSize(width: width, height: 36)
    }

    override func layout() {
        super.layout()
        if host.frame.size != glass.bounds.size {
            host.frame = glass.bounds
        }
    }

    /// Empty parts of the pill still take the click, so it cannot fall through and clear the selection.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        return super.hitTest(point) ?? self
    }

    override func mouseDown(with event: NSEvent) {}
}

private struct ShapeList: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        shapeList
    }

    private var shapeList: some View {
        List(selection: listSelection) {
            Section("Shapes") {
                ForEach(model.editor.document.groups) { group in
                    DisclosureGroup {
                        ForEach(members(of: group)) { object in
                            shapeRow(object)
                                .tag(object.id)
                        }
                    } label: {
                        Label(group.name, systemImage: "folder")
                            .lineLimit(1)
                    }
                }
                ForEach(ungroupedLayers) { object in
                    shapeRow(object)
                        .tag(object.id)
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityIdentifier("shape-list")
        .accessibilityLabel("Shape list")
        .navigationSplitViewColumnWidth(min: 210, ideal: 240)
    }

    /// A click in the detail used to make the sidebar list publish an empty selection and hide this bar.
    private var listSelection: Binding<Set<UUID>> {
        Binding(
            get: { model.selection },
            set: { newValue in
                if newValue.isEmpty, !model.selection.isEmpty, !clickIsInShapeList {
                    return
                }
                model.selection = newValue
            }
        )
    }

    private var clickIsInShapeList: Bool {
        guard let event = NSApp.currentEvent else { return true }
        switch event.type {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
            break
        default:
            return true
        }
        guard let content = event.window?.contentView else { return true }
        var view = content.hitTest(event.locationInWindow)
        while let current = view {
            if current is NSOutlineView || current is NSTableView { return true }
            view = current.superview
        }
        return false
    }

    private var ungroupedLayers: [DrawObject] {
        model.layers.filter { $0.groupID == nil }
    }

    private func members(of group: DrawGroup) -> [DrawObject] {
        let ids = Set(group.memberIDs)
        return model.layers.filter { ids.contains($0.id) }
    }

    private func shapeRow(_ object: DrawObject) -> some View {
        HStack(spacing: 8) {
                        Image(systemName: symbol(object))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(object.name)
                                .lineLimit(1)
                            Text(kindName(object))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Button {
                            model.toggleLock(object.id)
                        } label: {
                            Image(systemName: object.locked ? "lock.fill" : "lock.open")
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(HoverPlateButtonStyle())
                        .help(object.locked ? "Unlock" : "Lock")
                        .accessibilityLabel(object.locked ? "Unlock \(object.name)" : "Lock \(object.name)")
                        Button {
                            model.toggleHidden(object.id)
                        } label: {
                            Image(systemName: object.hidden ? "eye.slash" : "eye")
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(HoverPlateButtonStyle())
                        .help(object.hidden ? "Show" : "Hide")
                        .accessibilityLabel(object.hidden ? "Show \(object.name)" : "Hide \(object.name)")
                    }
                    .opacity(object.hidden ? 0.45 : 1)
    }

    private func symbol(_ object: DrawObject) -> String {
        switch object.kind {
        case .rectangle(let props):
            return props.border == nil && props.fillGlyph != nil ? "square.grid.3x3" : "rectangle"
        case .diamond: return "diamond"
        case .text: return "textformat"
        case .line: return "line.diagonal"
        case .banner: return "bold"
        }
    }

    private func kindName(_ object: DrawObject) -> String {
        switch object.kind {
        case .rectangle(let props):
            return props.border == nil && props.fillGlyph != nil ? "Surface" : "Rectangle"
        case .diamond: return "Diamond"
        case .text: return "Text"
        case .line: return "Line"
        case .banner: return "Banner"
        }
    }
}

private struct InspectorPane: View {
    @ObservedObject var model: EditorModel
    @State private var showingFontPreview = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Inspector")
                    .font(.headline)
                inspectorActions
                if model.selection.count > 1 {
                    Text("\(model.selection.count) shapes selected")
                        .foregroundStyle(.secondary)
                    multiActions
                } else if let id = model.selection.first, let object = model.editor.object(id) {
                    single(object)
                } else if paletteTool {
                    characterPalette
                } else {
                    Text("No Selection")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    documentSettings
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("selection-inspector")
        .accessibilityLabel("Selection inspector")
    }

    private var inspectorActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                inspectorIcon("align.horizontal.left", "Align Left", model.selection.count < 2) { model.alignSelection(.left) }
                inspectorIcon("align.horizontal.center", "Align Center", model.selection.count < 2) { model.alignSelection(.centerX) }
                inspectorIcon("align.horizontal.right", "Align Right", model.selection.count < 2) { model.alignSelection(.right) }
                inspectorIcon("align.vertical.top", "Align Top", model.selection.count < 2) { model.alignSelection(.top) }
                inspectorIcon("align.vertical.center", "Align Middle", model.selection.count < 2) { model.alignSelection(.centerY) }
                inspectorIcon("align.vertical.bottom", "Align Bottom", model.selection.count < 2) { model.alignSelection(.bottom) }
            }
            HStack(spacing: 4) {
                inspectorIcon("distribute.horizontal.center", "Distribute Horizontally", model.selection.count < 3) { model.distributeSelection(.horizontal) }
                inspectorIcon("distribute.vertical.center", "Distribute Vertically", model.selection.count < 3) { model.distributeSelection(.vertical) }
                inspectorIcon("rectangle.3.group", "Group", model.selection.count < 2, model.groupSelection)
                inspectorIcon("rectangle.split.2x1", "Ungroup", model.selection.compactMap { model.editor.object($0)?.groupID }.isEmpty, model.ungroupSelection)
                inspectorIcon(model.selectionLocked ? "lock.fill" : "lock.open", model.selectionLocked ? "Unlock" : "Lock", model.selection.isEmpty, model.toggleLockSelection)
                inspectorIcon(model.selectionHidden ? "eye.slash" : "eye", model.selectionHidden ? "Show" : "Hide", model.selection.isEmpty, model.toggleHiddenSelection)
            }
        }
    }

    private func inspectorIcon(_ symbol: String, _ help: String, _ disabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 26, height: 22)
        }
        .buttonStyle(HoverPlateButtonStyle(shape: .rounded(6)))
        .disabled(disabled)
        .help(help)
        .accessibilityLabel(help)
    }

    private var multiActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Group", action: model.groupSelection)
                .hoverPlate()
            Button("Delete", role: .destructive, action: model.deleteSelection)
                .hoverPlate()
        }
    }

    @ViewBuilder
    private func single(_ object: DrawObject) -> some View {
        TextField("Name", text: Binding(
            get: { model.editor.object(object.id)?.name ?? "" },
            set: { model.editor.setName(object.id, $0) }
        ))
        .textFieldStyle(.roundedBorder)
        .accentHover(cursor: nil)
        HStack {
            Toggle("Locked", isOn: Binding(
                get: { model.editor.object(object.id)?.locked ?? false },
                set: { model.editor.setLocked(object.id, $0) }
            ))
            .hoverPlate()
            Toggle("Hidden", isOn: Binding(
                get: { model.editor.object(object.id)?.hidden ?? false },
                set: { model.editor.setHidden(object.id, $0) }
            ))
            .hoverPlate()
        }
        HStack {
            Button("Front") { model.editor.bringToFront(object.id) }
                .hoverPlate()
            Button("Back") { model.editor.sendToBack(object.id) }
                .hoverPlate()
        }
        if case .line(let props) = object.kind {
            lineFields(object.id, props)
        } else {
            frameFields(object)
        }
        switch object.kind {
        case .rectangle(let props):
            rectangleFields(object.id, props)
        case .diamond:
            EmptyView()
        case .text(let props):
            textFields(object.id, props)
        case .line:
            EmptyView()
        case .banner(let props):
            bannerFields(object.id, props)
        }
    }

    private var paletteTool: Bool {
        switch model.editor.tool {
        case .pencil, .eraser, .bucket, .picker:
            return true
        case .select, .pan, .rect, .text, .surface, .diamond, .line, .banner:
            return false
        }
    }

    private var pencilGlyph: Binding<String> {
        Binding(
            get: { String(model.editor.pencilCharacter) },
            set: { model.editor.pencilCharacter = $0.first ?? "x" }
        )
    }

    private var documentSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Document")
                .font(.headline)
            labeledMenu("Alphabet") {
                AlignedPopup(
                    items: [DocumentAlphabet.unicode, .ascii],
                    selection: model.editor.document.alphabet,
                    itemTitle: { $0 == .ascii ? "ASCII" : "Unicode" },
                    onSelect: { model.editor.setAlphabet($0) }
                )
            }
        }
    }

    private func frameFields(_ object: DrawObject) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Width")
                TextField("Width", value: frame(\.width, object: object), format: .number)
                    .frame(width: 52)
                    .accentHover(cursor: nil)
                Text("Height")
                TextField("Height", value: frame(\.height, object: object), format: .number)
                    .frame(width: 52)
                    .accentHover(cursor: nil)
            }
            HStack(spacing: 8) {
                Text("X")
                TextField("X", value: frame(\.x, object: object), format: .number)
                    .frame(width: 52)
                    .accentHover(cursor: nil)
                Text("Y")
                TextField("Y", value: frame(\.y, object: object), format: .number)
                    .frame(width: 52)
                    .accentHover(cursor: nil)
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    private func frame(_ keyPath: WritableKeyPath<GridRect, Int>, object: DrawObject) -> Binding<Int> {
        Binding(
            get: { model.editor.object(object.id)?.frame[keyPath: keyPath] ?? 0 },
            set: { newValue in
                guard var frame = model.editor.object(object.id)?.frame else { return }
                frame[keyPath: keyPath] = newValue
                if keyPath == \.width { frame.width = max(2, newValue) }
                if keyPath == \.height { frame.height = max(2, newValue) }
                model.editor.setFrame(object.id, frame)
            }
        )
    }

    private func rectangleFields(_ id: UUID, _ props: RectangleProps) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            labeledMenu("Border") {
                AlignedPopup(
                    items: BorderChoice.allCases,
                    selection: BorderChoice(model.rectangle(id)?.border),
                    itemTitle: \.label,
                    onSelect: { choice in model.editor.setRectangle(id) { $0.border = choice.style } }
                )
            }
            TextField("Fill", text: Binding(
                get: { model.rectangle(id)?.fill ?? "" },
                set: { value in
                    model.editor.setRectangle(id) { $0.fill = value.isEmpty ? nil : String(value.prefix(1)) }
                }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.body.monospaced())
            .accentHover(cursor: nil)
            Toggle("Shadow", isOn: Binding(
                get: { model.rectangle(id)?.shadow != nil },
                set: { on in
                    model.editor.setRectangle(id) {
                        $0.shadow = on ? ($0.shadow ?? ShadowStyle(character: "#", dx: 1, dy: 1)) : nil
                    }
                }
            ))
            .hoverPlate()
            if model.rectangle(id)?.border != nil {
                Toggle("Blended", isOn: Binding(
                    get: { model.rectangle(id)?.blended ?? true },
                    set: { value in model.editor.setRectangle(id) { $0.blended = value } }
                ))
                .hoverPlate()
            }
            if let shadow = model.rectangle(id)?.shadow {
                TextField("Shadow character", text: Binding(
                    get: { shadow.character },
                    set: { value in
                        model.editor.setRectangle(id) { props in
                            let glyph = value.isEmpty ? "#" : String(value.prefix(1))
                            props.shadow?.character = glyph
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .accentHover(cursor: nil)
                Stepper("dx \(shadow.dx)", value: Binding(
                    get: { model.rectangle(id)?.shadow?.dx ?? 1 },
                    set: { value in model.editor.setRectangle(id) { $0.shadow?.dx = value } }
                ), in: -8...8)
                Stepper("dy \(shadow.dy)", value: Binding(
                    get: { model.rectangle(id)?.shadow?.dy ?? 1 },
                    set: { value in model.editor.setRectangle(id) { $0.shadow?.dy = value } }
                ), in: -8...8)
            }
        }
    }

    private func textFields(_ id: UUID, _ props: TextProps) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Text", isOn: Binding(
                get: { !(model.text(id)?.text.isEmpty ?? true) },
                set: { on in
                    model.editor.setText(id) { props in
                        if on, props.text.isEmpty { props.text = "Text" }
                        if !on { props.text = "" }
                    }
                }
            ))
            .hoverPlate()
            TextEditor(text: Binding(
                get: { model.text(id)?.text ?? "" },
                set: { value in model.editor.setText(id) { $0.text = value } }
            ))
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: 56)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
            .accentHover(.rounded(6), cursor: nil)
            iconChoices("Alignment", [
                (.left, "text.alignleft"),
                (.center, "text.aligncenter"),
                (.right, "text.alignright"),
            ], get: { model.text(id)?.alignment ?? props.alignment }) { value in
                model.editor.setText(id) { $0.alignment = value }
            }
            iconChoices("Position", [
                (.top, "align.vertical.top"),
                (.middle, "align.vertical.center"),
                (.bottom, "align.vertical.bottom"),
            ], get: { model.text(id)?.position ?? props.position }) { value in
                model.editor.setText(id) { $0.position = value }
            }
            labeledMenu("Font") {
                AlignedPopup(
                    items: fontChoices(model.text(id)?.fontName),
                    selection: model.text(id)?.fontName ?? "",
                    itemTitle: { $0.isEmpty ? "None" : $0 },
                    onSelect: { value in model.editor.setText(id) { $0.fontName = value.isEmpty ? nil : value } }
                )
            }
            Button("Preview") { showingFontPreview = true }
                .buttonStyle(.bordered)
                .hoverPlate()
                .popover(isPresented: $showingFontPreview) {
                    Text(TextLayout.rows(for: model.text(id) ?? props).joined(separator: "\n"))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(minWidth: 180, alignment: .leading)
                }
            iconChoices("Sweep", [
                (.right, "arrow.right"),
                (.left, "arrow.left"),
                (.down, "arrow.down"),
                (.up, "arrow.up"),
            ], get: { model.text(id)?.sweep ?? props.sweep }) { value in
                model.editor.setText(id) { $0.sweep = value }
            }
            iconChoices("Movement", [
                (.none, "minus"),
                (.top, "arrow.up.to.line"),
                (.bottom, "arrow.down.to.line"),
                (.left, "arrow.left.to.line"),
                (.right, "arrow.right.to.line"),
            ], get: { model.text(id)?.lineMovement ?? props.lineMovement }) { value in
                model.editor.setText(id) { $0.lineMovement = value }
            }
            Toggle("Text inside border", isOn: Binding(
                get: { model.text(id)?.textInsideBorder ?? true },
                set: { value in model.editor.setText(id) { $0.textInsideBorder = value } }
            ))
            .hoverPlate()
            Toggle("Fill", isOn: Binding(
                get: { model.text(id)?.fill != nil },
                set: { on in
                    model.editor.setText(id) {
                        $0.fill = on ? String(model.editor.pencilCharacter) : nil
                    }
                }
            ))
            .hoverPlate()
            if model.text(id)?.fill != nil {
                TextField("Fill character", text: Binding(
                    get: { model.text(id)?.fill ?? "" },
                    set: { value in
                        model.editor.setText(id) { $0.fill = value.isEmpty ? nil : String(value.prefix(1)) }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .frame(width: 80)
                .accentHover(cursor: nil)
            }
            Toggle("Border", isOn: Binding(
                get: { model.text(id)?.border != nil },
                set: { on in model.editor.setText(id) { $0.border = on ? ($0.border ?? .single) : nil } }
            ))
            .hoverPlate()
            if model.text(id)?.border != nil {
                labeledMenu("Type") {
                    AlignedPopup(
                        items: [BorderStyle.single, .double],
                        selection: model.text(id)?.border ?? .single,
                        itemTitle: { $0 == .double ? "Double" : "Single (Light)" },
                        onSelect: { style in model.editor.setText(id) { $0.border = style } }
                    )
                }
                Toggle("Blended", isOn: Binding(
                    get: { model.text(id)?.blended ?? true },
                    set: { value in model.editor.setText(id) { $0.blended = value } }
                ))
                .hoverPlate()
            }
        }
    }

    private func iconChoices<T: Hashable>(
        _ title: String,
        _ options: [(T, String)],
        get: @escaping () -> T,
        set: @escaping (T) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    let selected = get() == option.0
                    Button {
                        set(option.0)
                    } label: {
                        Image(systemName: option.1)
                            .frame(width: 22, height: 16)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 4)
                            .background(selected ? Color.accentColor.opacity(0.85) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(selected ? Color.white : Color.primary)
                    }
                    .buttonStyle(HoverPlateButtonStyle(shape: .rounded(5), selected: selected))
                    .accessibilityLabel("\(title) \(String(describing: option.0))")
                }
            }
        }
    }

    private var characterPalette: some View {
        CharacterPaletteView(character: pencilGlyph)
            .frame(minHeight: 280)
    }

    private func lineFields(_ id: UUID, _ props: LineProps) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            enumPicker("Routing", LineRouting.allCases, get: { model.line(id)?.routing ?? props.routing }, set: { value in
                model.editor.setLine(id) { $0.routing = value }
            })
            Toggle("Horizontal first", isOn: Binding(
                get: { model.line(id)?.horizontalFirst ?? true },
                set: { value in model.editor.setLine(id) { $0.horizontalFirst = value } }
            ))
            .hoverPlate()
            Stepper("Dash on \(model.line(id)?.dash.on ?? props.dash.on)", value: Binding(
                get: { model.line(id)?.dash.on ?? 1 },
                set: { value in model.editor.setLine(id) { $0.dash.on = max(1, value) } }
            ), in: 1...12)
            Stepper("Dash off \(model.line(id)?.dash.off ?? props.dash.off)", value: Binding(
                get: { model.line(id)?.dash.off ?? 0 },
                set: { value in model.editor.setLine(id) { $0.dash.off = max(0, value) } }
            ), in: 0...12)
            labeledMenu("Start") {
                AlignedPopup(
                    items: CapChoice.allCases,
                    selection: CapChoice(model.line(id)?.startCap ?? .none),
                    itemTitle: \.label,
                    onSelect: { choice in model.editor.setLine(id) { $0.startCap = choice.cap } }
                )
            }
            labeledMenu("End") {
                AlignedPopup(
                    items: CapChoice.allCases,
                    selection: CapChoice(model.line(id)?.endCap ?? .none),
                    itemTitle: \.label,
                    onSelect: { choice in model.editor.setLine(id) { $0.endCap = choice.cap } }
                )
            }
            LabeledContent("Start") { Text("\(props.start.x), \(props.start.y)").monospacedDigit() }
            LabeledContent("End") { Text("\(props.end.x), \(props.end.y)").monospacedDigit() }
        }
    }

    private func bannerFields(_ id: UUID, _ props: BannerProps) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Text", text: Binding(
                get: { model.banner(id)?.text ?? "" },
                set: { value in model.editor.setBanner(id) { $0.text = value } }
            ))
            .textFieldStyle(.roundedBorder)
            .accentHover(cursor: nil)
            labeledMenu("Font") {
                AlignedPopup(
                    items: fontChoices(model.banner(id)?.fontName ?? props.fontName),
                    selection: model.banner(id)?.fontName ?? props.fontName,
                    itemTitle: { $0.isEmpty ? "None" : $0 },
                    onSelect: { name in
                        model.editor.setBanner(id) {
                            $0.fontName = name
                            $0.customFLF = nil
                        }
                    }
                )
            }
            if model.banner(id)?.customFLF != nil {
                Text("Custom FIGlet font loaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Load .flf…") { model.loadFont(for: id) }
                .hoverPlate()
            enumPicker("Align", AsciiDrawCore.TextAlignment.allCases, get: { model.banner(id)?.alignment ?? props.alignment }, set: { value in
                model.editor.setBanner(id) { $0.alignment = value }
            })
            enumPicker("Position", TextVerticalPosition.allCases, get: { model.banner(id)?.position ?? props.position }, set: { value in
                model.editor.setBanner(id) { $0.position = value }
            })
        }
    }

    private func enumPicker<T: RawRepresentable & CaseIterable & Hashable>(
        _ title: String,
        _ values: T.AllCases,
        get: @escaping () -> T,
        set: @escaping (T) -> Void
    ) -> some View where T.RawValue == String, T: Identifiable, T.ID == String {
        labeledMenu(title) {
            AlignedPopup(items: Array(values), selection: get(), itemTitle: \.rawValue, onSelect: set)
        }
    }

    /// Bundled names, plus a custom name when the shape already uses one.
    private func fontChoices(_ current: String?) -> [String] {
        var names = [""] + BundledFonts.names
        if let current, !current.isEmpty, !names.contains(current) {
            names.append(current)
        }
        return names
    }

    /// Label sits outside the popup, so the open menu cannot paint across the title.
    private func labeledMenu<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            content()
                .fixedSize()
                .accessibilityLabel(title)
        }
    }
}

private extension EditorModel {
    func rectangle(_ id: UUID) -> RectangleProps? {
        if case .rectangle(let props) = object(id)?.kind { return props }
        return nil
    }

    func text(_ id: UUID) -> TextProps? {
        if case .text(let props) = object(id)?.kind { return props }
        return nil
    }

    func line(_ id: UUID) -> LineProps? {
        if case .line(let props) = object(id)?.kind { return props }
        return nil
    }

    func banner(_ id: UUID) -> BannerProps? {
        if case .banner(let props) = object(id)?.kind { return props }
        return nil
    }

    func object(_ id: UUID) -> DrawObject? { editor.object(id) }
}

private enum BorderChoice: String, CaseIterable, Identifiable {
    case none, single, double
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "None"
        case .single: return "Single (Light)"
        case .double: return "Double"
        }
    }
    var style: BorderStyle? {
        switch self {
        case .none: return nil
        case .single: return .single
        case .double: return .double
        }
    }
    init(_ style: BorderStyle?) {
        switch style {
        case nil: self = .none
        case .single: self = .single
        case .double: self = .double
        }
    }
}

private enum CapChoice: String, CaseIterable, Identifiable {
    case none, arrow, many, oneOrMany, zeroOrMany
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "None"
        case .arrow: return "Arrow"
        case .many: return "Crow’s foot, many"
        case .oneOrMany: return "Crow’s foot, one or many"
        case .zeroOrMany: return "Crow’s foot, zero or many"
        }
    }
    var cap: LineCap {
        switch self {
        case .none: return .none
        case .arrow: return .arrow
        case .many: return .crowsFoot(.many)
        case .oneOrMany: return .crowsFoot(.oneOrMany)
        case .zeroOrMany: return .crowsFoot(.zeroOrMany)
        }
    }
    init(_ cap: LineCap) {
        switch cap {
        case .none: self = .none
        case .arrow: self = .arrow
        case .crowsFoot(.many): self = .many
        case .crowsFoot(.oneOrMany): self = .oneOrMany
        case .crowsFoot(.zeroOrMany): self = .zeroOrMany
        }
    }
}

extension AsciiDrawCore.TextAlignment: Identifiable { public var id: String { rawValue } }
extension TextVerticalPosition: Identifiable { public var id: String { rawValue } }
extension LineSweep: Identifiable { public var id: String { rawValue } }
extension LineMovement: Identifiable { public var id: String { rawValue } }
extension LineRouting: Identifiable { public var id: String { rawValue } }
