import XCTest
import CLIProxyBarCore
@testable import MenuBar

final class OpenCodeMonthlyPaceTests: XCTestCase {
    private func date(_ value: String) -> Date { ProxyAccount.observationDate(value) }

    private func monthly(reset: String?, observedAt: String, provider: String = "opencode-go",
                         offset: Double = 0) throws -> QuotaMetric {
        var bucket: [String: Any] = ["window": "monthly", "remainingFraction": 0.51]
        if let reset { bucket["resetTime"] = reset }
        let body = try JSONSerialization.data(withJSONObject: ["serverTimeOffsetMs": offset,
            "groups": [["buckets": [bucket]]]])
        let quota = try PluginQuotaParser.parse(body, provider: provider, now: date(observedAt))
        return try XCTUnwrap(quota.models.first)
    }

    func testMonthlyPaceUsesUnambiguousBackendBillingCycle() throws {
        let observedAt = date("2026-10-12T10:21:00Z")
        let metric = try monthly(reset: "2026-11-07T22:21:00Z", observedAt: "2026-10-12T10:21:00Z")
        XCTAssertEqual(metric.windowDuration, 31 * 86400)
        XCTAssertEqual(metric.resetTime, "2026-11-07T22:21:00Z")
        let pace = try XCTUnwrap(QuotaPace.calculate(metric: metric, observedAt: observedAt, now: observedAt))
        let expected = 4.5 / 31 * 100
        XCTAssertEqual(pace.expectedUsedPercent, expected, accuracy: 0.001)
        XCTAssertEqual(pace.reservePoints, expected - 49, accuracy: 0.001)
        XCTAssertEqual(pace.markerPercent(mode: .used), expected, accuracy: 0.001)
        XCTAssertEqual(pace.markerPercent(mode: .remaining), 100 - expected, accuracy: 0.001)
        XCTAssertFalse(pace.lastsUntilReset)
        XCTAssertNil(QuotaPace.calculate(metric: metric, observedAt: observedAt, now: observedAt.addingTimeInterval(901)))
    }

    func testMonthlyDurationHandlesDifferentMonthLengthsAndYearBoundary() throws {
        for (observedAt, reset, days) in [
            ("2026-02-12T10:00:00Z", "2026-03-07T22:21:00Z", 28),
            ("2024-02-12T10:00:00Z", "2024-03-07T22:21:00Z", 29),
            ("2026-04-12T10:00:00Z", "2026-05-07T22:21:00Z", 30),
            ("2026-10-12T10:00:00Z", "2026-11-07T22:21:00Z", 31),
            ("2026-12-12T10:00:00Z", "2027-01-07T22:21:00Z", 31)
        ] {
            let metric = try monthly(reset: reset, observedAt: observedAt)
            XCTAssertEqual(metric.windowDuration, Double(days * 86400), reset)
        }
    }

    func testUnambiguousAnchorClampsPreviousShortMonth() throws {
        for (observedAt, reset) in [
            ("2026-03-12T10:00:00Z", "2026-03-31T22:21:00Z"),
            ("2024-03-12T10:00:00Z", "2024-03-31T22:21:00Z"),
            ("2026-05-12T10:00:00Z", "2026-05-31T22:21:00Z")
        ] {
            let metric = try monthly(reset: reset, observedAt: observedAt)
            XCTAssertEqual(metric.windowDuration, 31 * 86400, reset)
        }
    }

    func testAmbiguousShortMonthResetsHaveNoPace() throws {
        for (observedAt, reset) in [
            ("2026-02-12T10:00:00Z", "2026-02-28T22:21:00Z"),
            ("2024-02-12T10:00:00Z", "2024-02-29T22:21:00Z"),
            ("2026-04-12T10:00:00Z", "2026-04-30T22:21:00Z")
        ] {
            let metric = try monthly(reset: reset, observedAt: observedAt)
            XCTAssertEqual(metric.resetTime, reset)
            XCTAssertNil(metric.windowDuration, reset)
            XCTAssertNil(QuotaPace.calculate(metric: metric, observedAt: date(observedAt), now: date(observedAt)))
        }
    }

    func testObservationCanExcludeBillingAnchorsThatHaveNotStarted() throws {
        let metric = try monthly(reset: "2026-02-28T22:21:00Z", observedAt: "2026-01-28T23:21:00Z")
        XCTAssertEqual(metric.windowDuration, 31 * 86400)
        let later = try monthly(reset: "2026-02-28T22:21:00Z", observedAt: "2026-01-29T23:21:00Z")
        XCTAssertNil(later.windowDuration)
    }

    func testMissingExpiredAndFutureCycleDatesHaveNoPace() throws {
        for reset in [nil, "invalid", "2026-10-12T10:21:00Z", "2026-10-07T22:21:00Z", "2026-12-07T22:21:00Z"] {
            let metric = try monthly(reset: reset, observedAt: "2026-10-12T10:21:00Z")
            XCTAssertNil(metric.windowDuration)
        }
    }

    func testBillingCalendarUsesServerUTCBeforeClockCorrection() throws {
        let metric = try monthly(reset: "2026-03-01T00:30:00Z", observedAt: "2026-02-12T10:00:00Z", offset: 3600000)
        XCTAssertEqual(metric.windowDuration, 28 * 86400)
        XCTAssertEqual(metric.resetTime, "2026-02-28T23:30:00Z")
        let ambiguous = try monthly(reset: "2026-02-28T00:30:00Z", observedAt: "2026-02-12T10:00:00Z", offset: 3600000)
        XCTAssertNil(ambiguous.windowDuration)
        XCTAssertEqual(ambiguous.resetTime, "2026-02-27T23:30:00Z")
    }

    func testOtherPluginsDoNotInheritOpenCodeBillingRules() throws {
        let metric = try monthly(reset: "2026-11-07T22:21:00Z", observedAt: "2026-10-12T10:21:00Z", provider: "another-plugin")
        XCTAssertNil(metric.windowDuration)
    }
}
