import AppKit
import XCTest
@testable import MenuBar

final class MenuShortcutTests: XCTestCase {
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
