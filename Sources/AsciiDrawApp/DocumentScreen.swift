import AsciiDrawCore
import SwiftUI

struct DocumentScreen: View {
    @StateObject private var model = EditorModel()
    @State private var inspectorPresented = true

    var body: some View {
        NavigationSplitView {
            ShapeList(model: model)
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
        } detail: {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ToolPalette(model: model)
                    CanvasRepresentable(model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                StatusBar(model: model)
            }
            .navigationTitle(model.documentTitle)
            .navigationSubtitle("AsciiDraw")
        }
        .inspector(isPresented: $inspectorPresented) {
            InspectorPane(model: model)
                .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        }
        .toolbar { toolbar }
        .focusedSceneValue(\.editorModel, model)
        .onAppear { model.focusDrawing() }
        .frame(minWidth: 960, minHeight: 640)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                model.zoom(by: 1 / 1.15, anchor: CGPoint(x: model.viewport.width / 2, y: model.viewport.height / 2))
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("Zoom out")
            Button {
                model.setZoom(1)
            } label: {
                Text("\(Int((model.zoom * 100).rounded()))%")
                    .font(.body.monospacedDigit())
                    .frame(minWidth: 48)
            }
            .help("Actual size")
            Button {
                model.zoom(by: 1.15, anchor: CGPoint(x: model.viewport.width / 2, y: model.viewport.height / 2))
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("Zoom in")
            Button {
                model.zoomToFit()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .help("Zoom to visible shapes")
        }
        ToolbarItemGroup {
            Button("Group", action: model.groupSelection)
                .disabled(model.selection.count < 2)
            Button("Ungroup", action: model.ungroupSelection)
                .disabled(model.selection.compactMap { model.editor.object($0)?.groupID }.isEmpty)
            Button {
                model.deleteSelection()
            } label: {
                Image(systemName: "trash")
            }
            .disabled(model.selection.isEmpty)
            .help("Delete")
        }
    }
}

private struct ToolPalette: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Tool.allCases, id: \.self) { tool in
                Button {
                    model.selectTool(tool)
                } label: {
                    VStack(spacing: 1) {
                        Image(systemName: tool.symbolName)
                            .font(.system(size: 15, weight: .medium))
                            .frame(height: 18)
                        Text(tool.shortcutLabel)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                    }
                    .frame(width: 52, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(model.editor.tool == tool ? Color.accentColor.opacity(0.22) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .help("\(tool.title) (\(tool.shortcutLabel)). Space pans temporarily.")
                .accessibilityLabel("\(tool.title) \(tool.shortcutLabel)")
            }
            Divider().padding(.vertical, 6)
            TextField("Glyph", text: glyph)
                .font(.system(.body, design: .monospaced))
                .multilineTextAlignment(.center)
                .frame(width: 44)
                .accessibilityLabel("Pencil character")
            Text("Space")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text("pan")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .frame(width: 72)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tool-chooser")
        .accessibilityLabel("Tool chooser")
    }

    private var glyph: Binding<String> {
        Binding(
            get: { String(model.editor.pencilCharacter) },
            set: { model.editor.pencilCharacter = $0.first ?? "x" }
        )
    }
}

private struct ShapeList: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        List(selection: $model.selection) {
            Section("Shapes") {
                ForEach(model.layers) { object in
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
                        }
                        .buttonStyle(.borderless)
                        .help(object.locked ? "Unlock" : "Lock")
                        .accessibilityLabel(object.locked ? "Unlock \(object.name)" : "Lock \(object.name)")
                        Button {
                            model.toggleHidden(object.id)
                        } label: {
                            Image(systemName: object.hidden ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .help(object.hidden ? "Show" : "Hide")
                        .accessibilityLabel(object.hidden ? "Show \(object.name)" : "Hide \(object.name)")
                    }
                    .tag(object.id)
                    .opacity(object.hidden ? 0.45 : 1)
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityIdentifier("shape-list")
        .accessibilityLabel("Shape list")
        .navigationSplitViewColumnWidth(min: 210, ideal: 240)
    }

    private func symbol(_ object: DrawObject) -> String {
        switch object.kind {
        case .rectangle: return "rectangle"
        case .diamond: return "diamond"
        case .text: return "textformat"
        case .line: return "line.diagonal"
        case .banner: return "bold"
        }
    }

    private func kindName(_ object: DrawObject) -> String {
        switch object.kind {
        case .rectangle: return "Rectangle"
        case .diamond: return "Diamond"
        case .text: return "Text"
        case .line: return "Line"
        case .banner: return "Banner"
        }
    }
}

private struct StatusBar: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        HStack(spacing: 16) {
            Text(model.editor.activeTool.title)
            Text("\(model.hover.x), \(model.hover.y)")
                .monospacedDigit()
            Text(String(model.editor.pencilCharacter))
                .font(.body.monospaced())
            Spacer()
            Text("\(model.editor.document.objects.count) shapes")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
    }
}

private struct InspectorPane: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Inspector")
                    .font(.headline)
                if model.selection.count > 1 {
                    Text("\(model.selection.count) shapes selected")
                        .foregroundStyle(.secondary)
                    multiActions
                } else if let id = model.selection.first, let object = model.editor.object(id) {
                    single(object)
                } else {
                    Text("Select a shape to edit its border, text, line, or banner.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    pencilField
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("selection-inspector")
        .accessibilityLabel("Selection inspector")
    }

    private var multiActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Group", action: model.groupSelection)
            Button("Delete", role: .destructive, action: model.deleteSelection)
        }
    }

    @ViewBuilder
    private func single(_ object: DrawObject) -> some View {
        TextField("Name", text: Binding(
            get: { model.editor.object(object.id)?.name ?? "" },
            set: { model.editor.setName(object.id, $0) }
        ))
        .textFieldStyle(.roundedBorder)
        HStack {
            Toggle("Locked", isOn: Binding(
                get: { model.editor.object(object.id)?.locked ?? false },
                set: { model.editor.setLocked(object.id, $0) }
            ))
            Toggle("Hidden", isOn: Binding(
                get: { model.editor.object(object.id)?.hidden ?? false },
                set: { model.editor.setHidden(object.id, $0) }
            ))
        }
        HStack {
            Button("Front") { model.editor.bringToFront(object.id) }
            Button("Back") { model.editor.sendToBack(object.id) }
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
        pencilField
    }

    private func frameFields(_ object: DrawObject) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
            Text("X")
            TextField("X", value: frame(\.x, object: object), format: .number).labelsHidden()
            Text("Y")
            TextField("Y", value: frame(\.y, object: object), format: .number).labelsHidden()
            Text("W")
            TextField("W", value: frame(\.width, object: object), format: .number).labelsHidden()
            Text("H")
            TextField("H", value: frame(\.height, object: object), format: .number).labelsHidden()
        }
        .textFieldStyle(.roundedBorder)
        .frame(width: 180)
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
            Picker("Border", selection: Binding(
                get: { BorderChoice(model.rectangle(id)?.border) },
                set: { choice in model.editor.setRectangle(id) { $0.border = choice.style } }
            )) {
                ForEach(BorderChoice.allCases) { Text($0.label).tag($0) }
            }
            TextField("Fill", text: Binding(
                get: { model.rectangle(id)?.fill ?? "" },
                set: { value in
                    model.editor.setRectangle(id) { $0.fill = value.isEmpty ? nil : String(value.prefix(1)) }
                }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.body.monospaced())
            Toggle("Shadow", isOn: Binding(
                get: { model.rectangle(id)?.shadow != nil },
                set: { on in
                    model.editor.setRectangle(id) {
                        $0.shadow = on ? ($0.shadow ?? ShadowStyle(character: "#", dx: 1, dy: 1)) : nil
                    }
                }
            ))
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
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: Binding(
                get: { model.text(id)?.text ?? "" },
                set: { value in model.editor.setText(id) { $0.text = value } }
            ))
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: 72)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
            enumPicker("Align", AsciiDrawCore.TextAlignment.allCases, get: { model.text(id)?.alignment ?? props.alignment }, set: { value in
                model.editor.setText(id) { $0.alignment = value }
            })
            enumPicker("Position", TextVerticalPosition.allCases, get: { model.text(id)?.position ?? props.position }, set: { value in
                model.editor.setText(id) { $0.position = value }
            })
            enumPicker("Sweep", LineSweep.allCases, get: { model.text(id)?.sweep ?? props.sweep }, set: { value in
                model.editor.setText(id) { $0.sweep = value }
            })
            enumPicker("Movement", LineMovement.allCases, get: { model.text(id)?.lineMovement ?? props.lineMovement }, set: { value in
                model.editor.setText(id) { $0.lineMovement = value }
            })
            Picker("Border", selection: Binding(
                get: { BorderChoice(model.text(id)?.border) },
                set: { choice in model.editor.setText(id) { $0.border = choice.style } }
            )) {
                ForEach(BorderChoice.allCases) { Text($0.label).tag($0) }
            }
        }
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
            Stepper("Dash on \(model.line(id)?.dash.on ?? props.dash.on)", value: Binding(
                get: { model.line(id)?.dash.on ?? 1 },
                set: { value in model.editor.setLine(id) { $0.dash.on = max(1, value) } }
            ), in: 1...12)
            Stepper("Dash off \(model.line(id)?.dash.off ?? props.dash.off)", value: Binding(
                get: { model.line(id)?.dash.off ?? 0 },
                set: { value in model.editor.setLine(id) { $0.dash.off = max(0, value) } }
            ), in: 0...12)
            Picker("Start", selection: Binding(
                get: { CapChoice(model.line(id)?.startCap ?? .none) },
                set: { choice in model.editor.setLine(id) { $0.startCap = choice.cap } }
            )) {
                ForEach(CapChoice.allCases) { Text($0.label).tag($0) }
            }
            Picker("End", selection: Binding(
                get: { CapChoice(model.line(id)?.endCap ?? .none) },
                set: { choice in model.editor.setLine(id) { $0.endCap = choice.cap } }
            )) {
                ForEach(CapChoice.allCases) { Text($0.label).tag($0) }
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
            Picker("Font", selection: Binding(
                get: { model.banner(id)?.fontName ?? props.fontName },
                set: { name in
                    model.editor.setBanner(id) {
                        $0.fontName = name
                        $0.customFLF = nil
                    }
                }
            )) {
                ForEach(BundledFonts.names, id: \.self) { Text($0).tag($0) }
            }
            if model.banner(id)?.customFLF != nil {
                Text("Custom FIGlet font loaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Load .flf…") { model.loadFont(for: id) }
            enumPicker("Align", AsciiDrawCore.TextAlignment.allCases, get: { model.banner(id)?.alignment ?? props.alignment }, set: { value in
                model.editor.setBanner(id) { $0.alignment = value }
            })
            enumPicker("Position", TextVerticalPosition.allCases, get: { model.banner(id)?.position ?? props.position }, set: { value in
                model.editor.setBanner(id) { $0.position = value }
            })
        }
    }

    private var pencilField: some View {
        TextField("Pencil", text: Binding(
            get: { String(model.editor.pencilCharacter) },
            set: { model.editor.pencilCharacter = $0.first ?? "x" }
        ))
        .textFieldStyle(.roundedBorder)
        .font(.body.monospaced())
        .frame(width: 64)
        .accessibilityLabel("Pencil character")
    }

    private func enumPicker<T: RawRepresentable & CaseIterable & Hashable>(
        _ title: String,
        _ values: T.AllCases,
        get: @escaping () -> T,
        set: @escaping (T) -> Void
    ) -> some View where T.RawValue == String, T: Identifiable, T.ID == String {
        Picker(title, selection: Binding(get: get, set: set)) {
            ForEach(Array(values)) { value in
                Text(value.rawValue).tag(value)
            }
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
        case .single: return "Single"
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
