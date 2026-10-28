import SwiftUI

enum GlyphPalette: String, CaseIterable, Identifiable {
    case geometric = "Geometric Shapes"
    case box = "Box Drawing"
    case blocks = "Blocks"
    case arrows = "Arrows"

    var id: String { rawValue }

    var glyphs: [String] {
        let source: String
        switch self {
        case .geometric:
            source = "■□▢▣▤▥▦▧▨▩▪▫▬▭▮▯▲△▼▽◀▶◁▷◆◇○●◎◉◐◑◒◓◔◕★☆♦♠♣♥"
        case .box:
            source = "─│┌┐└┘├┤┬┴┼━┃┏┓┗┛┣┫┳┻╋═║╔╗╚╝╠╣╦╩╬╭╮╰╯╱╲╳┄┅┆┇┈┉┊┋"
        case .blocks:
            source = "▀▄█▌▐░▒▓▔▁▂▃▄▅▆▇▉▊▋▍▎▏▕▖▗▘▙▚▛▜▝▞▟"
        case .arrows:
            source = "←→↑↓↔↕↖↗↘↙⇐⇒⇑⇓⇔⬅➡⬆⬇▲▼◀▶◁▷◂▸▴▾"
        }
        var seen = Set<String>()
        var result: [String] = []
        for character in source {
            let glyph = String(character)
            if seen.insert(glyph).inserted {
                result.append(glyph)
            }
        }
        return result
    }
}

struct CharacterPaletteView: View {
    @Binding var character: String
    @State private var palette: GlyphPalette = .geometric

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Pencil")
                TextField("Glyph", text: $character)
                    .font(.system(.body, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .frame(width: 44)
                    .textFieldStyle(.roundedBorder)
                    .accentHover(.rounded(6), cursor: nil)
                    .accessibilityLabel("Pencil character")
            }
            HStack {
                Text("Palette")
                Spacer(minLength: 8)
                AlignedPopup(
                    items: Array(GlyphPalette.allCases),
                    selection: palette,
                    itemTitle: \.rawValue,
                    onSelect: { palette = $0 }
                )
                .fixedSize()
                .accessibilityLabel("Palette")
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(22), spacing: 2), count: 12), spacing: 2) {
                    ForEach(palette.glyphs, id: \.self) { glyph in
                        Button {
                            character = String(glyph.prefix(1))
                        } label: {
                            Text(glyph)
                                .font(.system(size: 13, design: .monospaced))
                                .frame(width: 20, height: 20)
                                .background(
                                    character == glyph ? Color.accentColor.opacity(0.28) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 3)
                                )
                        }
                        .buttonStyle(HoverPlateButtonStyle(shape: .rounded(4), selected: character == glyph))
                        .help(glyph)
                        .accessibilityLabel("Character \(glyph)")
                    }
                }
            }
        }
        .padding(12)
        .accessibilityIdentifier("character-palette")
        .accessibilityLabel("Character palette")
    }
}
