import AppKit
import SwiftUI

enum HoverShape {
    case circle
    case capsule
    case rounded(CGFloat)
}

enum HoverTint {
    /// Quiet gray plate behind icon buttons, toggles, and text buttons.
    case plate
    /// Accent edge for menus and text fields. No gray halo.
    case accent
}

extension View {
    /// Light plate that fades in under the pointer. No scale, so it does not read as a shadow.
    func hoverPlate(_ shape: HoverShape = .rounded(8), outset: CGFloat = 1, cursor: NSCursor? = .pointingHand) -> some View {
        modifier(HoverPlateModifier(shape: shape, outset: outset, cursor: cursor, tint: .plate))
    }

    /// Accent ring around a field or menu. It sits behind the control, so it does not cover text or an open menu.
    func accentHover(_ shape: HoverShape = .rounded(6), cursor: NSCursor? = .pointingHand) -> some View {
        modifier(HoverPlateModifier(shape: shape, outset: 1, cursor: cursor, tint: .accent))
    }
}

struct HoverPlateButtonStyle: ButtonStyle {
    var shape: HoverShape = .circle
    var selected: Bool = false
    var onHoverChange: ((Bool) -> Void)?

    init(shape: HoverShape = .circle, selected: Bool = false, onHoverChange: ((Bool) -> Void)? = nil) {
        self.shape = shape
        self.selected = selected
        self.onHoverChange = onHoverChange
    }

    func makeBody(configuration: Configuration) -> some View {
        HoverPlateButton(configuration: configuration, shape: shape, selected: selected, onHoverChange: onHoverChange)
    }
}

private struct HoverPlateButton: View {
    let configuration: ButtonStyleConfiguration
    var shape: HoverShape
    var selected: Bool
    var onHoverChange: ((Bool) -> Void)?
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false
    @State private var cursorPushed = false

    private var shown: Bool { hovering || configuration.isPressed }

    var body: some View {
        configuration.label
            .background {
                HoverPlateMark(shape: shape, pressed: configuration.isPressed, shown: shown && !selected, outset: 0, tint: .plate)
            }
            .brightness(selected && shown ? (configuration.isPressed ? 0.14 : 0.07) : 0)
            .contentShape(Rectangle())
            .onHover { inside in
                setHover(inside)
            }
            .background {
                HoverMonitor { inside in
                    setHover(inside)
                }
            }
            .onDisappear { setCursor(false) }
    }

    private func setHover(_ inside: Bool) {
        let changed = inside != hovering
        hovering = inside
        if changed { onHoverChange?(inside) }
        setCursor(inside && isEnabled)
    }

    private func setCursor(_ show: Bool) {
        if show && !cursorPushed {
            NSCursor.pointingHand.push()
            cursorPushed = true
        } else if !show && cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
    }
}

private struct HoverPlateModifier: ViewModifier {
    var shape: HoverShape
    var outset: CGFloat
    var cursor: NSCursor?
    var tint: HoverTint
    @State private var hovering = false
    @State private var cursorPushed = false

    func body(content: Content) -> some View {
        content
            .background {
                HoverPlateMark(shape: shape, pressed: false, shown: hovering, outset: outset, tint: tint)
            }
            .onHover { inside in
                hovering = inside
                setCursor(inside)
            }
            .background {
                HoverMonitor { inside in
                    hovering = inside
                    setCursor(inside)
                }
            }
            .onDisappear {
                if cursorPushed {
                    NSCursor.pop()
                    cursorPushed = false
                }
            }
    }

    private func setCursor(_ inside: Bool) {
        guard cursor != nil else { return }
        if inside && !cursorPushed {
            cursor?.push()
            cursorPushed = true
        } else if !inside && cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
    }
}

/// Tracking area, because SwiftUI `onHover` does not fire for every toolbar glass item.
private struct HoverMonitor: NSViewRepresentable {
    var hovering: (Bool) -> Void

    func makeNSView(context: Context) -> HoverMonitorView {
        let view = HoverMonitorView()
        view.hovering = hovering
        return view
    }

    func updateNSView(_ view: HoverMonitorView, context: Context) {
        view.hovering = hovering
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: HoverMonitorView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }
}

private final class HoverMonitorView: NSView {
    var hovering: (Bool) -> Void = { _ in }
    private var inside = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refresh(inside: mouseInside)
    }

    override func mouseEntered(with event: NSEvent) { refresh(inside: true) }
    override func mouseExited(with event: NSEvent) { refresh(inside: false) }

    private var mouseInside: Bool {
        guard let window else { return false }
        return bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    private func refresh(inside now: Bool) {
        guard now != inside else { return }
        inside = now
        hovering(now)
    }
}

private struct HoverPlateMark: View {
    var shape: HoverShape
    var pressed: Bool
    var shown: Bool
    var outset: CGFloat
    var tint: HoverTint

    var body: some View {
        mark
            .padding(tint == .plate ? -outset : 0)
            .opacity(shown ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: shown)
            .animation(.easeOut(duration: 0.08), value: pressed)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var mark: some View {
        switch tint {
        case .plate:
            filled(Color.primary.opacity(pressed ? 0.18 : 0.12))
        case .accent:
            stroked(Color.accentColor, lineWidth: 1.5)
        }
    }

    private func filled(_ color: Color) -> some View {
        Group {
            switch shape {
            case .circle:
                Circle().fill(color)
            case .capsule:
                Capsule().fill(color)
            case .rounded(let radius):
                RoundedRectangle(cornerRadius: radius + outset, style: .continuous).fill(color)
            }
        }
    }

    private func stroked(_ color: Color, lineWidth: CGFloat) -> some View {
        Group {
            switch shape {
            case .circle:
                Circle().strokeBorder(color, lineWidth: lineWidth)
            case .capsule:
                Capsule().strokeBorder(color, lineWidth: lineWidth)
            case .rounded(let radius):
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(color, lineWidth: lineWidth)
            }
        }
    }
}
