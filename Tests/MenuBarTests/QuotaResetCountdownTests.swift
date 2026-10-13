import AppKit
import SwiftUI
import XCTest
import CLIProxyBarCore
@testable import MenuBar

final class QuotaResetCountdownTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1800000000)

    private func metric(_ name: String, remaining: Double = 0, resetIn: TimeInterval?) -> QuotaMetric {
        QuotaMetric(name: name, percentage: remaining,
            resetTime: resetIn.map { ISO8601DateFormatter().string(from: now.addingTimeInterval($0)) } ?? "")
    }

    func testCompactUnitsRoundUpAndNeverShowZeroBeforeReset() {
        for (interval, expected) in [
            (0.1, "<1m"), (59.0, "<1m"), (60.0, "1m"), (61.0, "2m"),
            (2490.0, "42m"), (3599.0, "60m"), (3600.0, "1h"), (9000.0, "3h"),
            (86399.0, "24h"), (86400.0, "1d"), (129600.0, "2d")
        ] {
            XCTAssertEqual(QuotaResetCountdown.value(remainingPercentage: 0,
                resetAt: now.addingTimeInterval(interval), now: now)?.text, expected)
        }
    }

    func testUnknownAlmostExhaustedAndExpiredReadingsKeepPercentages() {
        let future = now.addingTimeInterval(3600)
        for percentage in [-1.0, 0.01, 0.4, 100, .nan, .infinity] {
            XCTAssertNil(QuotaResetCountdown.value(remainingPercentage: percentage, resetAt: future, now: now))
        }
        for reset in [nil, now, now.addingTimeInterval(-1)] as [Date?] {
            XCTAssertNil(QuotaResetCountdown.value(remainingPercentage: 0, resetAt: reset, now: now))
        }
        XCTAssertNil(QuotaResetCountdown.resetDate(""))
        XCTAssertNil(QuotaResetCountdown.resetDate("invalid"))
        XCTAssertEqual(QuotaResetCountdown.resetDate("2027-01-15T08:00:00.123Z"),
            ProxyAccount.observationDate("2027-01-15T08:00:00.123Z"))
    }

    func testSingleValueUsesLastResetOfTiedLimitsAndRequiresAllResetTimes() throws {
        let models = [metric("session", resetIn: 7200), metric("weekly", resetIn: 259200),
            metric("monthly", remaining: 12, resetIn: 864000)]
        let lowest = try XCTUnwrap(MenuBarQuotaMetric.lowest(in: models, labelKey: ""))
        XCTAssertEqual(lowest.remainingPercentage, 0)
        XCTAssertEqual(lowest.resetAt, now.addingTimeInterval(259200))
        XCTAssertEqual(QuotaResetCountdown.value(remainingPercentage: lowest.remainingPercentage,
            resetAt: lowest.resetAt, now: now)?.text, "3d")
        let missing = try XCTUnwrap(MenuBarQuotaMetric.lowest(in: models + [metric("unknown", resetIn: nil)], labelKey: ""))
        XCTAssertNil(missing.resetAt)
        XCTAssertEqual(missing.remainingPercentage, 0)
        XCTAssertNil(MenuBarQuotaMetric.lowest(in: [], labelKey: ""))
    }

    func testPairedQuotasKeepTheirOwnResetTimesAndLiveLabelChanges() throws {
        let pair = try XCTUnwrap(MenuBarQuotaPair.resolve(for: .claude, from: [
            metric("five-hour-session", resetIn: 2490), metric("seven-day-weekly", resetIn: 129600)
        ]))
        var item = MenuBarQuotaDisplayItem(id: "fixture", providerSymbol: "C", accountShort: "", percentage: 0,
            provider: .claude, quotaPair: pair, showsResetCountdown: true)
        XCTAssertEqual(item.resetCountdownLabels(now: now), ["42m", "2d"])
        XCTAssertEqual(item.resetCountdownLabels(now: now.addingTimeInterval(60)), ["41m", "2d"])
        XCTAssertEqual(item.resetCountdownLabels(now: now.addingTimeInterval(2490)), ["2d"])
        item.isForbidden = true
        XCTAssertTrue(item.resetCountdownLabels(now: now).isEmpty)
        let disabledOption = MenuBarQuotaDisplayItem(id: "fixture", providerSymbol: "C", accountShort: "", percentage: 0,
            provider: .claude, quotaPair: pair)
        XCTAssertTrue(disabledOption.resetCountdownLabels(now: now).isEmpty)
    }

    @MainActor
    func testCountdownAccessibilityDoesNotDependOnUsageOrRemainingDisplayMode() throws {
        let exhausted = MenuBarQuotaMetric(labelKey: "quota.metric.session", remainingPercentage: 0,
            resetAt: now.addingTimeInterval(2490))
        for mode in [QuotaDisplayMode.used, .remaining] {
            XCTAssertEqual(StatusBarQuotaItemView.accessibilityValue(for: exhausted, displayMode: mode,
                showsResetCountdown: true, now: now), "Resets in 42 minutes")
            XCTAssertFalse(StatusBarQuotaItemView.accessibilityValue(for: exhausted, displayMode: mode,
                showsResetCountdown: false, now: now).contains("Resets"))
        }
    }

    @MainActor
    func testCountdownOptionsAreIndependentPersistAndStartDisabled() {
        let suite = "QuotaResetCountdownTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DisplayPreferences(defaults: defaults)
        XCTAssertFalse(preferences.showsResetCountdownInMenuBar)
        XCTAssertFalse(preferences.showsResetCountdownInCompactMenu)
        var changes = 0
        preferences.onChange = { changes += 1 }
        preferences.showsResetCountdownInMenuBar = true
        preferences.showsResetCountdownInMenuBar = true
        var restored = DisplayPreferences(defaults: defaults)
        XCTAssertTrue(restored.showsResetCountdownInMenuBar)
        XCTAssertFalse(restored.showsResetCountdownInCompactMenu)
        preferences.showsResetCountdownInCompactMenu = true
        preferences.showsResetCountdownInMenuBar = false
        restored = DisplayPreferences(defaults: defaults)
        XCTAssertFalse(restored.showsResetCountdownInMenuBar)
        XCTAssertTrue(restored.showsResetCountdownInCompactMenu)
        XCTAssertTrue(restored.showsBothMenuBarQuotas)
        XCTAssertEqual(changes, 3)
    }

    @MainActor
    func testCountdownViewsStayCompactAndCanExportFictionalPreview() throws {
        let observed = Date()
        let models = [
            QuotaMetric(name: "five-hour-session", percentage: 0,
                resetTime: ISO8601DateFormatter().string(from: observed.addingTimeInterval(2490))),
            QuotaMetric(name: "seven-day-weekly", percentage: 32,
                resetTime: ISO8601DateFormatter().string(from: observed.addingTimeInterval(129600)))
        ]
        let account = StatusBarMenuAccountSnapshot(id: QuotaAccountID(provider: .claude, accountKey: "fixture"),
            email: "Personal", quota: ProviderQuota(models: models, lastUpdated: observed), subscription: nil,
            isActiveInIDE: false, isRefreshing: false, isRefreshBlocked: false)
        let pair = try XCTUnwrap(MenuBarQuotaPair.resolve(for: .claude, from: models))
        let item = MenuBarQuotaDisplayItem(id: "fixture", providerSymbol: "C", accountShort: "", percentage: 0,
            provider: .claude, quotaPair: pair, showsResetCountdown: true)
        let menuBar = StatusBarQuotaView(items: [item], colorMode: .monochrome, quotaDisplayMode: .used, now: observed)
        let compact = CompactQuotaAccountView(provider: .claude, providerName: "Claude Code", account: account,
            showAccountName: false, displayMode: .used, showsResetCountdown: true).frame(width: 280)
        // Size checks also run on Intel CI's virtual GPU. Raster exports are
        // opt-in because that device cannot run SwiftUI's Metal renderer.
        let barLayout = NSHostingView(rootView: menuBar).intrinsicContentSize
        XCTAssertLessThan(barLayout.width, 80)
        XCTAssertEqual(barLayout.height, 22)
        let menuLayout = NSHostingView(rootView: compact).intrinsicContentSize
        XCTAssertEqual(menuLayout.width, 280)
        XCTAssertLessThan(menuLayout.height, 120)
        if let path = ProcessInfo.processInfo.environment["CLIPROXYBAR_RESET_COUNTDOWN_PREVIEW"] {
            for (suffix, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
                let preview = VStack(alignment: .leading, spacing: 12) {
                    Text("Menu bar").font(.caption).foregroundStyle(.secondary)
                    menuBar
                    Divider()
                    Text("Compact menu").font(.caption).foregroundStyle(.secondary)
                    compact
                }.padding(16).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: preview)
                renderer.scale = 2
                let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: path + "-" + suffix + ".png"))
            }
        }
    }
}
