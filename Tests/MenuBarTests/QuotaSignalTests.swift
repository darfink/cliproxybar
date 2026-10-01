import XCTest
@testable import MenuBar

final class QuotaSignalTests: XCTestCase {
    func decode(_ json: String) throws -> ProxyAccount { try JSONDecoder().decode(ProxyAccount.self, from: Data(json.utf8)) }
    func testClaudeFractionsBecomeRemainingPercentages() throws {
        let account = try decode(#"{"name":"test","provider":"claude","model_quotas":{"opus":{"observed_at":"2026-09-28T16:17:03Z","signals":{"Anthropic-Ratelimit-Unified-5h-Utilization":"0.71","Anthropic-Ratelimit-Unified-7d-Utilization":"0.34","Anthropic-Ratelimit-Unified-5h-Reset":"1790623800"}}}}"#)
        let quota = account.providerQuota()
        XCTAssertEqual(quota.models.map(\.name), ["five-hour-session", "seven-day-weekly"])
        XCTAssertEqual(quota.models[0].percentage, 29, accuracy: 0.001)
        XCTAssertEqual(quota.models[1].percentage, 66, accuracy: 0.001)
        XCTAssertFalse(quota.models[0].resetTime.isEmpty)
    }
    func testCodexPrimaryMayBeWeeklyAndZeroWindowIsOmitted() throws {
        let account = try decode(#"{"name":"test","provider":"codex","quota":{"signals":{"X-Codex-Primary-Window-Minutes":"10080","X-Codex-Primary-Used-Percent":"33","X-Codex-Secondary-Window-Minutes":"0","X-Codex-Secondary-Used-Percent":"0"}}}"#)
        let models = account.providerQuota().models
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models[0].name, "codex-weekly")
        XCTAssertEqual(models[0].percentage, 67)
    }
    func testNewestObservationWinsAndEmptyQuotaDoesNotHideModelSignals() throws {
        let account = try decode(#"{"name":"test","provider":"claude","quota":{"signals":{}},"model_quotas":{"old":{"observed_at":"2026-09-27T16:17:03Z","signals":{"Anthropic-Ratelimit-Unified-5h-Utilization":"0.1"}},"new":{"observed_at":"2026-09-28T16:17:03Z","signals":{"Anthropic-Ratelimit-Unified-5h-Utilization":"0.8"}}}}"#)
        XCTAssertEqual(account.providerQuota().models[0].percentage, 20, accuracy: 0.001)
    }
    func testMissingAndInvalidSignalsStayUnknown() throws {
        for signals in ["{}", #"{"Anthropic-Ratelimit-Unified-5h-Utilization":"nan"}"#, #"{"Anthropic-Ratelimit-Unified-5h-Utilization":"-1"}"#] {
            let account = try decode("{\"name\":\"test\",\"provider\":\"claude\",\"quota\":{\"signals\":\(signals)}}")
            XCTAssertTrue(account.providerQuota().models.isEmpty)
        }
    }
    func testDisabledAccountIsFlagged() throws {
        XCTAssertTrue(try decode(#"{"name":"test","provider":"claude","disabled":true}"#).providerQuota().isForbidden)
    }
    func testQuotaCooldownKeepsPassivePercentagesWithoutDisabledFlag() throws {
        let account = try decode(#"{"name":"test","provider":"claude","disabled":false,"unavailable":true,"quota":{"signals":{"Anthropic-Ratelimit-Unified-5h-Utilization":"1","Anthropic-Ratelimit-Unified-7d-Utilization":"0.85"}}}"#)
        let quota = account.providerQuota()
        XCTAssertFalse(quota.isForbidden)
        XCTAssertEqual(quota.models[0].percentage, 0)
        XCTAssertEqual(quota.models[1].percentage, 15, accuracy: 0.001)
        let pair = try XCTUnwrap(MenuBarQuotaPair.resolve(for: .claude, from: quota.models))
        XCTAssertEqual(pair.top.remainingPercentage, 0)
        XCTAssertEqual(pair.bottom.remainingPercentage, 15, accuracy: 0.001)
    }
    func testProxyUnavailabilityDoesNotImplyDisablement() throws {
        XCTAssertFalse(try decode(#"{"name":"test","provider":"claude","unavailable":true}"#).providerQuota().isForbidden)
    }
    func testRejectsNonLocalOrCredentialBearingEndpoints() throws {
        for endpoint in ["http://example.com", "https://127.0.0.1:8317", "http://user:pass@localhost:8317", "http://localhost:8317/path", "http://localhost:8317?token=secret"] {
            XCTAssertThrowsError(try LocalProxyClient(endpoint: endpoint))
        }
        XCTAssertNoThrow(try LocalProxyClient(endpoint: "http://127.0.0.1:8317"))
    }
}
