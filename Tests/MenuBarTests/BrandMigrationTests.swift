import XCTest
import CLIProxyBarCore
@testable import MenuBar

final class BrandMigrationTests: XCTestCase {
    @MainActor
    func testMigrationCopiesOnlyMissingDisplaySettingsAndRunsOnce() throws {
        let suite = "CLIProxyBarTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("http://localhost:9000", forKey: "endpoint")
        DisplayPreferences.migrateLegacyDefaults(defaults, legacy: [
            "endpoint": "http://localhost:8317",
            "quotaDisplayMode": "remaining",
            "hiddenMenuBarProviders": ["claude"],
            "managementKey": "must-not-copy",
            "unrelated": "must-not-copy"
        ])
        let preferences = DisplayPreferences(defaults: defaults)
        XCTAssertEqual(preferences.endpoint, "http://localhost:9000")
        XCTAssertEqual(preferences.mode, .remaining)
        XCTAssertFalse(preferences.showsInMenuBar(.claude))
        XCTAssertNil(defaults.object(forKey: "managementKey"))
        XCTAssertNil(defaults.object(forKey: "unrelated"))
        defaults.removeObject(forKey: "quotaDisplayMode")
        DisplayPreferences.migrateLegacyDefaults(defaults, legacy: ["quotaDisplayMode": "remaining"])
        XCTAssertNil(defaults.object(forKey: "quotaDisplayMode"))
    }

    func testLegacyCacheFallbackRetainsEndpointBoundaryAndPrefersNewCache() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let endpoint = "http://127.0.0.1:8317"
        let legacy = QuotaCache(endpoint: endpoint, directory: root.appendingPathComponent("legacy"))
        var account = ProxyAccount(name: "demo", provider: "claude", email: nil, disabled: nil, unavailable: nil, quota: nil, model_quotas: nil)
        account.fetchedQuota = ProviderQuota(models: [QuotaMetric(name: "five-hour-session", percentage: 75, resetTime: "")])
        try legacy.save([account])
        let cache = QuotaCache(endpoint: endpoint, directory: root.appendingPathComponent("new"), legacyURL: legacy.url)
        XCTAssertEqual(try cache.load().first?.providerQuota().models.first?.percentage, 75)
        XCTAssertTrue(try QuotaCache(endpoint: "http://localhost:9000", directory: root.appendingPathComponent("other"), legacyURL: legacy.url).load().isEmpty)
        account.fetchedQuota = ProviderQuota(models: [QuotaMetric(name: "five-hour-session", percentage: 50, resetTime: "")])
        try cache.save([account])
        XCTAssertEqual(try cache.load().first?.providerQuota().models.first?.percentage, 50)
        XCTAssertEqual(try legacy.load().first?.providerQuota().models.first?.percentage, 75)
    }
}
