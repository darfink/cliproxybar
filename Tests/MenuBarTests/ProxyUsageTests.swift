import AppKit
import SwiftUI
import XCTest
import CLIProxyBarCore
@testable import MenuBar

final class ProxyUsageTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1791547200)
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    func event(provider: String = "codex", index: String = "private-auth-index", execution: String = "execution-1",
               date: Date? = nil, tokens: [String: Int64] = ["input_tokens": 100, "output_tokens": 40, "cached_tokens": 60, "reasoning_tokens": 20, "total_tokens": 140],
               failed: Bool = false, extra: [String: Any] = [:]) throws -> ProxyUsageEvent {
        var json: [String: Any] = ["provider": provider, "auth_index": index, "execution_id": execution, "request_id": "same-trace",
            "model": "test-model", "timestamp": ISO8601DateFormatter().string(from: date ?? now), "tokens": tokens, "failed": failed,
            "api_key": "secret-client-key", "response_headers": ["authorization": "sensitive-header"], "fail": ["body": "sensitive-response"]]
        json.merge(extra) { _, new in new }
        return try JSONDecoder().decode(ProxyUsageEvent.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func account(provider: String = "codex", index: String = "private-auth-index") -> ProxyAccount {
        var value = ProxyAccount(name: "fixture", provider: provider, email: "example@example.com", disabled: nil, unavailable: nil, quota: nil, model_quotas: nil)
        value.auth_index = index
        value.success = 50
        value.failed = 2
        return value
    }

    func testTokenSubsetsAreNotAddedToReportedTotal() throws {
        let value = try event()
        XCTAssertEqual(value.tokens.total, 140)
        XCTAssertEqual(value.tokens.input, 100)
        XCTAssertEqual(value.tokens.cached, 60)
        XCTAssertEqual(value.tokens.reasoning, 20)
        let claude = try event(provider: "claude", tokens: ["input_tokens": 100, "cache_read_tokens": 60, "cache_creation_tokens": 10, "output_tokens": 40, "total_tokens": 210])
        XCTAssertEqual(claude.tokens.input, 170)
        XCTAssertEqual(claude.tokens.total, 210)
    }

    func testCanonicalTokenBreakdownTakesPriority() throws {
        let value = try event(extra: ["token_breakdown": ["schema_version": 2, "total_tokens": 250,
            "input": ["total_tokens": 200, "cache_read_tokens": 80, "cache_write_tokens": 20],
            "output": ["total_tokens": 50, "reasoning_tokens": 25]]])
        XCTAssertEqual(value.tokens.total, 250)
        XCTAssertEqual(value.tokens.input, 200)
        XCTAssertEqual(value.tokens.cached, 80)
        XCTAssertEqual(value.tokens.cacheWrite, 20)
    }

    func testHistoryDeduplicatesAcrossRelaunchAndKeepsAccountsSeparate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var history = ProxyUsageHistory(endpoint: "http://localhost:8317", directory: directory)
        history.start(at: now)
        let first = try event()
        history.ingest([first, first, try event(provider: "claude"), try event(index: "other-account")], now: now, calendar: calendar)
        try history.save()
        var restored = ProxyUsageHistory(endpoint: "http://localhost:8317", directory: directory)
        try restored.load()
        restored.ingest([first, try event(execution: "execution-2", failed: true)], now: now, calendar: calendar)
        let snapshot = restored.snapshot(for: account(), trackingEnabled: true, issue: nil, lastCollectedAt: now)
        XCTAssertEqual(snapshot.days.count, 1)
        XCTAssertEqual(snapshot.days[0].requests, 2)
        XCTAssertEqual(snapshot.days[0].failures, 1)
        XCTAssertEqual(snapshot.days[0].tokens.total, 280)
        XCTAssertEqual(restored.snapshot(for: account(provider: "claude"), trackingEnabled: true, issue: nil, lastCollectedAt: now).days[0].requests, 1)
        XCTAssertTrue(restored.snapshot(for: account(index: "missing-account"), trackingEnabled: true, issue: nil, lastCollectedAt: now).days.isEmpty)
        let raw = try String(contentsOf: history.url, encoding: .utf8)
        for secret in ["private-auth-index", "secret-client-key", "sensitive-header", "sensitive-response", "example@example.com", "execution-1"] {
            XCTAssertFalse(raw.contains(secret))
        }
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: history.url.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        var otherEndpoint = ProxyUsageHistory(endpoint: "http://localhost:9999", directory: directory)
        try otherEndpoint.load()
        XCTAssertTrue(otherEndpoint.snapshot(for: account(), trackingEnabled: true, issue: nil, lastCollectedAt: now).days.isEmpty)
    }

    func testDatesRetentionAndInvalidAccounts() throws {
        var history = ProxyUsageHistory(endpoint: "http://localhost:8317")
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let expired = calendar.date(byAdding: .day, value: -367, to: now)!
        history.start(at: now)
        history.ingest([try event(date: yesterday), try event(execution: "today"), try event(execution: "expired", date: expired),
            try event(execution: "future", date: now.addingTimeInterval(600)), try event(index: "")], now: now, calendar: calendar)
        let snapshot = history.snapshot(for: account(), trackingEnabled: true, issue: nil, lastCollectedAt: now)
        XCTAssertEqual(snapshot.days.count, 2)
        XCTAssertEqual(snapshot.totals(since: calendar.startOfDay(for: now)).total, 140)
        XCTAssertEqual(snapshot.totals(since: calendar.startOfDay(for: yesterday)).total, 280)
    }

    @MainActor
    func testTrackingIsOptInAndPersists() {
        let suite = "CLIProxyBarTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DisplayPreferences(defaults: defaults)
        XCTAssertFalse(preferences.tracksProxyUsage)
        var changes = 0
        preferences.onUsageTrackingChange = { changes += 1 }
        preferences.tracksProxyUsage = true
        preferences.tracksProxyUsage = true
        XCTAssertEqual(changes, 1)
        XCTAssertTrue(DisplayPreferences(defaults: defaults).tracksProxyUsage)
    }

    @MainActor
    func testAccountUsageBelongsToNativeMenuHierarchyInBothViews() throws {
        var history = ProxyUsageHistory(endpoint: "http://localhost:8317")
        history.start(at: now)
        history.ingest([try event()], now: now, calendar: calendar)
        let usage = history.snapshot(for: account(), trackingEnabled: true, issue: nil, lastCollectedAt: now)
        let snapshot = StatusBarMenuSnapshot(connectionMessage: "Connected", isLocalProxyMode: true, proxyPort: 8317, isProxyRunning: true,
            tunnel: CloudflareTunnelSnapshot(), providers: [StatusBarMenuProviderSnapshot(provider: .codex,
                accounts: [StatusBarMenuAccountSnapshot(id: QuotaAccountID(provider: .codex, accountKey: "fixture"), email: "example@example.com",
                    quota: ProviderQuota(models: [QuotaMetric(name: "codex-weekly", percentage: 50, resetTime: "")]), subscription: nil,
                    isActiveInIDE: false, isRefreshing: false, isRefreshBlocked: false, proxyUsage: usage)], isRefreshing: false, supportsScopedRefresh: true)],
            selectedProvider: nil, isLoadingQuotas: false,
            displaySettings: StatusBarMenuDisplaySettings(quotaDisplayMode: .used, quotaDisplayStyle: .lowestBar, hideSensitiveInfo: false, modelAggregationMode: .lowest),
            appearanceMode: .system, language: .english)
        let commands = StatusBarCommandDispatcher(handlers: StatusBarCommandHandlers(refreshAll: {}, refreshProvider: { _ in }, refreshAccount: { _ in },
            toggleProxy: {}, toggleTunnel: { _ in }, copyText: { _ in }, switchAntigravityAccount: { _ in }, isAntigravityIDERunning: { false },
            confirmAntigravitySwitch: { _, _ in false }, selectProvider: { _ in }, settings: {}, openApp: {}, quit: {}, menuNeedsRebuild: {}))
        for expanded in [false, true] {
            let renderer = StatusBarMenuRenderer(snapshot: snapshot, commands: commands, expanded: expanded)
            let menu = renderer.buildMenu()
            let anchor = try XCTUnwrap(menu.items.first { $0.submenu is UsageSubmenu })
            let submenu = try XCTUnwrap(anchor.submenu as? UsageSubmenu)
            XCTAssertTrue(submenu.supermenu === menu)
            XCTAssertTrue(submenu.anchorItem === anchor)
            XCTAssertTrue(submenu.delegate === submenu)
            XCTAssertNil(submenu.items.first?.action)
            let content = try XCTUnwrap(submenu.items.first?.view)
            XCTAssertEqual(content.frame.width, 520)

            // Refresh moves the submenu to an existing account item.
            let existing = NSMenuItem()
            anchor.submenu = nil
            existing.submenu = submenu
            renderer.transferFilterScope(from: anchor, to: existing)
            XCTAssertTrue(submenu.anchorItem === existing)
            let view = NSHostingView(rootView: ProxyUsageDetailView(usage: usage, provider: .codex, accountName: "example@example.com").frame(width: 520))
            view.setFrameSize(view.intrinsicContentSize)
            XCTAssertEqual(view.frame.width, 520)
            XCTAssertGreaterThan(view.frame.height, 250)
            XCTAssertLessThan(view.frame.height, 600)
        }
        // Optional developer preview uses fixture data only, never live identities.
        if let path = ProcessInfo.processInfo.environment["CLIPROXYBAR_USAGE_PREVIEW"] {
            let renderer = ImageRenderer(content: ProxyUsageDetailView(usage: usage, provider: .codex, accountName: "example@example.com", interactive: false)
                .frame(width: 520).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .dark))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.cgImage)
            let bitmap = NSBitmapImageRep(cgImage: image)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
        }
    }
}
