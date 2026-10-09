import AppKit
import SwiftUI
import XCTest
@testable import MenuBar

final class UsageMenuInteractionTests: XCTestCase {
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
