import XCTest
import CLIProxyBarCore
@testable import MenuBar

final class QuotaPaceTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1800000000)
    func metric(used: Double, elapsed: Double, duration: Double = 18000) -> QuotaMetric {
        QuotaMetric(name: "five-hour-session", percentage: 100 - used,
                    resetTime: ISO8601DateFormatter().string(from: now.addingTimeInterval(duration - elapsed)),
                    windowDuration: duration)
    }
    func testReserveLastsUntilReset() throws {
        let pace = try XCTUnwrap(QuotaPace.calculate(metric: metric(used: 72, elapsed: 14760), observedAt: now, now: now))
        XCTAssertEqual(pace.expectedUsedPercent, 82, accuracy: 0.001)
        XCTAssertEqual(pace.reservePoints, 10, accuracy: 0.001)
        XCTAssertTrue(pace.lastsUntilReset)
        XCTAssertEqual(pace.markerPercent(mode: .remaining), 18, accuracy: 0.001)
        XCTAssertEqual(pace.markerPercent(mode: .used), 82, accuracy: 0.001)
    }
    func testWeeklyDeficitProjectsExhaustion() throws {
        let pace = try XCTUnwrap(QuotaPace.calculate(metric: metric(used: 37, elapsed: 42336, duration: 604800), observedAt: now, now: now))
        XCTAssertEqual(pace.reservePoints, -30, accuracy: 0.001)
        XCTAssertFalse(pace.lastsUntilReset)
        XCTAssertEqual(try XCTUnwrap(pace.timeUntilExhaustion), 42336 * 63 / 37, accuracy: 0.01)
    }
    func testZeroUseAndExhaustedQuota() throws {
        let unused = try XCTUnwrap(QuotaPace.calculate(metric: metric(used: 0, elapsed: 3600), observedAt: now, now: now))
        XCTAssertNil(unused.timeUntilExhaustion)
        XCTAssertTrue(unused.lastsUntilReset)
        let exhausted = try XCTUnwrap(QuotaPace.calculate(metric: metric(used: 100, elapsed: 3600), observedAt: now, now: now))
        XCTAssertEqual(exhausted.timeUntilExhaustion, 0)
        XCTAssertFalse(exhausted.lastsUntilReset)
    }
    func testRejectsUnknownExpiredStaleAndNotStartedWindows() {
        XCTAssertNil(QuotaPace.calculate(metric: metric(used: 20, elapsed: 0), observedAt: now, now: now))
        XCTAssertNil(QuotaPace.calculate(metric: metric(used: 20, elapsed: 18001), observedAt: now, now: now))
        XCTAssertNil(QuotaPace.calculate(metric: metric(used: 20, elapsed: 3600), observedAt: now.addingTimeInterval(-901), now: now))
        var unknown = metric(used: 20, elapsed: 3600)
        unknown.windowDuration = nil
        XCTAssertNil(QuotaPace.calculate(metric: unknown, observedAt: now, now: now))
    }
    func testActiveParserRetainsExactCodexWindowDuration() throws {
        let quota = try ActiveQuotaParser.parse(Data(#"{"rate_limit":{"primary_window":{"used_percent":20,"limit_window_seconds":14400,"reset_at":1800003600}}}"#.utf8), provider: "codex", now: now)
        XCTAssertEqual(quota.models[0].windowDuration, 14400)
        let pace = try XCTUnwrap(QuotaPace.calculate(metric: quota.models[0], observedAt: now, now: now))
        XCTAssertEqual(pace.expectedUsedPercent, 75)
    }
    func testOpenCodeRollingPaceUsesBackendResetAndFiveHourDuration() throws {
        let reset = ISO8601DateFormatter().string(from: now.addingTimeInterval(10800))
        let body = try JSONSerialization.data(withJSONObject: ["groups": [["buckets": [
            ["window": "rolling", "remainingFraction": 0.75, "resetTime": reset],
            ["window": "monthly", "remainingFraction": 0.51]
        ]]]])
        let quota = try PluginQuotaParser.parse(body, provider: "opencode-go", now: now)
        let rolling = try XCTUnwrap(quota.models.first)
        XCTAssertEqual(rolling.resetTime, reset)
        let pace = try XCTUnwrap(QuotaPace.calculate(metric: rolling, observedAt: now, now: now))
        XCTAssertEqual(pace.expectedUsedPercent, 40, accuracy: 0.001)
        XCTAssertEqual(pace.reservePoints, 15, accuracy: 0.001)
        XCTAssertEqual(pace.markerPercent(mode: .used), 40, accuracy: 0.001)
        XCTAssertEqual(pace.markerPercent(mode: .remaining), 60, accuracy: 0.001)
        XCTAssertTrue(pace.lastsUntilReset)
        let monthly = try XCTUnwrap(quota.models.last)
        XCTAssertNil(QuotaPace.calculate(metric: monthly, observedAt: now, now: now))
        XCTAssertNil(QuotaPace.calculate(metric: rolling, observedAt: now, now: now.addingTimeInterval(901)))
        let unrelated = try PluginQuotaParser.parse(body, provider: "another-plugin", now: now)
        XCTAssertTrue(unrelated.models.allSatisfy { $0.windowDuration == nil })
    }
    func testOpenCodeRollingPaceRequiresUsableBackendReset() throws {
        for offset in [nil, -1.0, 18001.0] as [Double?] {
            var bucket: [String: Any] = ["window": "rolling", "remainingFraction": 0.75]
            if let offset {
                bucket["resetTime"] = ISO8601DateFormatter().string(from: now.addingTimeInterval(offset))
            }
            let body = try JSONSerialization.data(withJSONObject: ["groups": [["buckets": [bucket]]]])
            let quota = try PluginQuotaParser.parse(body, provider: "opencode-go", now: now)
            let rolling = try XCTUnwrap(quota.models.first)
            XCTAssertNil(QuotaPace.calculate(metric: rolling, observedAt: now, now: now))
        }
    }
}
