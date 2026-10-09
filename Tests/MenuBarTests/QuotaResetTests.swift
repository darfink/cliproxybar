import AppKit
import SwiftUI
import XCTest
import CLIProxyBarCore
@testable import MenuBar

final class QuotaResetTests: XCTestCase {
    private let endpoint = "https://proxy.example.test"
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func account(_ provider: String = "claude") -> ProxyAccount {
        ProxyAccount(name: "private-account-file.json", provider: provider, email: "fixture@example.test",
            disabled: nil, unavailable: nil, quota: nil, model_quotas: nil)
    }
    private func quota(_ name: String = "five-hour-session", remaining: Double = 50,
                       at date: Date, reset: Date? = nil, plan: String? = nil) -> ProviderQuota {
        ProviderQuota(models: [QuotaMetric(name: name, percentage: remaining,
            resetTime: reset.map { ISO8601DateFormatter().string(from: $0) } ?? "")], lastUpdated: date, planType: plan)
    }
    private func read(_ monitor: inout QuotaResetMonitor, _ quota: ProviderQuota, provider: String = "claude") -> [QuotaResetEvent] {
        monitor.observe(account: account(provider), quota: quota, now: quota.lastUpdated)
    }

    func testFirstReadingAndEarlyDeadlineChangesDoNotNotify() {
        var monitor = QuotaResetMonitor(endpoint: endpoint)
        XCTAssertTrue(read(&monitor, quota(at: start, reset: start.addingTimeInterval(600))).isEmpty)
        XCTAssertTrue(read(&monitor, quota(remaining: 100, at: start.addingTimeInterval(60),
            reset: start.addingTimeInterval(18000))).isEmpty)
        XCTAssertTrue(read(&monitor, quota(remaining: 100, at: start.addingTimeInterval(120),
            reset: start.addingTimeInterval(18000))).isEmpty)
    }

    func testConfirmedTimedResetWorksEvenWhenNewAllowanceIsAlreadyPartlyUsed() {
        for (provider, name, kind) in [("claude", "five-hour-session", QuotaResetKind.short),
                                      ("codex", "codex-session", .short),
                                      ("opencode-go", "opencode-go-weekly", .long),
                                      ("opencode-go", "opencode-go-monthly", .long)] {
            var monitor = QuotaResetMonitor(endpoint: endpoint)
            _ = read(&monitor, quota(name, at: start, reset: start.addingTimeInterval(60)), provider: provider)
            let date = start.addingTimeInterval(90)
            let refreshed = quota(name, remaining: 80, at: date, reset: start.addingTimeInterval(604800))
            let events = read(&monitor, refreshed, provider: provider)
            XCTAssertEqual(events.count, 1)
            XCTAssertEqual(events.first?.kind, kind)
            XCTAssertEqual(events.first?.resetAt, start.addingTimeInterval(60))
            XCTAssertTrue(read(&monitor, refreshed, provider: provider).isEmpty)
            XCTAssertTrue(read(&monitor, quota(name, remaining: 70, at: date.addingTimeInterval(300),
                reset: start.addingTimeInterval(604800)), provider: provider).isEmpty)
        }
    }

    func testExpiredCountdownWithoutProviderConfirmationDoesNotNotify() {
        var monitor = QuotaResetMonitor(endpoint: endpoint)
        let deadline = start.addingTimeInterval(60)
        _ = read(&monitor, quota(at: start, reset: deadline))
        XCTAssertTrue(read(&monitor, quota(at: start.addingTimeInterval(90), reset: deadline)).isEmpty)
        XCTAssertTrue(read(&monitor, quota(remaining: 50, at: start.addingTimeInterval(120))).isEmpty)
    }

    func testProviderCanClearResetDateWhenItRestoresUnusedWindow() {
        var monitor = QuotaResetMonitor(endpoint: endpoint)
        _ = read(&monitor, quota(at: start, reset: start.addingTimeInterval(60)))
        XCTAssertEqual(read(&monitor, quota(remaining: 100, at: start.addingTimeInterval(90))).count, 1)
        XCTAssertTrue(read(&monitor, quota(remaining: 100, at: start.addingTimeInterval(120))).isEmpty)
    }

    func testProviderCanConfirmResetOnALaterPollWithoutLosingTheDeadline() {
        for delayedReset in [start.addingTimeInterval(60), nil] {
            var monitor = QuotaResetMonitor(endpoint: endpoint)
            _ = read(&monitor, quota(at: start, reset: start.addingTimeInterval(60)))
            XCTAssertTrue(read(&monitor, quota(at: start.addingTimeInterval(90), reset: delayedReset)).isEmpty)
            let events = read(&monitor, quota(remaining: 80, at: start.addingTimeInterval(390),
                reset: start.addingTimeInterval(18000)))
            XCTAssertEqual(events.count, 1)
            XCTAssertEqual(events.first?.resetAt, start.addingTimeInterval(60))
        }
    }

    func testRollingPartialRecoveryAndMovingDatesDoNotNotifyUntilFullRefill() {
        var monitor = QuotaResetMonitor(endpoint: endpoint)
        let name = "opencode-go-rolling"
        _ = read(&monitor, quota(name, remaining: 0, at: start, reset: start.addingTimeInterval(60)), provider: "opencode-go")
        XCTAssertTrue(read(&monitor, quota(name, remaining: 25, at: start.addingTimeInterval(90),
            reset: start.addingTimeInterval(180)), provider: "opencode-go").isEmpty)
        let date = start.addingTimeInterval(300)
        XCTAssertEqual(read(&monitor, quota(name, remaining: 100, at: date), provider: "opencode-go").count, 1)
        _ = read(&monitor, quota(name, remaining: 98, at: date.addingTimeInterval(60)), provider: "opencode-go")
        XCTAssertTrue(read(&monitor, quota(name, remaining: 100, at: date.addingTimeInterval(120)), provider: "opencode-go").isEmpty)
    }

    func testOldRollingReadingsAndPastWindowsDoNotCreateCatchUpAlerts() {
        var monitor = QuotaResetMonitor(endpoint: endpoint)
        _ = read(&monitor, quota("opencode-go-rolling", at: start), provider: "opencode-go")
        XCTAssertTrue(read(&monitor, quota("opencode-go-rolling", remaining: 100, at: start.addingTimeInterval(1800)),
            provider: "opencode-go").isEmpty)
        _ = read(&monitor, quota(at: start, reset: start.addingTimeInterval(60)))
        XCTAssertTrue(read(&monitor, quota(remaining: 100, at: start.addingTimeInterval(3600),
            reset: start.addingTimeInterval(18000))).isEmpty)
    }

    func testWeeklyResetCanBeConfirmedAfterSleepButNotDaysLater() {
        for (delay, expected) in [(3600.0, 1), (172800.0, 0)] {
            var monitor = QuotaResetMonitor(endpoint: endpoint)
            _ = read(&monitor, quota("seven-day-weekly", at: start, reset: start.addingTimeInterval(60)))
            let events = read(&monitor, quota("seven-day-weekly", at: start.addingTimeInterval(delay),
                reset: start.addingTimeInterval(604800)))
            XCTAssertEqual(events.count, expected)
        }
    }

    func testStaleOutOfOrderInvalidReadingsAndPlanChangesDoNotNotify() {
        var monitor = QuotaResetMonitor(endpoint: endpoint)
        let first = quota(at: start, reset: start.addingTimeInterval(60), plan: "Pro")
        _ = read(&monitor, first)
        let next = start.addingTimeInterval(90)
        let stale = quota(remaining: 100, at: start.addingTimeInterval(-1), reset: start.addingTimeInterval(18000), plan: "Pro")
        XCTAssertTrue(monitor.observe(account: account(), quota: stale, now: next).isEmpty)
        XCTAssertTrue(monitor.observe(account: account(), quota: first, now: start.addingTimeInterval(3600)).isEmpty)
        for value in [Double.nan, Double.infinity, -1, 101] {
            XCTAssertTrue(read(&monitor, quota(remaining: value, at: next, reset: start.addingTimeInterval(18000), plan: "Pro")).isEmpty)
        }
        XCTAssertTrue(read(&monitor, quota(remaining: 100, at: next, reset: start.addingTimeInterval(18000), plan: "Team")).isEmpty)
    }

    func testRelaunchDeduplicatesResetsAndStateContainsNoAccountNames() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var monitor = QuotaResetMonitor(endpoint: endpoint, directory: directory)
        _ = read(&monitor, quota(at: start, reset: start.addingTimeInterval(60)))
        try monitor.save()
        var reopened = QuotaResetMonitor(endpoint: endpoint, directory: directory)
        try reopened.load()
        let newWindow = start.addingTimeInterval(18000)
        XCTAssertEqual(read(&reopened, quota(at: start.addingTimeInterval(90), reset: newWindow)).count, 1)
        try reopened.save()
        var restored = QuotaResetMonitor(endpoint: endpoint, directory: directory)
        try restored.load()
        XCTAssertTrue(read(&restored, quota(at: start.addingTimeInterval(120), reset: newWindow)).isEmpty)
        let saved = try String(contentsOf: restored.url, encoding: .utf8)
        XCTAssertFalse(saved.contains("fixture@example.test"))
        XCTAssertFalse(saved.contains("private-account-file.json"))
        let other = QuotaResetMonitor(endpoint: "https://other.example.test", directory: directory)
        XCTAssertNotEqual(other.url, restored.url)
    }

    @MainActor
    func testResetSettingsAreOptInAndPersistIndependently() {
        let suite = "CLIProxyBarTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DisplayPreferences(defaults: defaults)
        XCTAssertFalse(preferences.notifiesShortResets)
        XCTAssertFalse(preferences.notifiesLongResets)
        XCTAssertFalse(preferences.celebratesLongResets)
        var changes = 0
        preferences.onResetAlertsChange = { changes += 1 }
        preferences.notifiesShortResets = true
        preferences.notifiesShortResets = true
        preferences.celebratesLongResets = true
        XCTAssertEqual(changes, 2)
        let restored = DisplayPreferences(defaults: defaults)
        XCTAssertTrue(restored.notifiesShortResets)
        XCTAssertFalse(restored.notifiesLongResets)
        XCTAssertTrue(restored.celebratesLongResets)
    }

    @MainActor
    func testConfettiPanelDoesNotTakeKeyboardFocusOrInterceptClicks() {
        let panel = ConfettiPresenter.makePanel(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        defer { panel.close() }
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.isOpaque)
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(panel.collectionBehavior.contains(.ignoresCycle))
    }

    @MainActor
    func testConfettiCanvasLeavesBackgroundTransparent() throws {
        try requireCanvasRenderer()
        let view = ConfettiCanvas(particles: ConfettiParticle.make(seed: 123), elapsed: 1.5)
            .frame(width: 800, height: 500)
        let renderer = ImageRenderer(content: view)
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
        XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)).alphaComponent, 0)
    }

    @MainActor
    func testConfettiVisualPreview() throws {
        guard let path = ProcessInfo.processInfo.environment["CLIPROXYBAR_CONFETTI_PREVIEW"] else { return }
        try requireCanvasRenderer()
        let view = ConfettiCanvas(particles: ConfettiParticle.make(seed: 123), elapsed: 1.5)
            .frame(width: 800, height: 500).background(Color(nsColor: NSColor(white: 0.12, alpha: 1)))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
    }

    private func requireCanvasRenderer() throws {
        #if arch(x86_64)
        guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] != "true" else {
            throw XCTSkip("GitHub's Intel VM cannot render the Metal-backed Canvas. This fixture runs on Apple Silicon CI and native desktops.")
        }
        #endif
    }
}
