import XCTest
import CLIProxyBarCore
@testable import MenuBar

final class ActiveQuotaTests: XCTestCase {
    func testClaudeActiveEndpointUsesPercentNotHeaderFraction() throws {
        let now = Date(timeIntervalSince1970: 123)
        let data = Data(#"{"five_hour":{"utilization":72,"resets_at":"2026-09-28T19:29:59Z"},"seven_day":{"utilization":35},"seven_day_sonnet":null}"#.utf8)
        let quota = try ActiveQuotaParser.parse(data, provider: "claude", now: now)
        XCTAssertEqual(quota.models.map(\.percentage), [28, 65])
        XCTAssertEqual(quota.lastUpdated, now)
        XCTAssertEqual(quota.models[0].resetTime, "2026-09-28T19:29:59Z")
    }
    func testUnusedClaudeAccountStillHasFullQuota() throws {
        let quota = try ActiveQuotaParser.parse(Data(#"{"five_hour":{"utilization":0},"seven_day":{"utilization":0}}"#.utf8), provider: "claude")
        XCTAssertEqual(quota.models.map(\.percentage), [100, 100])
    }
    func testFreshQuotaDistinguishesCooldownFromDisabledAccount() throws {
        let quota = try ActiveQuotaParser.parse(Data(#"{"five_hour":{"utilization":100},"seven_day":{"utilization":85}}"#.utf8), provider: "claude")
        for disabled in [false, true] {
            var account = try JSONDecoder().decode(ProxyAccount.self, from: Data("{\"name\":\"test\",\"provider\":\"claude\",\"disabled\":\(disabled),\"unavailable\":true}".utf8))
            account.fetchedQuota = quota
            let displayed = account.providerQuota()
            XCTAssertEqual(displayed.isForbidden, disabled)
            XCTAssertEqual(displayed.models.map(\.percentage), [0, 15])
        }
    }
    func testCodexWeeklyPrimaryAndNullSecondary() throws {
        let data = Data(#"{"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":35,"limit_window_seconds":604800,"reset_at":1791180182},"secondary_window":null}}"#.utf8)
        let quota = try ActiveQuotaParser.parse(data, provider: "codex")
        XCTAssertEqual(quota.models.count, 1)
        XCTAssertEqual(quota.models[0].name, "codex-weekly")
        XCTAssertEqual(quota.models[0].percentage, 65)
        XCTAssertEqual(quota.planType, "pro")
    }
    func testInvalidProviderResponsesDoNotReplaceGoodReadings() {
        for body in ["{}", #"{"error":{"type":"unauthorized"}}"#, #"{"five_hour":{"utilization":true}}"#, #"{"five_hour":{"utilization":-1}}"#, #"{"five_hour":{"utilization":101}}"#] {
            XCTAssertThrowsError(try ActiveQuotaParser.parse(Data(body.utf8), provider: "claude"))
        }
    }
    func testProxySubstitutesTokenAndSelectsAccount() throws {
        let account = try JSONDecoder().decode(ProxyAccount.self, from: Data(#"{"name":"test","provider":"codex","auth_index":"index-1","id_token":{"chatgpt_account_id":"account-1"}}"#.utf8))
        let request = try ActiveQuotaParser.request(for: account)
        XCTAssertEqual(request.authIndex, "index-1")
        XCTAssertEqual(request.header?["Authorization"], "Bearer $TOKEN$")
        XCTAssertEqual(request.header?["ChatGPT-Account-Id"], "account-1")
        XCTAssertEqual(request.url, "https://chatgpt.com/backend-api/wham/usage")
        XCTAssertEqual(request.method, "GET")
    }
    func testMissingAuthIndexFailsRatherThanUsingAnotherAccount() throws {
        let account = try JSONDecoder().decode(ProxyAccount.self, from: Data(#"{"name":"test","provider":"claude"}"#.utf8))
        XCTAssertThrowsError(try ActiveQuotaParser.request(for: account))
    }
    func testCacheRestoresWithoutCredentialsAndIsPrivate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = QuotaCache(endpoint: "http://127.0.0.1:8317", directory: directory)
        var account = ProxyAccount(name: "test", provider: "claude", email: "test@example.com", disabled: nil, unavailable: nil, quota: nil, model_quotas: nil)
        account.auth_index = "do-not-persist"
        account.fetchedQuota = ProviderQuota(models: [QuotaMetric(name: "five-hour-session", percentage: 28, resetTime: "")], lastUpdated: Date(timeIntervalSince1970: 123))
        try cache.save([account])
        let restored = try cache.load()
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored[0].providerQuota().models[0].percentage, 28)
        XCTAssertEqual(restored[0].providerQuota().lastUpdated, Date(timeIntervalSince1970: 123))
        XCTAssertNotNil(restored[0].quotaIssue)
        XCTAssertNil(restored[0].auth_index)
        let raw = try String(contentsOf: cache.url, encoding: .utf8)
        XCTAssertFalse(raw.contains("do-not-persist"))
        let permissions = try FileManager.default.attributesOfItem(atPath: cache.url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        XCTAssertTrue(try QuotaCache(endpoint: "http://127.0.0.1:9999", directory: directory).load().isEmpty)
        let fresh = ProxyAccount(name: "test", provider: "claude", email: nil, disabled: nil, unavailable: nil, quota: nil, model_quotas: nil)
        let merged = QuotaCache.merging([fresh], previous: restored)
        XCTAssertEqual(merged[0].providerQuota().models[0].percentage, 28)
        XCTAssertTrue(QuotaCache.merging([], previous: restored).isEmpty)
    }
    func testCorruptCacheIsReported() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cache = QuotaCache(endpoint: "http://127.0.0.1:8317", directory: directory)
        try Data("invalid".utf8).write(to: cache.url)
        XCTAssertThrowsError(try cache.load())
    }
}
