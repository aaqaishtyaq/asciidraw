import AppKit
import SwiftUI

/// Popup whose menu is positioned by AppKit, so the open menu sits on the button.
/// SwiftUI `Picker` offsets that menu after the label is pulled out of the control.
struct AlignedPopup<Item: Hashable>: NSViewRepresentable {
    var items: [Item]
    var selection: Item
    var itemTitle: (Item) -> String
    var onSelect: (Item) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> FittingPopupButton {
        let button = FittingPopupButton(frame: .zero, pullsDown: false)
        button.controlSize = .regular
        button.font = .systemFont(ofSize: NSFont.systemFontSize)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.target = context.coordinator
        button.action = #selector(Coordinator.pick(_:))
        return button
    }

    func updateNSView(_ button: FittingPopupButton, context: Context) {
        let titles = items.map(itemTitle)
        context.coordinator.onPick = { index in
            guard items.indices.contains(index) else { return }
            onSelect(items[index])
        }
        if button.itemTitles != titles {
            button.removeAllItems()
            button.addItems(withTitles: titles)
            button.sizeToFit()
        }
        if let index = items.firstIndex(of: selection), button.indexOfSelectedItem != index {
            button.selectItem(at: index)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: FittingPopupButton, context: Context) -> CGSize? {
        let fit = nsView.intrinsicContentSize
        let width = fit.width > 1 ? fit.width : 88
        let height = fit.height > 1 ? fit.height : 24
        return CGSize(width: width, height: height)
    }

    final class Coordinator: NSObject {
        var onPick: (Int) -> Void = { _ in }

        @objc func pick(_ sender: NSPopUpButton) {
            onPick(sender.indexOfSelectedItem)
        }
    }
}

/// Opens the menu on the button's own edges. The system popup sits about 12 points to the left.
final class FittingPopupButton: NSPopUpButton {
    override func mouseDown(with event: NSEvent) {
        guard let menu = menu, menu.numberOfItems > 0 else { return }
        menu.minimumWidth = bounds.width
        let index = indexOfSelectedItem >= 0 ? indexOfSelectedItem : 0
        let item = menu.item(at: index)
        let anchor = NSPoint(x: 0, y: isFlipped ? 0 : bounds.maxY)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            menu.popUp(positioning: item, at: anchor, in: self)
        }
    }
}
