import XCTest
import CLIProxyBarCore
@testable import MenuBar

final class PluginQuotaTests: XCTestCase {
    @MainActor func testNativeQuotaWindowsAndUnknownDurations() throws {
        let body = #"{"subscription":{"plan":"Go"},"groups":[{"buckets":[{"window":"rolling","remainingFraction":0.75,"resetTime":"2026-10-01T00:00:00Z"},{"window":"weekly","remainingFraction":0},{"window":"monthly","remainingFraction":1}]}]}"#
        let quota = try ActiveQuotaParser.parsePlugin(Data(body.utf8))
        XCTAssertEqual(quota.models.map(\.percentage), [75, 0, 100])
        XCTAssertEqual(quota.models.map(\.displayName), ["Rolling", "Weekly", "Monthly"])
        XCTAssertEqual(quota.planType, "Go")
        XCTAssertNil(quota.models[0].windowDuration)
        XCTAssertEqual(quota.models[1].windowDuration, 604800)
        XCTAssertNil(quota.models[2].windowDuration)
    }
    func testInvalidOrMissingReadingsStayUnknown() {
        for body in ["{}", #"{"groups":[{"buckets":[{"window":"weekly"}]}]}"#, #"{"groups":[{"buckets":[{"window":"weekly","remainingFraction":2}]}]}"#, #"{"groups":[{"buckets":[{"window":"weekly","remainingFraction":true}]}]}"#] {
            XCTAssertThrowsError(try ActiveQuotaParser.parsePlugin(Data(body.utf8)))
        }
    }
    func testNameSurvivesCacheWithoutCredential() throws {
        var account = try JSONDecoder().decode(ProxyAccount.self, from: Data(#"{"name":"OpenCode-Go.json","provider":"opencode-go","label":"Personal","auth_index":"private-index"}"#.utf8))
        account.fetchedQuota = ProviderQuota(models: [QuotaMetric(name: "opencode-go-weekly", percentage: 75, resetTime: "")], accountDisplayName: account.displayName)
        XCTAssertEqual(account.displayName, "Personal")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = QuotaCache(endpoint: "http://localhost:8317", directory: directory)
        try cache.save([account])
        XCTAssertEqual(try cache.load().first?.displayName, "Personal")
        XCTAssertFalse(try String(contentsOf: cache.url, encoding: .utf8).contains("private-index"))
    }
}
