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
    private let usage: ProxyUsageSnapshot
    private let provider: QuotaProvider
    private let accountName: String
    private let locale: Locale
    private let quotaHistory: QuotaHistorySnapshot?
    private let defaults: UserDefaults
    private let detailItem = NSMenuItem(title: "Usage", action: nil, keyEquivalent: "")
    private let selection: AccountHistorySelection
    var selectedHistoryTab: AccountHistoryTab { selection.tab }

    init(usage: ProxyUsageSnapshot, provider: QuotaProvider, accountName: String,
         anchor: NSMenuItem, appearance: NSAppearance?, locale: Locale, quotaHistory: QuotaHistorySnapshot? = nil,
         defaults: UserDefaults = .standard) {
        anchorItem = anchor
        self.usage = usage
        self.provider = provider
        self.accountName = accountName
        self.locale = locale
        self.quotaHistory = quotaHistory
        self.defaults = defaults
        selection = AccountHistorySelection(quotaHistory?.series.isEmpty == false ? AccountHistoryTab.preferred(in: defaults) : .tokens)
        super.init(title: "Usage")
        self.appearance = appearance
        autoenablesItems = false
        showsStateColumn = false
        delegate = self

        detailItem.view = makeDetailView()
        addItem(detailItem)
    }

    private func makeDetailView() -> NSView {
        let detail = AccountDetailView(usage: usage, quotaHistory: quotaHistory, provider: provider, defaults: defaults,
            selection: selection, onSelectTab: { [weak self] in self?.selectHistoryTab($0) })
            .frame(width: 520).fixedSize(horizontal: false, vertical: true).environment(\.locale, locale)
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
            .accessibilityLabel(accountName + " usage")
        let hosting = UsageMenuHostingView(rootView: detail)
        hosting.appearance = appearance
        // Measure both persistent panels before this menu is first displayed.
        hosting.fitToContent()
        hosting.layoutSubtreeIfNeeded()
        hosting.fitToContent()
        return hosting
    }

    func selectHistoryTab(_ tab: AccountHistoryTab) {
        guard quotaHistory?.series.isEmpty == false else { return }
        showHistoryTab(tab)
        defaults.set(tab.rawValue, forKey: AccountHistoryTab.preferenceKey)
    }

    private func showHistoryTab(_ tab: AccountHistoryTab) {
        guard tab != selectedHistoryTab else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { selection.tab = tab }
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard quotaHistory?.series.isEmpty == false else { return }
        showHistoryTab(AccountHistoryTab.preferred(in: defaults))
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

// AppKit resizes an open menu when an item's view frame changes. Follow
// SwiftUI's intrinsic size without replacing the item or ending tracking.
@MainActor
final class UsageMenuHostingView<Content: View>: NSHostingView<Content> {
    private var fitPending = false

    required init(rootView: Content) {
        super.init(rootView: rootView)
        sizingOptions = [.intrinsicContentSize]
    }

    required init?(coder: NSCoder) {
        fatalError("UsageMenuHostingView is created from a usage snapshot")
    }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        scheduleContentFit()
    }

    override func layout() {
        super.layout()
        scheduleContentFit()
    }

    private func scheduleContentFit() {
        guard !fitPending else { return }
        fitPending = true
        // A menu runs in event-tracking mode. Resize after SwiftUI finishes
        // its layout, including while the user is interacting with the tabs.
        let fit: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            self.fitPending = false
            self.fitToContent()
        }
        RunLoop.main.perform(inModes: [.common, .eventTracking]) {
            MainActor.assumeIsolated { fit() }
        }
    }

    func fitToContent() {
        let size = intrinsicContentSize
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              abs(frame.width - size.width) > 0.5 || abs(frame.height - size.height) > 0.5 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            setFrameSize(NSSize(width: ceil(size.width), height: ceil(size.height)))
        }
    }
}
