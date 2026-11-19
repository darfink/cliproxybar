import AppKit
import SwiftUI
import XCTest
import CLIProxyBarCore
@testable import MenuBar

final class ProviderVisibilityTests: XCTestCase {
    private func account(_ provider: String, name: String = "fixture") -> ProxyAccount {
        ProxyAccount(name: name, provider: provider, email: nil, disabled: false,
            unavailable: false, quota: nil, model_quotas: nil)
    }

    @MainActor
    func testHiddenQuotaWindowsLeaveDisplayedReadingsAndPersist() throws {
        let suite = "ProviderVisibilityTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DisplayPreferences(defaults: defaults)
        var claude = account("claude")
        claude.recordQuota(ProviderQuota(models: [
            QuotaMetric(name: "five-hour-session", percentage: 90, resetTime: ""),
            QuotaMetric(name: "seven-day-weekly", percentage: 80, resetTime: ""),
            QuotaMetric(name: "seven-day-fable", percentage: 10, resetTime: "")
        ], lastUpdated: Date()))
        var antigravity = account("antigravity", name: "second")
        antigravity.recordQuota(ProviderQuota(models: [
            QuotaMetric(name: "antigravity-gemini-session", percentage: 70, resetTime: ""),
            QuotaMetric(name: "antigravity-claude-gpt-session", percentage: 5, resetTime: ""),
            QuotaMetric(name: "antigravity-claude-gpt-weekly", percentage: 5, resetTime: "")
        ], lastUpdated: Date()))
        preferences.updateAvailableProviders([claude, antigravity])
        XCTAssertEqual(preferences.availableQuotaWindows, [.claudeFable, .antigravityClaudeGPT])
        XCTAssertEqual(preferences.displayed(claude).providerQuota().models.count, 3)

        var changes = 0
        preferences.onChange = { changes += 1 }
        preferences.setQuotaWindowVisible(false, for: .claudeFable)
        preferences.setQuotaWindowVisible(false, for: .antigravityClaudeGPT)
        preferences.setQuotaWindowVisible(false, for: .antigravityClaudeGPT)
        XCTAssertEqual(changes, 2)
        let shownClaude = preferences.displayed(claude)
        XCTAssertEqual(shownClaude.providerQuota().models.map(\.name), ["five-hour-session", "seven-day-weekly"])
        XCTAssertEqual(shownClaude.quotaReadState, claude.quotaReadState)
        // A hidden Fable window no longer drives the weekly menu bar figure.
        XCTAssertEqual(MenuBarQuotaPair.resolve(for: .claude, from: shownClaude.providerQuota().models)?.bottom.remainingPercentage, 80)
        XCTAssertEqual(preferences.displayed(antigravity).providerQuota().models.map(\.name), ["antigravity-gemini-session"])
        // The source readings stay complete for recording and alerts.
        XCTAssertEqual(claude.providerQuota().models.count, 3)
        // Hidden windows stay offered so they can be shown again.
        preferences.updateAvailableProviders([claude, antigravity])
        XCTAssertEqual(preferences.availableQuotaWindows, [.claudeFable, .antigravityClaudeGPT])

        // A hidden window stays listed even while no account reports it.
        preferences.updateAvailableProviders([account("claude")])
        XCTAssertEqual(preferences.availableQuotaWindows, [.claudeFable, .antigravityClaudeGPT])

        let reopened = DisplayPreferences(defaults: defaults)
        XCTAssertFalse(reopened.showsQuotaWindow(.claudeFable))
        XCTAssertFalse(reopened.showsQuotaWindow(.antigravityClaudeGPT))
        XCTAssertTrue(reopened.showsQuotaWindow(.claudeOpus))
    }

    @MainActor
    func testDropdownFiltersEveryAccountWithoutChangingMenuBarChoicesOrSourceData() throws {
        let suite = "ProviderVisibilityTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DisplayPreferences(defaults: defaults)
        let plugin = try XCTUnwrap(QuotaProvider(rawValue: "fixture-plugin"))
        var pluginAccount = account(plugin.rawValue)
        pluginAccount.providerDisplayName = "Fixture Plugin"
        let accounts = [account("gemini"), account("gemini-cli", name: "second"),
            account("claude"), pluginAccount]
        preferences.updateAvailableProviders(accounts)
        XCTAssertEqual(preferences.providerName(plugin), "Fixture Plugin")
        preferences.setDropdownVisible(false, for: .gemini)
        preferences.setMenuBarVisible(false, for: plugin)
        var usageLookups: [String] = []
        let groups = StatusBarMenuProviderSnapshot.grouping(accounts, refreshing: true,
            isVisible: preferences.showsInDropdown) {
                usageLookups.append($0.provider)
                return nil
            }
        XCTAssertEqual(Set(groups.map(\.provider)), [.claude, plugin])
        XCTAssertEqual(Set(usageLookups), ["claude", "fixture-plugin"])
        XCTAssertTrue(groups.allSatisfy(\.isRefreshing))
        XCTAssertTrue(preferences.showsInMenuBar(.gemini))
        XCTAssertTrue(preferences.showsInDropdown(plugin))
        XCTAssertEqual(accounts.count, 4)
        XCTAssertEqual(StatusBarMenuProviderSnapshot.grouping(accounts, refreshing: false).count, 3)

        preferences.setDropdownVisible(false, for: plugin)
        preferences.updateAvailableProviders([])
        preferences.updateAvailableProviders(accounts)
        let restored = DisplayPreferences(defaults: defaults)
        XCTAssertFalse(restored.showsInDropdown(plugin))
        XCTAssertFalse(restored.showsInMenuBar(plugin))
        XCTAssertFalse(restored.showsInDropdown(.gemini))
    }

    @MainActor
    func testAllHiddenMenusKeepSettingsShortcutAndFooterAccessible() throws {
        let snapshot = StatusBarMenuSnapshot(connectionMessage: "Fixture", isLocalProxyMode: true, proxyPort: 8317,
            isProxyRunning: true, tunnel: CloudflareTunnelSnapshot(), providers: [], selectedProvider: .gemini,
            isLoadingQuotas: false, displaySettings: StatusBarMenuDisplaySettings(quotaDisplayMode: .used,
                quotaDisplayStyle: .lowestBar, hideSensitiveInfo: false, modelAggregationMode: .lowest),
            appearanceMode: .system, language: .english, hiddenProviderCount: 2)
        var openedSettings = 0
        let commands = StatusBarCommandDispatcher(handlers: StatusBarCommandHandlers(
            refreshAll: {}, refreshProvider: { _ in }, refreshAccount: { _ in },
            toggleProxy: {}, toggleTunnel: { _ in }, copyText: { _ in },
            switchAntigravityAccount: { _ in }, isAntigravityIDERunning: { false },
            confirmAntigravitySwitch: { _, _ in false }, selectProvider: { _ in },
            settings: { openedSettings += 1 }, openApp: {}, quit: {}, menuNeedsRebuild: {}))
        for expanded in [false, true] {
            let menu = StatusBarMenuRenderer(snapshot: snapshot, commands: commands, expanded: expanded).buildMenu()
            let settings = try XCTUnwrap(menu.items.first { $0.keyEquivalent == "," })
            XCTAssertEqual(settings.keyEquivalentModifierMask, .command)
            XCTAssertTrue(settings.allowsKeyEquivalentWhenHidden)
            XCTAssertTrue(settings.target === commands)
            commands.perform(try XCTUnwrap(settings.action))
            XCTAssertEqual(menu.items.filter { $0.view != nil && !$0.isHidden }.count, 2)
        }
        XCTAssertEqual(openedSettings, 2)
    }

    @MainActor
    func testVisibilitySettingsFitWindowAndCanRenderFixturePreview() throws {
        let suite = "ProviderVisibilityTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DisplayPreferences(defaults: defaults)
        var plugin = account("fixture-plugin")
        plugin.providerDisplayName = "An Example Plugin With A Long Provider Name"
        preferences.updateAvailableProviders([account("gemini"), plugin])
        preferences.setDropdownVisible(false, for: .gemini)
        preferences.setMenuBarVisible(false, for: .antigravity)
        let view = ProviderVisibilitySettingsView(preferences: preferences)
            .padding(20).frame(width: 440)
            .background(Color(nsColor: .windowBackgroundColor))
        let hosting = NSHostingView(rootView: view)
        hosting.setFrameSize(hosting.intrinsicContentSize)
        XCTAssertEqual(hosting.frame.width, 440)
        XCTAssertGreaterThan(hosting.frame.height, 180)
        XCTAssertLessThan(hosting.frame.height, 400)

        // Export only mock providers and isolated preferences, without opening a window.
        if let path = ProcessInfo.processInfo.environment["CLIPROXYBAR_PROVIDER_PREVIEW"] {
            for (suffix, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
                // ImageRenderer cannot render AppKit's native checkbox controls.
                let preview = NSHostingView(rootView: view.environment(\.colorScheme, scheme))
                preview.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
                preview.setFrameSize(preview.intrinsicContentSize)
                preview.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(preview.bitmapImageRepForCachingDisplay(in: preview.bounds))
                preview.cacheDisplay(in: preview.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: path + "-" + suffix + ".png"))
            }
        }
    }
}
