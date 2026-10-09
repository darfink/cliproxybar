import AppKit
import CLIProxyBarCore
import SwiftUI

struct UsageMenuPlacement {
    let frame: NSRect
    let isLeftOfMenu: Bool

    // AppKit screen coordinates grow upwards. Align the submenu top to the
    // account top, then clamp only when the screen leaves insufficient room.
    static func calculate(anchor: NSRect, menu: NSRect, size: NSSize, screen: NSRect) -> Self {
        let safe = screen.insetBy(dx: 8, dy: 8)
        let width = min(size.width, safe.width)
        let height = min(size.height, safe.height)
        let right = menu.maxX + 6
        let left = menu.minX - width - 6
        let useLeft = right + width > safe.maxX && left >= safe.minX
        let preferredX = useLeft ? left : right
        let x = min(max(preferredX, safe.minX), safe.maxX - width)
        let y = min(max(anchor.maxY - height, safe.minY), safe.maxY - height)
        return Self(frame: NSRect(x: x, y: y, width: width, height: height), isLeftOfMenu: useLeft)
    }
}

// The detail must belong to the native menu hierarchy. A separate NSPanel
// receives outside-click dismissal before its SwiftUI buttons can act.
@MainActor
final class UsageSubmenu: NSMenu, NSMenuDelegate {
    weak var anchorItem: NSMenuItem?

    init(usage: ProxyUsageSnapshot, provider: QuotaProvider, accountName: String,
         anchor: NSMenuItem, appearance: NSAppearance?, locale: Locale) {
        anchorItem = anchor
        super.init(title: "Usage")
        self.appearance = appearance
        autoenablesItems = false
        showsStateColumn = false
        delegate = self

        let detail = ProxyUsageDetailView(usage: usage, provider: provider)
            .frame(width: 520).environment(\.locale, locale)
            .accessibilityLabel(accountName + " usage")
        let hosting = NSHostingView(rootView: detail)
        hosting.appearance = appearance
        hosting.setFrameSize(hosting.intrinsicContentSize)
        let item = NSMenuItem(title: "Usage", action: nil, keyEquivalent: "")
        item.view = hosting
        addItem(item)
    }

    required init(coder: NSCoder) {
        fatalError("UsageSubmenu is created from a usage snapshot")
    }

    func confinementRect(for menu: NSMenu, on screen: NSScreen?) -> NSRect {
        guard let view = anchorItem?.view, let window = view.window,
              let screen = screen ?? window.screen, !view.visibleRect.isEmpty else { return .zero }
        let anchor = window.convertToScreen(view.convert(view.visibleRect, to: nil))
        // Use the public positioning delegate, never modify AppKit's menu window.
        return UsageMenuPlacement.calculate(anchor: anchor, menu: window.frame,
            size: menu.size, screen: screen.visibleFrame).frame
    }

    func menuHasKeyEquivalent(_ menu: NSMenu, for event: NSEvent,
                              target: AutoreleasingUnsafeMutablePointer<AnyObject?>,
                              action: UnsafeMutablePointer<Selector?>) -> Bool {
        guard let parent = supermenu else { return false }
        return parent.delegate?.menuHasKeyEquivalent?(parent, for: event, target: target, action: action) ?? false
    }
}
