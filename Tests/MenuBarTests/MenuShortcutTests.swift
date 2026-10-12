import AppKit
import XCTest
import CLIProxyBarCore
@testable import MenuBar

final class MenuShortcutTests: XCTestCase {
    @MainActor
    func testMenuOpeningUsesCurrentDefaultAndOptionSelectsOtherView() throws {
        var expandedDefault = false
        let snapshot = StatusBarMenuSnapshot(connectionMessage: "Fixture", isLocalProxyMode: true, proxyPort: 8317,
            isProxyRunning: true, tunnel: CloudflareTunnelSnapshot(), providers: [], selectedProvider: nil,
            isLoadingQuotas: false, displaySettings: StatusBarMenuDisplaySettings(quotaDisplayMode: .used,
                quotaDisplayStyle: .lowestBar, hideSensitiveInfo: false, modelAggregationMode: .lowest),
            appearanceMode: .system, language: .english, hiddenProviderCount: 1)
        let dispatcher = StatusBarCommandDispatcher(handlers: StatusBarCommandHandlers(
            refreshAll: {}, refreshProvider: { _ in }, refreshAccount: { _ in },
            toggleProxy: {}, toggleTunnel: { _ in }, copyText: { _ in }, switchAntigravityAccount: { _ in },
            isAntigravityIDERunning: { false }, confirmAntigravitySwitch: { _, _ in false },
            selectProvider: { _ in }, settings: {}, openApp: {}, quit: {}, menuNeedsRebuild: {}))
        let manager = StatusBarManager()
        manager.configureMenu(snapshotProvider: { snapshot }, commandDispatcher: dispatcher,
            defaultExpanded: { expandedDefault })
        let menu = NSMenu()
        for (defaultValue, option, expectedWidth) in [
            (false, false, 280.0), (false, true, 360.0),
            (true, false, 360.0), (true, true, 280.0), (false, false, 280.0)
        ] {
            expandedDefault = defaultValue
            manager.prepareMenuForOpening(menu, optionPressed: option)
            let views = menu.items.compactMap(\.view)
            XCTAssertEqual(views.count, 2)
            XCTAssertTrue(views.allSatisfy { $0.frame.width == expectedWidth })
            XCTAssertNotNil(menu.items.first { $0.keyEquivalent == "," })
        }
    }

    @MainActor
    func testRefreshShortcutConsumesEventWithoutNativeAction() async throws {
        let refreshed = expectation(description: "Refresh dispatched")
        let dispatcher = StatusBarCommandDispatcher(handlers: StatusBarCommandHandlers(
            refreshAll: { refreshed.fulfill() }, refreshProvider: { _ in }, refreshAccount: { _ in },
            toggleProxy: {}, toggleTunnel: { _ in }, copyText: { _ in }, switchAntigravityAccount: { _ in },
            isAntigravityIDERunning: { false }, confirmAntigravitySwitch: { _, _ in false },
            selectProvider: { _ in }, settings: {}, openApp: {}, quit: {}, menuNeedsRebuild: {}
        ))
        let manager = StatusBarManager()
        manager.configureMenu(snapshotProvider: { fatalError("Shortcut must not rebuild synchronously") }, commandDispatcher: dispatcher)
        let menu = NSMenu()
        func event(_ flags: NSEvent.ModifierFlags, repeatKey: Bool = false) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil, characters: "r", charactersIgnoringModifiers: "r", isARepeat: repeatKey, keyCode: 15))
        }
        var target: AnyObject? = dispatcher
        var action: Selector? = #selector(getter: NSObject.description)
        XCTAssertFalse(manager.menuHasKeyEquivalent(menu, for: try event([]), target: &target, action: &action))
        XCTAssertFalse(manager.menuHasKeyEquivalent(menu, for: try event([.command, .shift]), target: &target, action: &action))
        XCTAssertTrue(manager.menuHasKeyEquivalent(menu, for: try event(.command), target: &target, action: &action))
        XCTAssertNil(target)
        XCTAssertNil(action)
        XCTAssertTrue(manager.menuHasKeyEquivalent(menu, for: try event(.command, repeatKey: true), target: &target, action: &action))
        await fulfillment(of: [refreshed], timeout: 1)
    }

    @MainActor
    func testProviderFilterScopeFollowsReusedMenuItem() {
        let controller = StatusBarProviderFilterController(selectedProvider: nil, onSelectionChanged: { _ in })
        let temporary = NSMenuItem(title: "New", action: nil, keyEquivalent: "")
        let existing = NSMenuItem(title: "Existing", action: nil, keyEquivalent: "")
        controller.register(temporary, scope: .provider(.claude))
        controller.transferScope(from: temporary, to: existing)
        let menu = NSMenu()
        menu.addItem(existing)
        controller.activate(in: menu)
        controller.select(.codex)
        XCTAssertTrue(existing.isHidden)
        controller.select(.claude)
        XCTAssertFalse(existing.isHidden)
    }
}
