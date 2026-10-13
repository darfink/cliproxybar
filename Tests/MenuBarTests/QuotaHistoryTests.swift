import AppKit
import SwiftUI
import XCTest
import CLIProxyBarCore
@testable import MenuBar

final class QuotaHistoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1800000000)

    private func account(_ name: String = "private-account-name", provider: String = "claude") -> ProxyAccount {
        var account = ProxyAccount(name: name, provider: provider, email: "private@example.test", disabled: false,
            unavailable: false, quota: nil, model_quotas: nil)
        account.auth_index = "private-auth-index"
        return account
    }

    @MainActor private func reading(_ used: Double, at date: Date, account: inout ProxyAccount,
                                    name: String = "five-hour-session") -> ProviderQuota {
        let quota = ProviderQuota(models: [QuotaMetric(name: name, percentage: 100 - used, resetTime: "")], lastUpdated: date)
        account.recordQuota(quota)
        return quota
    }

    @MainActor func testFreshQuotaHistoryPersistsWithoutCredentialsOrRawIdentifiers() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var history = QuotaHistory(endpoint: "https://private-proxy.test", directory: directory)
        var account = account()
        for (offset, used) in [(0.0, 15.0), (300, 20), (600, 0)] {
            let quota = reading(used, at: now.addingTimeInterval(offset), account: &account)
            history.record(account: account, quota: quota, now: quota.lastUpdated)
        }
        try history.save()
        let text = try String(contentsOf: history.url, encoding: .utf8)
        for value in ["private-account-name", "private-auth-index", "private@example.test", "private-proxy.test", "five-hour-session"] {
            XCTAssertFalse(text.contains(value))
        }
        let mode = try FileManager.default.attributesOfItem(atPath: history.url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
        var restored = QuotaHistory(endpoint: "https://private-proxy.test", directory: directory)
        try restored.load()
        let series = try XCTUnwrap(restored.snapshot(for: account, now: now.addingTimeInterval(600)).series.first)
        XCTAssertEqual(series.points.map(\.usedPercent), [15, 20, 0])
        XCTAssertEqual(series.points.map(\.date), [now, now.addingTimeInterval(300), now.addingTimeInterval(600)])
        var otherAccount = self.account("other")
        otherAccount.recordQuota(account.providerQuota())
        XCTAssertTrue(restored.snapshot(for: otherAccount, now: now.addingTimeInterval(600)).series.allSatisfy { $0.points.isEmpty })
        let otherEndpoint = QuotaHistory(endpoint: "https://different.test", directory: directory)
        XCTAssertNotEqual(otherEndpoint.url, history.url)
    }

    @MainActor func testCachedFailedDisabledAndInvalidReadingsDoNotCreateHistory() {
        var history = QuotaHistory(endpoint: "https://fixture.test")
        var account = account()
        let quota = reading(50, at: now, account: &account)
        for state in [QuotaReadState.cached, .stale, .failed, .unsupported, .pending] {
            account.quotaState = state
            history.record(account: account, quota: quota, now: now)
        }
        account.quotaState = .current
        account = ProxyAccount(name: account.name, provider: account.provider, email: nil, disabled: true,
            unavailable: false, quota: nil, model_quotas: nil, fetchedQuota: quota)
        history.record(account: account, quota: quota, now: now)
        XCTAssertTrue(history.snapshot(for: account, now: now).series.first?.points.isEmpty == true)
        account = self.account()
        let invalid = ProviderQuota(models: [QuotaMetric(name: "invalid", percentage: .nan, resetTime: ""),
            QuotaMetric(name: "unknown", percentage: -1, resetTime: ""), QuotaMetric(name: "overflow", percentage: 101, resetTime: "")], lastUpdated: now)
        account.recordQuota(invalid)
        history.record(account: account, quota: invalid, now: now)
        XCTAssertTrue(history.snapshot(for: account, now: now).series.isEmpty)
        for date in [now.addingTimeInterval(120), now.addingTimeInterval(-QuotaHistory.retention - 1)] {
            let dated = reading(30, at: date, account: &account)
            history.record(account: account, quota: dated, now: now)
            XCTAssertTrue(history.snapshot(for: account, now: now).series.first?.points.isEmpty == true)
        }
    }

    @MainActor func testFrequentUnchangedRefreshesCoalesceButResetsAndTimeProgressRemain() throws {
        var history = QuotaHistory(endpoint: "https://fixture.test")
        var account = account()
        for (offset, used) in [(0.0, 100.0), (10, 100), (20, 0), (60, 0)] {
            let quota = reading(used, at: now.addingTimeInterval(offset), account: &account)
            history.record(account: account, quota: quota, now: quota.lastUpdated)
        }
        let points = try XCTUnwrap(history.snapshot(for: account, now: now.addingTimeInterval(60)).series.first).points
        XCTAssertEqual(points.map(\.usedPercent), [100, 0, 0])
        XCTAssertEqual(points.first?.date, now.addingTimeInterval(10))
        let older = reading(90, at: now, account: &account)
        history.record(account: account, quota: older, now: now.addingTimeInterval(60))
        XCTAssertEqual(history.snapshot(for: account, now: now.addingTimeInterval(60)).series.first?.points, points)
    }

    @MainActor func testRetentionAndModelReorderingKeepIndependentWindows() throws {
        var history = QuotaHistory(endpoint: "https://fixture.test")
        var account = account()
        for offset in [0.0, QuotaHistory.retention + 1] {
            let date = now.addingTimeInterval(offset)
            let models = [QuotaMetric(name: "five-hour-session", percentage: 80, resetTime: ""),
                QuotaMetric(name: "seven-day-weekly", percentage: 30, resetTime: "")]
            let quota = ProviderQuota(models: offset == 0 ? models : Array(models.reversed()), lastUpdated: date)
            account.recordQuota(quota)
            history.record(account: account, quota: quota, now: date)
        }
        let snapshot = history.snapshot(for: account, now: now.addingTimeInterval(QuotaHistory.retention + 1))
        XCTAssertEqual(snapshot.series.map(\.id), ["seven-day-weekly", "five-hour-session"])
        XCTAssertEqual(snapshot.series.map { $0.points.map(\.usedPercent) }, [[70], [20]])
        XCTAssertTrue(snapshot.series.allSatisfy { $0.points.count == 1 })
    }

    @MainActor func testPausedRecorderAndCorruptFilesArePreserved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var account = account()
        let quota = reading(25, at: now, account: &account)
        let recorder = QuotaHistoryRecorder(endpoint: "https://fixture.test", directory: directory)
        recorder.isEnabled = false
        recorder.record(account: account, quota: quota, now: now)
        XCTAssertTrue(recorder.snapshot(for: account).series.first?.points.isEmpty == true)
        let file = QuotaHistory(endpoint: "https://fixture.test", directory: directory).url
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = Data("not valid history".utf8)
        try original.write(to: file)
        let corrupt = QuotaHistoryRecorder(endpoint: "https://fixture.test", directory: directory)
        corrupt.record(account: account, quota: quota, now: now)
        corrupt.save()
        XCTAssertNotNil(corrupt.issue)
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testPlotDoesNotJoinGapsAndNearestReadingDoesNotInventValues() {
        let points = [QuotaHistoryPoint(date: now, usedPercent: 20),
            QuotaHistoryPoint(date: now.addingTimeInterval(300), usedPercent: 100),
            QuotaHistoryPoint(date: now.addingTimeInterval(600), usedPercent: 0),
            QuotaHistoryPoint(date: now.addingTimeInterval(7200), usedPercent: 10)]
        let plot = QuotaHistoryPlotPoint.plot(points, start: now, end: now.addingTimeInterval(7200))
        XCTAssertEqual(plot.map(\.segment), [0, 0, 0, 1])
        XCTAssertEqual(plot.map(\.point), points)
        XCTAssertNil(QuotaHistoryPlotPoint.nearest(now.addingTimeInterval(3600), in: points))
        XCTAssertEqual(QuotaHistoryPlotPoint.nearest(now.addingTimeInterval(310), in: points), points[1])
        XCTAssertTrue(QuotaHistoryPlotPoint.plot(points, start: now.addingTimeInterval(8000), end: now.addingTimeInterval(9000)).isEmpty)
    }

    func testLargePlotPreservesExtremesAndGapEdges() {
        let points: [QuotaHistoryPoint] = (0..<9000).map { index in
            let offset = Double(index * 300 + (index >= 4500 ? 3600 : 0))
            let percent: Double = index == 1234 ? 100 : index == 7000 ? 0 : 30
            return QuotaHistoryPoint(date: now.addingTimeInterval(offset), usedPercent: percent)
        }
        let plot = QuotaHistoryPlotPoint.plot(points, start: points.first!.date, end: points.last!.date)
        XCTAssertLessThan(plot.count, 600)
        for index in [0, 1234, 4499, 4500, 7000, 8999] { XCTAssertTrue(plot.contains { $0.point == points[index] }) }
        XCTAssertEqual(plot.first?.segment, 0)
        XCTAssertEqual(plot.last?.segment, 1)
    }

    func testCombinedChartKeepsWindowsAndGapSegmentsSeparate() throws {
        let session = QuotaHistorySeries(id: "session", title: "5 hours", points: [
            QuotaHistoryPoint(date: now, usedPercent: 20),
            QuotaHistoryPoint(date: now.addingTimeInterval(300), usedPercent: 40),
            QuotaHistoryPoint(date: now.addingTimeInterval(3600), usedPercent: 0)
        ])
        let weekly = QuotaHistorySeries(id: "weekly", title: "Weekly", points: [
            QuotaHistoryPoint(date: now, usedPercent: 65),
            QuotaHistoryPoint(date: now.addingTimeInterval(300), usedPercent: 66)
        ])
        let history = QuotaHistorySnapshot(series: [session, weekly])
        let series = QuotaHistoryChartSeries.project(history, start: now, end: now.addingTimeInterval(3600))
        XCTAssertEqual(series.map(\.id), ["session", "weekly"])
        XCTAssertEqual(series.map { $0.plot.map(\.point.usedPercent) }, [[20, 40, 0], [65, 66]])
        XCTAssertEqual(series[0].plot.map(\.segment), [0, 0, 1])
        XCTAssertEqual(series[0].isolatedDates, [now.addingTimeInterval(3600)])
        XCTAssertTrue(series[1].isolatedDates.isEmpty)
        let lineIDs = series.flatMap { window in Set(window.plot.map { window.lineID(segment: $0.segment) }) }
        XCTAssertEqual(Set(lineIDs).count, 3)
        XCTAssertEqual(series.map { $0.reading?.usedPercent }, [0, 66])
    }

    func testCombinedChartRetainsDistinctColorsWhenWindowsAreReordered() {
        let point = QuotaHistoryPoint(date: now, usedPercent: 40)
        let windows = ["weekly", "monthly", "session"].map {
            QuotaHistorySeries(id: $0, title: $0, points: [point])
        }
        let history = QuotaHistorySnapshot(series: windows)
        let combined = QuotaHistoryChartSeries.project(history, start: now, end: now)
        XCTAssertEqual(combined.map { $0.plot.map(\.point) }, [[point], [point], [point]])
        XCTAssertEqual(Set(combined.map(\.colorIndex)).count, 3)
        let reordered = QuotaHistoryChartSeries.project(QuotaHistorySnapshot(series: windows.reversed()), start: now, end: now)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: reordered.map { ($0.id, $0.colorIndex) }),
            Dictionary(uniqueKeysWithValues: combined.map { ($0.id, $0.colorIndex) }))
    }

    func testCombinedHoverUsesEachWindowsActualReadingWithoutFillingGaps() {
        let sessionPoint = QuotaHistoryPoint(date: now.addingTimeInterval(300), usedPercent: 80)
        let weeklyPoint = QuotaHistoryPoint(date: now.addingTimeInterval(600), usedPercent: 30)
        let history = QuotaHistorySnapshot(series: [
            QuotaHistorySeries(id: "session", title: "5 hours", points: [sessionPoint]),
            QuotaHistorySeries(id: "weekly", title: "Weekly", points: [weeklyPoint]),
            QuotaHistorySeries(id: "monthly", title: "Monthly", points: [QuotaHistoryPoint(date: now, usedPercent: 10)]),
            QuotaHistorySeries(id: "empty", title: "No history", points: [])
        ])
        let series = QuotaHistoryChartSeries.project(history, start: now, end: now.addingTimeInterval(7200),
            hoveredDate: now.addingTimeInterval(1000))
        XCTAssertEqual(series.map(\.reading), [sessionPoint, weeklyPoint, nil, nil])
        let gap = QuotaHistoryChartSeries.project(history, start: now, end: now.addingTimeInterval(7200),
            hoveredDate: now.addingTimeInterval(3600))
        XCTAssertTrue(gap.allSatisfy { $0.reading == nil })
    }

    @MainActor func testRecordingPreferenceIsIndependentFromTokenCollection() {
        let suite = "QuotaHistoryTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DisplayPreferences(defaults: defaults)
        XCTAssertTrue(preferences.recordsQuotaHistory)
        XCTAssertFalse(preferences.tracksProxyUsage)
        var changes = 0
        preferences.onQuotaHistoryChange = { changes += 1 }
        preferences.recordsQuotaHistory = false
        preferences.recordsQuotaHistory = false
        let restored = DisplayPreferences(defaults: defaults)
        XCTAssertFalse(restored.recordsQuotaHistory)
        XCTAssertFalse(restored.tracksProxyUsage)
        XCTAssertEqual(changes, 1)
    }

    @MainActor func testQuotaHoverWorksWithoutTokenCollectionAndExportsFictionalChart() throws {
        let observed = now.addingTimeInterval(86400)
        let points = (0...288).compactMap { index -> QuotaHistoryPoint? in
            if (110...135).contains(index) { return nil }
            return QuotaHistoryPoint(date: now.addingTimeInterval(Double(index * 300)), usedPercent: Double(index % 60) / 59 * 100)
        }
        let history = QuotaHistorySnapshot(series: [
            QuotaHistorySeries(id: "five-hour-session", title: "5 hours", points: points),
            QuotaHistorySeries(id: "seven-day-weekly", title: "Weekly", points: points.map {
                QuotaHistoryPoint(date: $0.date, usedPercent: 24 + $0.date.timeIntervalSince(now) / 86400 * 14)
            })
        ])
        var account = account()
        _ = reading(50, at: observed, account: &account)
        let providers = StatusBarMenuProviderSnapshot.grouping([account], refreshing: false, quotaHistory: { _ in history })
        XCTAssertNil(providers.first?.accounts.first?.proxyUsage)
        XCTAssertEqual(providers.first?.accounts.first?.quotaHistory, history)
        let commands = StatusBarCommandDispatcher(handlers: StatusBarCommandHandlers(refreshAll: {}, refreshProvider: { _ in }, refreshAccount: { _ in },
            toggleProxy: {}, toggleTunnel: { _ in }, copyText: { _ in }, switchAntigravityAccount: { _ in }, isAntigravityIDERunning: { false },
            confirmAntigravitySwitch: { _, _ in false }, selectProvider: { _ in }, settings: {}, openApp: {}, quit: {}, menuNeedsRebuild: {}))
        let snapshot = StatusBarMenuSnapshot(connectionMessage: "Fixture", isLocalProxyMode: true, proxyPort: 8317,
            isProxyRunning: true, tunnel: CloudflareTunnelSnapshot(), providers: providers, selectedProvider: nil,
            isLoadingQuotas: false, displaySettings: StatusBarMenuDisplaySettings(quotaDisplayMode: .used,
                quotaDisplayStyle: .lowestBar, hideSensitiveInfo: false, modelAggregationMode: .lowest),
            appearanceMode: .system, language: .english)
        for expanded in [false, true] {
            let menu = StatusBarMenuRenderer(snapshot: snapshot, commands: commands, expanded: expanded).buildMenu()
            let submenu = try XCTUnwrap(menu.items.first { $0.submenu is UsageSubmenu }?.submenu)
            let view = try XCTUnwrap(submenu.items.first?.view)
            XCTAssertEqual(view.frame.width, 520)
            XCTAssertLessThan(view.frame.height, 600)
        }
        let chart = QuotaHistoryDetailView(history: history, provider: .claude, now: observed, interactive: false).frame(width: 520)
        // Virtual Intel runners lack a working Metal chart renderer. Geometry
        // checks do not need a GPU; actual image exports remain opt-in below.
        let layout = NSHostingView(rootView: chart).intrinsicContentSize
        XCTAssertEqual(layout.width, 520)
        XCTAssertLessThan(layout.height, 420)
        if let path = ProcessInfo.processInfo.environment["CLIPROXYBAR_QUOTA_HISTORY_PREVIEW"] {
            for (suffix, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
                // Match the native menu's appearance in offscreen fixtures.
                let view = NSHostingView(rootView: chart.background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, scheme))
                view.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
                view.setFrameSize(view.intrinsicContentSize)
                view.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: path + "-" + suffix + ".png"))
            }
        }
    }
}
