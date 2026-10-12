import XCTest
import CLIProxyBarCore
@testable import MenuBar

final class DisplayPreferencesTests: XCTestCase {
    @MainActor
    func testDisplayChoiceSurvivesRelaunchAndNotifiesRenderer() {
        let suite = "CLIProxyBarTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DisplayPreferences(defaults: defaults)
        XCTAssertEqual(preferences.mode, .used)
        var changed = false
        preferences.onChange = { changed = true }
        preferences.mode = .remaining
        XCTAssertTrue(changed)
        XCTAssertEqual(DisplayPreferences(defaults: defaults).mode, .remaining)
        preferences.mode = .used
        XCTAssertEqual(DisplayPreferences(defaults: defaults).mode, .used)
    }

    @MainActor
    func testProxyURLPersistsAndRejectsInvalidChanges() throws {
        let suite = "CLIProxyBarTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DisplayPreferences(defaults: defaults)
        var changes = 0
        preferences.onEndpointChange = { changes += 1 }
        try preferences.saveEndpoint("  http://localhost:9000  ")
        XCTAssertEqual(preferences.endpoint, "http://localhost:9000")
        XCTAssertEqual(DisplayPreferences(defaults: defaults).endpoint, preferences.endpoint)
        try preferences.saveEndpoint("http://localhost:9000")
        XCTAssertEqual(changes, 1)
        for invalid in ["", "ftp://example.com", "http://localhost:99999", "http://localhost:0", "http://user:secret@localhost:8317", "https://proxy.example.com?key=secret"] {
            XCTAssertThrowsError(try preferences.saveEndpoint(invalid))
            XCTAssertEqual(preferences.endpoint, "http://localhost:9000")
        }
        XCTAssertEqual(changes, 1)
        try preferences.saveEndpoint("https://proxy.example.com/cli")
        XCTAssertEqual(DisplayPreferences(defaults: defaults).endpoint, "https://proxy.example.com/cli")
        XCTAssertEqual(changes, 2)
    }

    @MainActor
    func testMenuBarProviderChoicesPersistAndNotify() {
        let suite = "CLIProxyBarTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DisplayPreferences(defaults: defaults)
        var changes = 0
        preferences.onChange = { changes += 1 }
        XCTAssertTrue(preferences.showsInMenuBar(.opencodeGo))
        preferences.setMenuBarVisible(false, for: .claude)
        preferences.setMenuBarVisible(false, for: .claude)
        XCTAssertEqual(changes, 1)
        let restored = DisplayPreferences(defaults: defaults)
        XCTAssertFalse(restored.showsInMenuBar(.claude))
        XCTAssertTrue(restored.showsInMenuBar(.codex))
        XCTAssertTrue(restored.showsInMenuBar(.opencodeGo))
        restored.setMenuBarVisible(false, for: .codex)
        restored.setMenuBarVisible(false, for: .opencodeGo)
        XCTAssertFalse([QuotaProvider.claude, .codex, .opencodeGo].contains { restored.showsInMenuBar($0) })
        restored.setMenuBarVisible(true, for: .claude)
        XCTAssertTrue(DisplayPreferences(defaults: defaults).showsInMenuBar(.claude))
    }

    func testUsageConversionPreservesUnknownReadings() {
        XCTAssertEqual(QuotaDisplayMode.used.displayValue(from: 28), 72)
        XCTAssertEqual(QuotaDisplayMode.used.displayValue(from: 100), 0)
        XCTAssertEqual(QuotaDisplayMode.used.displayValue(from: -1), -1)
        XCTAssertEqual(QuotaDisplayMode.remaining.displayValue(from: 28), 28)
    }

    @MainActor
    func testPairedQuotaDisplayPreservesDefaultAndPersistsChanges() {
        let suite = "CLIProxyBarTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["gemini"], forKey: "hiddenDropdownProviders")
        let preferences = DisplayPreferences(defaults: defaults)
        XCTAssertTrue(preferences.showsBothMenuBarQuotas)
        var changes = 0
        preferences.onChange = { changes += 1 }
        preferences.showsBothMenuBarQuotas = true
        XCTAssertEqual(changes, 0)
        preferences.showsBothMenuBarQuotas = false
        preferences.showsBothMenuBarQuotas = false
        XCTAssertEqual(changes, 1)
        let restored = DisplayPreferences(defaults: defaults)
        XCTAssertFalse(restored.showsBothMenuBarQuotas)
        XCTAssertFalse(restored.showsInDropdown(.gemini))
        XCTAssertEqual(restored.mode, .used)
        preferences.showsBothMenuBarQuotas = true
        XCTAssertTrue(DisplayPreferences(defaults: defaults).showsBothMenuBarQuotas)
        XCTAssertEqual(changes, 2)
    }

    @MainActor
    func testDefaultMenuViewStartsCompactPersistsAndRejectsUnknownSavedValues() {
        let suite = "CLIProxyBarTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DisplayPreferences(defaults: defaults)
        XCTAssertEqual(preferences.defaultMenuView, .compact)
        var changes = 0
        preferences.onChange = { changes += 1 }
        preferences.defaultMenuView = .compact
        XCTAssertEqual(changes, 0)
        preferences.defaultMenuView = .expanded
        preferences.defaultMenuView = .expanded
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(DisplayPreferences(defaults: defaults).defaultMenuView, .expanded)
        preferences.defaultMenuView = .compact
        XCTAssertEqual(changes, 2)
        XCTAssertEqual(DisplayPreferences(defaults: defaults).defaultMenuView, .compact)
        defaults.set("unknown-view", forKey: "defaultMenuView")
        XCTAssertEqual(DisplayPreferences(defaults: defaults).defaultMenuView, .compact)
    }

    @MainActor
    func testProviderLocationsAreIndependentAndPersistAllCombinations() {
        let suite = "CLIProxyBarTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DisplayPreferences(defaults: defaults)
        var changes = 0
        preferences.onChange = { changes += 1 }

        for menuBar in [false, true] {
            for dropdown in [false, true] {
                preferences.setMenuBarVisible(menuBar, for: .gemini)
                preferences.setDropdownVisible(dropdown, for: .gemini)
                let restored = DisplayPreferences(defaults: defaults)
                XCTAssertEqual(restored.showsInMenuBar(.gemini), menuBar)
                XCTAssertEqual(restored.showsInDropdown(.gemini), dropdown)
                XCTAssertTrue(restored.showsInMenuBar(.claude))
                XCTAssertTrue(restored.showsInDropdown(.claude))
                let previousChanges = changes
                preferences.setMenuBarVisible(menuBar, for: .gemini)
                preferences.setDropdownVisible(dropdown, for: .gemini)
                XCTAssertEqual(changes, previousChanges)
            }
        }
        XCTAssertEqual(changes, 6)
    }

    @MainActor
    func testExistingMenuBarChoicesDoNotHideDropdownProviders() {
        let suite = "CLIProxyBarTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["claude", "gemini"], forKey: "hiddenMenuBarProviders")
        defaults.set(true, forKey: "tracksProxyUsage")
        defaults.set(true, forKey: "notifiesShortResets")
        let preferences = DisplayPreferences(defaults: defaults)
        XCTAssertFalse(preferences.showsInMenuBar(.gemini))
        XCTAssertTrue(preferences.showsInDropdown(.gemini))
        preferences.setDropdownVisible(false, for: .gemini)
        preferences.setDropdownVisible(true, for: .gemini)
        let restored = DisplayPreferences(defaults: defaults)
        XCTAssertFalse(restored.showsInMenuBar(.gemini))
        XCTAssertTrue(restored.showsInDropdown(.gemini))
        XCTAssertTrue(restored.tracksProxyUsage)
        XCTAssertTrue(restored.notifiesShortResets)
    }
}
