import AppKit
import SwiftUI

struct UsagePanelPlacement {
    let frame: NSRect
    let isLeftOfMenu: Bool
    let markerY: CGFloat

    // AppKit screen coordinates grow upwards. Align the panel top to the
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
        let frame = NSRect(x: x, y: y, width: width, height: height)
        let sourceY = min(anchor.maxY - 18, anchor.midY)
        return Self(frame: frame, isLeftOfMenu: useLeft,
                    markerY: min(max(frame.maxY - sourceY, 18), height - 18))
    }
}

@MainActor
final class UsageHoverController {
    private struct AccountAnchor {
        weak var item: NSMenuItem?
        let account: StatusBarMenuAccountSnapshot
    }
    private var anchors: [AccountAnchor] = []
    private var timer: Timer?
    private var panel: NSPanel?
    private weak var currentItem: NSMenuItem?
    private weak var candidate: NSMenuItem?
    private var candidateSince = Date.distantPast
    private var leftAt: Date?
    private let appearance: NSAppearance?
    private let locale: Locale

    init(appearance: NSAppearance?, locale: Locale) {
        self.appearance = appearance
        self.locale = locale
    }

    var accountCount: Int { anchors.count }

    func register(_ item: NSMenuItem, account: StatusBarMenuAccountSnapshot) {
        guard account.proxyUsage != nil else { return }
        anchors.append(AccountAnchor(item: item, account: account))
    }

    func transferAnchor(from source: NSMenuItem, to destination: NSMenuItem) {
        guard let index = anchors.firstIndex(where: { $0.item === source }) else { return }
        anchors[index].item = destination
    }

    func start() {
        stop()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        dismiss()
    }

    private func screenRect(for item: NSMenuItem) -> NSRect? {
        guard !item.isHidden, let view = item.view, let window = view.window,
              window.isVisible, !view.visibleRect.isEmpty else { return nil }
        return window.convertToScreen(view.convert(view.visibleRect, to: nil))
    }

    private func sample() {
        let point = NSEvent.mouseLocation
        if let anchor = anchors.first(where: { $0.item.flatMap(screenRect)?.contains(point) == true }), let item = anchor.item {
            leftAt = nil
            if currentItem === item { return }
            if candidate !== item {
                candidate = item
                candidateSince = Date()
            } else if Date().timeIntervalSince(candidateSince) >= 0.2 {
                show(anchor)
            }
            return
        }
        candidate = nil
        // Keep the card open while crossing the small gap or exploring it.
        if let panel, let item = currentItem, let rect = screenRect(for: item) {
            if panel.frame.contains(point) || NSRect(x: min(rect.minX, panel.frame.minX),
                y: rect.minY, width: max(rect.maxX, panel.frame.maxX) - min(rect.minX, panel.frame.minX),
                height: rect.height).contains(point) {
                leftAt = nil
                return
            }
        }
        if leftAt == nil { leftAt = Date() }
        if Date().timeIntervalSince(leftAt!) > 0.25 { dismiss() }
    }

    private func show(_ anchor: AccountAnchor) {
        guard let item = anchor.item, let rect = screenRect(for: item), let window = item.view?.window,
              let screen = window.screen, let usage = anchor.account.proxyUsage else { return }
        let detail = ProxyUsageDetailView(usage: usage, provider: anchor.account.id.provider, accountName: anchor.account.email)
            .frame(width: 520).environment(\.locale, locale)
        let measuring = NSHostingView(rootView: detail)
        measuring.appearance = appearance
        let size = NSSize(width: 532, height: measuring.intrinsicContentSize.height)
        let placement = UsagePanelPlacement.calculate(anchor: rect, menu: window.frame, size: size, screen: screen.visibleFrame)
        let content = UsagePanelContent(detail: detail, placement: placement, tint: anchor.account.id.provider.color)
        let hosting = NSHostingView(rootView: content)
        hosting.appearance = appearance
        let panel = self.panel ?? NSPanel(contentRect: placement.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true
        panel.appearance = appearance
        panel.contentView = hosting
        panel.setFrame(placement.frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
        currentItem = item
        candidate = nil
    }

    private func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        currentItem = nil
        candidate = nil
        leftAt = nil
    }
}

private struct UsagePanelContent<Detail: View>: View {
    let detail: Detail
    let placement: UsagePanelPlacement
    let tint: Color

    var body: some View {
        ScrollView(.vertical) { detail }
            .scrollIndicators(.hidden)
            .frame(width: placement.frame.width - 12, height: placement.frame.height)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.2)))
            .overlay(alignment: placement.isLeftOfMenu ? .topTrailing : .topLeading) {
                Image(systemName: placement.isLeftOfMenu ? "arrowtriangle.right.fill" : "arrowtriangle.left.fill")
                    .font(.system(size: 10)).foregroundStyle(tint)
                    .offset(x: placement.isLeftOfMenu ? 5 : -5, y: placement.markerY - 5)
            }
            .padding(.horizontal, 6)
    }
}
