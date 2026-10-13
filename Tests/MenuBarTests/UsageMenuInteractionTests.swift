import AppKit
import SwiftUI
import XCTest
import CLIProxyBarCore
@testable import MenuBar

final class UsageMenuInteractionTests: XCTestCase {
    @MainActor
    func testHistoryTabChoiceSurvivesReopeningAndTokenOnlyFallback() throws {
        let suite = "AccountHistoryTabTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = QuotaHistorySnapshot(series: [QuotaHistorySeries(id: "session", title: "5 hours", points: [])])
        func account(_ quota: QuotaHistorySnapshot?) -> AccountDetailView {
            AccountDetailView(usage: ProxyUsageSnapshot(), quotaHistory: quota, provider: .claude, defaults: defaults)
        }
        XCTAssertEqual(account(history).selectedTab, .tokens)
        XCTAssertNil(defaults.object(forKey: AccountHistoryTab.preferenceKey))
        defaults.set(AccountHistoryTab.tokens.rawValue, forKey: AccountHistoryTab.preferenceKey)
        XCTAssertEqual(account(history).selectedTab, .tokens)
        defaults.set(AccountHistoryTab.quota.rawValue, forKey: AccountHistoryTab.preferenceKey)
        XCTAssertEqual(account(nil).selectedTab, .tokens)
        XCTAssertEqual(account(QuotaHistorySnapshot()).selectedTab, .tokens)
        XCTAssertEqual(defaults.string(forKey: AccountHistoryTab.preferenceKey), AccountHistoryTab.quota.rawValue)
        XCTAssertEqual(account(history).selectedTab, .quota)
        defaults.removeObject(forKey: AccountHistoryTab.preferenceKey)
        var paused = history
        paused.recordingEnabled = false
        XCTAssertEqual(account(paused).selectedTab, .tokens)
    }

    @MainActor
    func testSwitchingHistoryTabsKeepsMountedCardStableAndFitsBothPanels() throws {
        let suite = "AccountHistorySizingTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(AccountHistoryTab.quota.rawValue, forKey: AccountHistoryTab.preferenceKey)
        let now = Date()
        var day = ProxyUsageDay(date: now, requests: 20)
        day.tokens.total = 100_000
        day.tokens.cacheWrite = 12_000
        for name in ["Model A", "Model B", "Model C", "Model D"] {
            day.models[name] = ProxyUsageModelTotals(requests: 5, tokens: day.tokens)
        }
        let usage = ProxyUsageSnapshot(days: [day], startedAt: now, trackingEnabled: true, lastCollectedAt: now)
        let history = QuotaHistorySnapshot(series: [
            QuotaHistorySeries(id: "session", title: "5 hours", points: [QuotaHistoryPoint(date: now, usedPercent: 20)]),
            QuotaHistorySeries(id: "weekly", title: "Weekly", points: [QuotaHistoryPoint(date: now, usedPercent: 40)])
        ])
        let anchor = NSMenuItem()
        let submenu = UsageSubmenu(usage: usage, provider: .claude, accountName: "Fixture", anchor: anchor,
            appearance: nil, locale: .current, quotaHistory: history, defaults: defaults)
        anchor.submenu = submenu
        let item = try XCTUnwrap(submenu.items.first)
        let hosting = try XCTUnwrap(item.view)
        _ = NSApplication.shared
        // Attaching a hosting view can trigger layout that offscreen size
        // measurements miss. This window stays hidden throughout the test.
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: hosting.frame.size),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView?.addSubview(hosting)
        defer { hosting.removeFromSuperview(); window.orderOut(nil) }
        func settleLayout(mode: RunLoop.Mode = .default, duration: TimeInterval = 0.1) {
            let deadline = Date().addingTimeInterval(duration)
            while Date() < deadline {
                hosting.layoutSubtreeIfNeeded()
                RunLoop.main.run(mode: mode, before: Date().addingTimeInterval(0.01))
            }
        }
        func export(_ tab: String) throws {
            guard let path = ProcessInfo.processInfo.environment["CLIPROXYBAR_HISTORY_CARD_PREVIEW"] else { return }
            for (suffix, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
                let preview = NSHostingView(rootView: AccountDetailView(usage: usage, quotaHistory: history,
                    provider: .claude, defaults: defaults).frame(width: 520).fixedSize(horizontal: false, vertical: true)
                    .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, scheme))
                preview.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
                preview.setFrameSize(preview.intrinsicContentSize)
                preview.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(preview.bitmapImageRepForCachingDisplay(in: preview.bounds))
                preview.cacheDisplay(in: preview.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: path + "-" + tab + "-" + suffix + ".png"))
            }
        }
        settleLayout()
        let frame = hosting.frame
        let menuSize = submenu.size
        XCTAssertEqual(frame.height, hosting.intrinsicContentSize.height, accuracy: 1)
        let fullTokens = NSHostingView(rootView: ProxyUsageDetailView(usage: usage, provider: .claude).frame(width: 520))
        XCTAssertGreaterThan(frame.height, fullTokens.intrinsicContentSize.height)
        hosting.postsFrameChangedNotifications = true
        var changedFrames: [NSRect] = []
        let recordFrame: @MainActor @Sendable () -> Void = { changedFrames.append(hosting.frame) }
        let observer = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification,
            object: hosting, queue: .main) { _ in MainActor.assumeIsolated { recordFrame() } }
        defer { NotificationCenter.default.removeObserver(observer) }
        try export("quota")
        submenu.selectHistoryTab(.tokens)
        XCTAssertTrue(hosting === item.view, "The header and panels must not be replaced when switching tabs")
        XCTAssertEqual(submenu.selectedHistoryTab, .tokens)
        XCTAssertEqual(defaults.string(forKey: AccountHistoryTab.preferenceKey), AccountHistoryTab.tokens.rawValue)
        settleLayout(duration: 0.75)
        XCTAssertEqual(hosting.frame, frame)
        XCTAssertEqual(submenu.size, menuSize)
        XCTAssertEqual(hosting.intrinsicContentSize.height, frame.height, accuracy: 1)
        try export("tokens")
        submenu.selectHistoryTab(.quota)
        XCTAssertTrue(hosting === item.view)
        settleLayout(mode: .eventTracking, duration: 0.75)
        XCTAssertEqual(hosting.frame, frame)
        XCTAssertEqual(submenu.size, menuSize)
        XCTAssertEqual(hosting.intrinsicContentSize.height, frame.height, accuracy: 1)
        XCTAssertTrue(changedFrames.isEmpty, "No immediate or delayed frame correction may run after a tab switch")
        XCTAssertTrue(item === submenu.items.first)
        defaults.set(AccountHistoryTab.tokens.rawValue, forKey: AccountHistoryTab.preferenceKey)
        submenu.menuWillOpen(submenu)
        XCTAssertEqual(submenu.selectedHistoryTab, .tokens)
        XCTAssertTrue(hosting === item.view)
        XCTAssertEqual(hosting.frame, frame)
    }

    @MainActor
    func testUsageSubmenuForwardsRefreshWithoutSelectingAMenuAction() async throws {
        let refreshed = expectation(description: "Refresh from Usage submenu")
        let commands = StatusBarCommandDispatcher(handlers: StatusBarCommandHandlers(
            refreshAll: { refreshed.fulfill() }, refreshProvider: { _ in }, refreshAccount: { _ in },
            toggleProxy: {}, toggleTunnel: { _ in }, copyText: { _ in }, switchAntigravityAccount: { _ in },
            isAntigravityIDERunning: { false }, confirmAntigravitySwitch: { _, _ in false },
            selectProvider: { _ in }, settings: {}, openApp: {}, quit: {}, menuNeedsRebuild: {}
        ))
        let manager = StatusBarManager()
        manager.configureMenu(snapshotProvider: { fatalError("Shortcut must not rebuild synchronously") }, commandDispatcher: commands)
        let parent = NSMenu()
        parent.delegate = manager
        let anchor = NSMenuItem()
        parent.addItem(anchor)
        let submenu = UsageSubmenu(usage: ProxyUsageSnapshot(), provider: .codex, accountName: "Fixture",
            anchor: anchor, appearance: nil, locale: .current)
        anchor.submenu = submenu
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: 0, context: nil, characters: "r", charactersIgnoringModifiers: "r", isARepeat: false, keyCode: 15))
        var target: AnyObject? = commands
        var action: Selector? = #selector(getter: NSObject.description)
        XCTAssertTrue(submenu.menuHasKeyEquivalent(submenu, for: event, target: &target, action: &action))
        XCTAssertNil(target)
        XCTAssertNil(action)
        await fulfillment(of: [refreshed], timeout: 1)
    }

    // This fixture opens a real native menu. Opt in on a macOS desktop; CI can
    // have no window server. Events stay inside the test's own menu window.
    @MainActor
    func testMouseClicksChangeActivityMeasureWithoutEndingNativeMenuTracking() throws {
        guard ProcessInfo.processInfo.environment["CLIPROXYBAR_MENU_INTERACTION_TEST"] == "1" else {
            throw XCTSkip("Requires a macOS desktop; set CLIPROXYBAR_MENU_INTERACTION_TEST=1")
        }
        let app = NSApplication.shared
        let anchor = NSMenuItem()
        let submenu = UsageSubmenu(usage: ProxyUsageSnapshot(), provider: .codex, accountName: "Fixture",
            anchor: anchor, appearance: nil, locale: .current)
        anchor.submenu = submenu
        var measure = UsageActivityMeasure.tokens
        let picker = UsageActivityMeasurePicker(measure: Binding(get: { measure }, set: { measure = $0 }))
            .frame(width: 200, height: 60)
        let hosting = NSHostingView(rootView: picker)
        hosting.setFrameSize(hosting.intrinsicContentSize)
        submenu.items[0].view = hosting

        var step = 0
        var ticks = 0
        var remainedOpen = false
        let drive: @MainActor @Sendable () -> Void = {
            ticks += 1
            if ticks > 40 { submenu.cancelTracking(); return }
            guard let window = hosting.window, ticks >= 6 else { return }
            hosting.layoutSubtreeIfNeeded()
            switch step {
            case 0:
                Self.click(hosting.convert(NSPoint(x: 140, y: 30), to: nil), in: window, app: app)
                step = 1
            case 1 where measure == .requests:
                remainedOpen = window.isVisible
                step = 2
                submenu.cancelTracking()
            default: break
            }
        }
        let timer = Timer(timeInterval: 0.05, repeats: true) { _ in
            MainActor.assumeIsolated { drive() }
        }
        RunLoop.main.add(timer, forMode: .eventTracking)
        defer { timer.invalidate() }
        let point = NSEvent.mouseLocation
        let screen = try XCTUnwrap(NSScreen.screens.first { $0.frame.contains(point) })
        // Native tracking also samples the physical cursor. Place this test's
        // Requests button under it; never move the user's cursor.
        let topLeft = NSPoint(x: point.x - 140, y: point.y + 35)
        guard screen.visibleFrame.contains(NSRect(x: topLeft.x, y: topLeft.y - 70, width: 200, height: 70)) else {
            throw XCTSkip("Fixture needs room beside the cursor")
        }
        submenu.popUp(positioning: nil, at: topLeft, in: nil)
        XCTAssertEqual(step, 2, "A native mouse click must reach the SwiftUI selector")
        XCTAssertTrue(remainedOpen, "Changing the measure must keep native menu tracking active")
    }

    @MainActor
    func testNativeMenuHonorsAccountRelativeConfinement() throws {
        guard ProcessInfo.processInfo.environment["CLIPROXYBAR_MENU_INTERACTION_TEST"] == "1" else {
            throw XCTSkip("Requires a macOS desktop; set CLIPROXYBAR_MENU_INTERACTION_TEST=1")
        }
        let screen = try XCTUnwrap(NSScreen.main)
        let parent = NSWindow(contentRect: NSRect(x: screen.visibleFrame.midX - 100, y: screen.visibleFrame.midY - 100,
            width: 200, height: 200), styleMask: .borderless, backing: .buffered, defer: false)
        defer { parent.orderOut(nil) }
        let anchor = NSMenuItem()
        let source = NSView(frame: NSRect(x: 0, y: 140, width: 200, height: 60))
        anchor.view = source
        parent.contentView?.addSubview(source)
        parent.orderFrontRegardless()
        let submenu = UsageSubmenu(usage: ProxyUsageSnapshot(), provider: .codex, accountName: "Fixture",
            anchor: anchor, appearance: nil, locale: .current)
        let hosting = try XCTUnwrap(submenu.items[0].view)
        var actual: NSRect?
        var expected: NSRect?
        let record: @MainActor @Sendable () -> Void = {
            actual = hosting.window?.frame
            expected = submenu.confinementRect(for: submenu, on: screen)
            submenu.cancelTracking()
        }
        let timer = Timer(timeInterval: 0.1, repeats: false) { _ in MainActor.assumeIsolated { record() } }
        RunLoop.main.add(timer, forMode: .eventTracking)
        defer { timer.invalidate() }
        _ = withExtendedLifetime(anchor) {
            submenu.popUp(positioning: nil, at: NSPoint(x: screen.visibleFrame.minX + 40, y: screen.visibleFrame.maxY - 40), in: nil)
        }
        let frame = try XCTUnwrap(actual)
        let target = try XCTUnwrap(expected)
        XCTAssertEqual(frame.minX, target.minX, accuracy: 1)
        XCTAssertEqual(frame.maxY, target.maxY, accuracy: 1)
    }

    @MainActor
    private static func click(_ point: NSPoint, in window: NSWindow, app: NSApplication) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            post(type, at: point, in: window, app: app)
        }
    }

    @MainActor
    private static func post(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow, app: NSApplication) {
        if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) {
            app.postEvent(event, atStart: false)
        }
    }
}
