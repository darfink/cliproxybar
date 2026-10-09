import AppKit
import XCTest
@testable import MenuBar

final class UsagePresentationTests: XCTestCase {
    func testActivityColorsKeepDistinctLevelsWithLargeTokenCountsAndOutliers() {
        let values: [Int64] = [100_000, 120_000, 140_000, 160_000, 180_000, 200_000, 220_000, 90_000_000]
        let scale = UsageActivityScale(values: values + [0, 0, 0])
        XCTAssertEqual(values.map { scale.level(for: $0) }, [1, 1, 2, 2, 3, 3, 4, 4])
        XCTAssertEqual(scale.level(for: 0), 0)
        XCTAssertEqual(scale.level(for: -1), 0)
        XCTAssertGreaterThan(UsageActivityScale.opacity(for: 4) - UsageActivityScale.opacity(for: 1), 0.7)
    }

    func testActivityColorsKeepEqualCountsEqualAndHandleEmptyHistory() {
        XCTAssertEqual(UsageActivityScale(values: []).level(for: 0), 0)
        XCTAssertEqual(UsageActivityScale(values: [0, 0]).level(for: 0), 0)
        let scale = UsageActivityScale(values: [7, 7, 7, 7])
        XCTAssertEqual(scale.level(for: 7), 4)
        var day = ProxyUsageDay(date: Date(), requests: 7)
        day.tokens.total = 100_000
        XCTAssertEqual(UsageActivityMeasure.requests.value(for: day), 7)
        XCTAssertEqual(UsageActivityMeasure.tokens.value(for: day), 100_000)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return calendar
    }

    func testMeasureChangesPeriodTotalsAndModelRankingWithinThirtyCalendarDays() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 12)))
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int, requests: Int64, tokens: Int64, model: String) -> ProxyUsageDay {
            var day = ProxyUsageDay(date: calendar.date(byAdding: .day, value: offset, to: today)!, requests: requests)
            day.tokens.total = tokens
            day.models[model] = ProxyUsageModelTotals(requests: requests, tokens: day.tokens)
            return day
        }
        let usage = ProxyUsageSnapshot(days: [
            day(0, requests: 2, tokens: 900_000, model: "Long context"),
            day(-1, requests: 80, tokens: 40_000, model: "Short requests"),
            day(-29, requests: 20, tokens: 10_000, model: "Short requests"),
            day(-30, requests: 500, tokens: 9_000_000, model: "Outside the period"),
            day(1, requests: 500, tokens: 9_000_000, model: "Future"),
        ], startedAt: today)
        let summary = ProxyUsageSummary(usage: usage, now: now, calendar: calendar)
        XCTAssertEqual(summary.value(on: summary.today, measure: .tokens), 900_000)
        XCTAssertEqual(summary.value(on: summary.today, measure: .requests), 2)
        XCTAssertEqual(summary.value(on: summary.yesterday, measure: .tokens), 40_000)
        XCTAssertEqual(summary.value(on: summary.yesterday, measure: .requests), 80)
        XCTAssertEqual(summary.value(measure: .tokens), 950_000)
        XCTAssertEqual(summary.value(measure: .requests), 102)
        XCTAssertEqual(summary.tokens.total, 950_000)
        let tokens = summary.models(measure: .tokens)
        let requests = summary.models(measure: .requests)
        XCTAssertEqual(tokens.map(\.0), ["Long context", "Short requests"])
        XCTAssertEqual(requests.map(\.0), ["Short requests", "Long context"])
        XCTAssertEqual(UsageActivityMeasure.requests.value(for: requests[0].1), 100)
        XCTAssertEqual(UsageActivityMeasure.tokens.value(for: tokens[0].1), 900_000)
    }

    func testActivitySeparatesTodayFutureZeroAndUnrecordedDays() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 12)))
        let start = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: now))
        let grid = UsageActivityCalendar(days: [], startedAt: start, now: now, calendar: calendar)
        XCTAssertEqual(calendar.component(.weekday, from: grid.start), 2)
        XCTAssertEqual(grid.date(week: 25, weekday: 4), grid.today)
        XCTAssertEqual(grid.status(on: grid.today), .recorded)
        XCTAssertEqual(grid.status(on: grid.date(week: 25, weekday: 5)), .upcoming)
        XCTAssertEqual(grid.status(on: grid.date(week: 25, weekday: 0)), .unrecorded)
        XCTAssertEqual(grid.detail(on: grid.today), "0 tokens · 0 requests")
        XCTAssertEqual(grid.detail(on: grid.date(week: 25, weekday: 5)), "Upcoming day")
        XCTAssertEqual(grid.detail(on: grid.start), "No recorded history")
        XCTAssertEqual(calendar.dateComponents([.day], from: grid.start, to: grid.date(week: 25, weekday: 6)).day, 181)
    }

    func testActivityUsesCalendarDaysAcrossDaylightSavingsAndIncludesRecordedEvents() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 30, hour: 12)))
        let yesterday = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: now)!)
        var day = ProxyUsageDay(date: yesterday, requests: 3, failures: 1)
        day.tokens.total = 500
        let grid = UsageActivityCalendar(days: [day], startedAt: now, now: now, calendar: calendar)
        XCTAssertEqual(grid.date(week: 24, weekday: 6), yesterday)
        XCTAssertEqual(grid.today.timeIntervalSince(yesterday), 23 * 3600)
        XCTAssertEqual(grid.status(on: yesterday), .recorded)
        XCTAssertEqual(grid.detail(on: yesterday), "500 tokens · 3 requests · 1 failed")
        let disabled = UsageActivityCalendar(days: [], startedAt: nil, now: now, calendar: calendar)
        XCTAssertEqual(disabled.status(on: disabled.today), .unrecorded)
    }

    func testUsageMenuAlignsToAccountAndSwitchesSides() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let menu = NSRect(x: 1100, y: 80, width: 330, height: 800)
        let account = NSRect(x: 1110, y: 500, width: 310, height: 150)
        let placement = UsageMenuPlacement.calculate(anchor: account, menu: menu,
            size: NSSize(width: 532, height: 500), screen: screen)
        XCTAssertTrue(placement.isLeftOfMenu)
        XCTAssertEqual(placement.frame.maxY, account.maxY)
        XCTAssertEqual(placement.frame.maxX, menu.minX - 6)
        let leftMenu = NSRect(x: 50, y: 80, width: 330, height: 800)
        let right = UsageMenuPlacement.calculate(anchor: NSRect(x: 60, y: 500, width: 310, height: 150),
            menu: leftMenu, size: placement.frame.size, screen: screen)
        XCTAssertFalse(right.isLeftOfMenu)
        XCTAssertEqual(right.frame.minX, leftMenu.maxX + 6)
    }

    func testUsageMenuClampsAtScreenEdges() {
        // A second monitor can have a negative origin. Bounds must stay local to it.
        let screen = NSRect(x: -1440, y: 0, width: 1440, height: 700)
        let account = NSRect(x: -320, y: 30, width: 300, height: 90)
        let placement = UsageMenuPlacement.calculate(anchor: account,
            menu: NSRect(x: -330, y: 10, width: 320, height: 680),
            size: NSSize(width: 532, height: 900), screen: screen)
        XCTAssertEqual(placement.frame.height, 684)
        XCTAssertTrue(screen.contains(placement.frame))
        XCTAssertEqual(placement.frame.minY, screen.minY + 8)
    }
}
