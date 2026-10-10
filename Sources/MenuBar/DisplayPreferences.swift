import Foundation
import Observation
import CLIProxyBarCore

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
    @ObservationIgnored var onResetAlertsChange: (() -> Void)?
    private(set) var endpoint: String
    private(set) var hiddenMenuBarProviders: Set<String>
    private(set) var availableProviders: [QuotaProvider] = QuotaProvider.allCases.filter { ActiveQuotaParser.supports($0.rawValue) }
    private(set) var providerNames: [QuotaProvider: String] = [:]

    func updateAvailableProviders(_ accounts: [ProxyAccount]) {
        providerNames = Dictionary(accounts.compactMap { account -> (QuotaProvider, String)? in
            guard let provider = QuotaProvider(rawValue: account.provider), let name = account.providerDisplayName else { return nil }
            return (provider, name)
        }, uniquingKeysWith: { first, _ in first })
        let configured = accounts.compactMap { QuotaProvider(rawValue: $0.provider) }
        let builtIn = QuotaProvider.allCases.filter { ActiveQuotaParser.supports($0.rawValue) }
        availableProviders = Set(configured + builtIn).sorted { providerName($0) < providerName($1) }
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
    var tracksProxyUsage: Bool {
        didSet {
            guard oldValue != tracksProxyUsage else { return }
            defaults.set(tracksProxyUsage, forKey: "tracksProxyUsage")
            onUsageTrackingChange?()
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
        endpoint = defaults.string(forKey: "endpoint") ?? "http://127.0.0.1:8317"
        mode = defaults.string(forKey: "quotaDisplayMode").flatMap(QuotaDisplayMode.init(rawValue:)) ?? .used
        tracksProxyUsage = defaults.bool(forKey: "tracksProxyUsage")
        notifiesShortResets = defaults.bool(forKey: "notifiesShortResets")
        notifiesLongResets = defaults.bool(forKey: "notifiesLongResets")
        celebratesLongResets = defaults.bool(forKey: "celebratesLongResets")
    }
}
