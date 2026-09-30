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
        for invalid in ["", "https://example.com", "http://localhost:99999", "http://localhost:0", "http://user:secret@localhost:8317", "http://localhost:8317/path"] {
            XCTAssertThrowsError(try preferences.saveEndpoint(invalid))
            XCTAssertEqual(preferences.endpoint, "http://localhost:9000")
        }
        XCTAssertEqual(changes, 1)
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
}
