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
}
