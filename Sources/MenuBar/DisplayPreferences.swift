import Foundation
import Observation
import CLIProxyBarCore

enum MenuViewMode: String {
    case compact
    case expanded
}

@MainActor
@Observable
final class DisplayPreferences {
    /// Import only display preferences, never credentials or unrelated upstream settings.
    static func migrateLegacyDefaults(_ defaults: UserDefaults = .standard, legacy: [String: Any]? = nil) {
        guard !defaults.bool(forKey: "brandMigrationV1") else { return }
        let saved = legacy ?? defaults.persistentDomain(forName: "local.QuotioMenuBar") ?? [:]
        for key in ["endpoint", "quotaDisplayMode", "hiddenMenuBarProviders"] where defaults.object(forKey: key) == nil {
            if let value = saved[key] { defaults.set(value, forKey: key) }
        }
        defaults.set(true, forKey: "brandMigrationV1")
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var onEndpointChange: (() -> Void)?
    @ObservationIgnored var onUsageTrackingChange: (() -> Void)?
    @ObservationIgnored var onQuotaHistoryChange: (() -> Void)?
    @ObservationIgnored var onResetAlertsChange: (() -> Void)?
    private(set) var endpoint: String
    private(set) var hiddenMenuBarProviders: Set<String>
    private(set) var hiddenDropdownProviders: Set<String>
    private(set) var availableProviders: [QuotaProvider] = QuotaProvider.allCases.filter { ActiveQuotaParser.supports($0.rawValue) }
    private(set) var providerNames: [QuotaProvider: String] = [:]
    private(set) var hiddenQuotaWindows: Set<String>
    /// Optional windows reported by at least one account, offered in Settings.
    private(set) var availableQuotaWindows: [OptionalQuotaWindow] = []

    func updateAvailableProviders(_ accounts: [ProxyAccount]) {
        providerNames = Dictionary(accounts.compactMap { account -> (QuotaProvider, String)? in
            guard let provider = QuotaProvider(rawValue: account.provider), let name = account.providerDisplayName else { return nil }
            return (provider, name)
        }, uniquingKeysWith: { first, _ in first })
        let configured = accounts.compactMap { QuotaProvider(rawValue: $0.provider) }
        let builtIn = QuotaProvider.allCases.filter { ActiveQuotaParser.supports($0.rawValue) }
        availableProviders = Set(configured + builtIn).sorted { providerName($0) < providerName($1) }
        let reported = Set(accounts.flatMap { $0.providerQuota().models.map(\.name) })
        // Keep hidden windows listed so they can always be shown again.
        availableQuotaWindows = OptionalQuotaWindow.allCases.filter { !reported.isDisjoint(with: $0.metricNames) || !showsQuotaWindow($0) }
    }

    func showsQuotaWindow(_ window: OptionalQuotaWindow) -> Bool {
        !hiddenQuotaWindows.contains(window.rawValue)
    }

    func setQuotaWindowVisible(_ visible: Bool, for window: OptionalQuotaWindow) {
        guard visible != showsQuotaWindow(window) else { return }
        if visible { hiddenQuotaWindows.remove(window.rawValue) }
        else { hiddenQuotaWindows.insert(window.rawValue) }
        defaults.set(hiddenQuotaWindows.sorted(), forKey: "hiddenQuotaWindows")
        onChange?()
    }

    /// Removes hidden windows from what the menu bar, drop-down, and history show.
    /// Quota recording and reset alerts keep using the full readings.
    func displayed(_ account: ProxyAccount) -> ProxyAccount {
        let hidden = Set(OptionalQuotaWindow.allCases.filter { !showsQuotaWindow($0) }.flatMap(\.metricNames))
        guard !hidden.isEmpty, var quota = account.fetchedQuota, quota.models.contains(where: { hidden.contains($0.name) }) else { return account }
        quota.models.removeAll { hidden.contains($0.name) }
        var result = account
        result.fetchedQuota = quota
        return result
    }

    func providerName(_ provider: QuotaProvider) -> String { providerNames[provider] ?? provider.displayName }

    func showsInMenuBar(_ provider: QuotaProvider) -> Bool {
        !hiddenMenuBarProviders.contains(provider.rawValue)
    }

    func setMenuBarVisible(_ visible: Bool, for provider: QuotaProvider) {
        guard visible != showsInMenuBar(provider) else { return }
        if visible { hiddenMenuBarProviders.remove(provider.rawValue) }
        else { hiddenMenuBarProviders.insert(provider.rawValue) }
        defaults.set(hiddenMenuBarProviders.sorted(), forKey: "hiddenMenuBarProviders")
        onChange?()
    }

    func showsInDropdown(_ provider: QuotaProvider) -> Bool {
        !hiddenDropdownProviders.contains(provider.rawValue)
    }

    func setDropdownVisible(_ visible: Bool, for provider: QuotaProvider) {
        guard visible != showsInDropdown(provider) else { return }
        if visible { hiddenDropdownProviders.remove(provider.rawValue) }
        else { hiddenDropdownProviders.insert(provider.rawValue) }
        defaults.set(hiddenDropdownProviders.sorted(), forKey: "hiddenDropdownProviders")
        onChange?()
    }

    func saveEndpoint(_ input: String) throws {
        let client = try LocalProxyClient(endpoint: input.trimmingCharacters(in: .whitespacesAndNewlines))
        let value = client.baseURL.absoluteString
        guard value != endpoint else { return }
        endpoint = value
        defaults.set(value, forKey: "endpoint")
        onEndpointChange?()
    }

    var mode: QuotaDisplayMode {
        didSet {
            defaults.set(mode.rawValue, forKey: "quotaDisplayMode")
            onChange?()
        }
    }
    var showsBothMenuBarQuotas: Bool {
        didSet {
            guard oldValue != showsBothMenuBarQuotas else { return }
            defaults.set(showsBothMenuBarQuotas, forKey: "showsBothMenuBarQuotas")
            onChange?()
        }
    }
    var defaultMenuView: MenuViewMode {
        didSet {
            guard oldValue != defaultMenuView else { return }
            defaults.set(defaultMenuView.rawValue, forKey: "defaultMenuView")
            onChange?()
        }
    }
    var showsResetCountdownInMenuBar: Bool {
        didSet {
            guard oldValue != showsResetCountdownInMenuBar else { return }
            defaults.set(showsResetCountdownInMenuBar, forKey: "showsResetCountdownInMenuBar")
            onChange?()
        }
    }
    var showsResetCountdownInCompactMenu: Bool {
        didSet {
            guard oldValue != showsResetCountdownInCompactMenu else { return }
            defaults.set(showsResetCountdownInCompactMenu, forKey: "showsResetCountdownInCompactMenu")
            onChange?()
        }
    }
    var tracksProxyUsage: Bool {
        didSet {
            guard oldValue != tracksProxyUsage else { return }
            defaults.set(tracksProxyUsage, forKey: "tracksProxyUsage")
            onUsageTrackingChange?()
        }
    }
    var recordsQuotaHistory: Bool {
        didSet {
            guard oldValue != recordsQuotaHistory else { return }
            defaults.set(recordsQuotaHistory, forKey: "recordsQuotaHistory")
            onQuotaHistoryChange?()
        }
    }
    var notifiesShortResets: Bool {
        didSet {
            guard oldValue != notifiesShortResets else { return }
            defaults.set(notifiesShortResets, forKey: "notifiesShortResets")
            onResetAlertsChange?()
        }
    }
    var notifiesLongResets: Bool {
        didSet {
            guard oldValue != notifiesLongResets else { return }
            defaults.set(notifiesLongResets, forKey: "notifiesLongResets")
            onResetAlertsChange?()
        }
    }
    var celebratesLongResets: Bool {
        didSet {
            guard oldValue != celebratesLongResets else { return }
            defaults.set(celebratesLongResets, forKey: "celebratesLongResets")
            onResetAlertsChange?()
        }
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hiddenMenuBarProviders = Set(defaults.stringArray(forKey: "hiddenMenuBarProviders") ?? [])
        hiddenDropdownProviders = Set(defaults.stringArray(forKey: "hiddenDropdownProviders") ?? [])
        hiddenQuotaWindows = Set(defaults.stringArray(forKey: "hiddenQuotaWindows") ?? [])
        endpoint = defaults.string(forKey: "endpoint") ?? "http://127.0.0.1:8317"
        mode = defaults.string(forKey: "quotaDisplayMode").flatMap(QuotaDisplayMode.init(rawValue:)) ?? .used
        showsBothMenuBarQuotas = defaults.object(forKey: "showsBothMenuBarQuotas") == nil
            ? true : defaults.bool(forKey: "showsBothMenuBarQuotas")
        defaultMenuView = defaults.string(forKey: "defaultMenuView").flatMap(MenuViewMode.init(rawValue:)) ?? .compact
        showsResetCountdownInMenuBar = defaults.bool(forKey: "showsResetCountdownInMenuBar")
        showsResetCountdownInCompactMenu = defaults.bool(forKey: "showsResetCountdownInCompactMenu")
        tracksProxyUsage = defaults.bool(forKey: "tracksProxyUsage")
        recordsQuotaHistory = defaults.object(forKey: "recordsQuotaHistory") == nil ? true : defaults.bool(forKey: "recordsQuotaHistory")
        notifiesShortResets = defaults.bool(forKey: "notifiesShortResets")
        notifiesLongResets = defaults.bool(forKey: "notifiesLongResets")
        celebratesLongResets = defaults.bool(forKey: "celebratesLongResets")
    }
}

/// Quota windows that some people never use. Each can be hidden from the app's views.
enum OptionalQuotaWindow: String, CaseIterable, Identifiable {
    case claudeFable, claudeSonnet, claudeOpus, antigravityClaudeGPT

    var id: String { rawValue }

    var provider: QuotaProvider {
        self == .antigravityClaudeGPT ? .antigravity : .claude
    }

    var title: String {
        switch self {
        case .claudeFable: "Fable weekly"
        case .claudeSonnet: "Sonnet weekly"
        case .claudeOpus: "Opus weekly"
        case .antigravityClaudeGPT: "Claude & GPT"
        }
    }

    var metricNames: Set<String> {
        switch self {
        case .claudeFable: ["seven-day-fable"]
        case .claudeSonnet: ["seven-day-sonnet"]
        case .claudeOpus: ["seven-day-opus"]
        case .antigravityClaudeGPT: ["antigravity-claude-gpt-session", "antigravity-claude-gpt-weekly"]
        }
    }
}
