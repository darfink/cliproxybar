import Foundation
import CLIProxyBarCore

/// Persists display values only, never auth indices, tokens, or raw API responses.
struct QuotaCache {
    struct Entry: Codable {
        let name: String
        let provider: String
        let email: String?
        let quota: ProviderQuota
        var providerDisplayName: String? = nil
        var disabled: Bool? = nil
        var quotaState: QuotaReadState? = nil
    }
    struct Envelope: Codable {
        let endpoint: String
        let entries: [Entry]
    }
    let url: URL
    let legacyURL: URL?
    let endpoint: String
    init(endpoint: String, directory: URL? = nil, legacyURL: URL? = nil) {
        self.endpoint = endpoint
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let root = directory ?? support.appendingPathComponent("CLIProxyBar")
        url = root.appendingPathComponent("quota-cache.json")
        self.legacyURL = legacyURL ?? (directory == nil ? support.appendingPathComponent("QuotioMenuBar/quota-cache.json") : nil)
    }
    func load() throws -> [ProxyAccount] {
        let source = FileManager.default.fileExists(atPath: url.path) ? url : legacyURL
        guard let source, FileManager.default.fileExists(atPath: source.path) else { return [] }
        let saved = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: source))
        guard saved.endpoint == endpoint else { return [] }
        return saved.entries.map { entry in
            var account = ProxyAccount(name: entry.name, provider: entry.provider, email: entry.email, disabled: entry.disabled, unavailable: nil, quota: nil, model_quotas: nil)
            account.fetchedQuota = entry.quota
            account.providerDisplayName = entry.providerDisplayName
            account.quotaState = entry.quotaState == .unsupported ? .unsupported : .cached
            account.quotaIssue = "Saved reading · refreshing…"
            return account
        }
    }
    func save(_ accounts: [ProxyAccount]) throws {
        let entries = accounts.compactMap { account -> Entry? in
            var quota = account.providerQuota()
            quota.accountDisplayName = account.displayName
            return Entry(name: account.name, provider: account.provider, email: account.email, quota: quota,
                providerDisplayName: account.providerDisplayName, disabled: account.disabled, quotaState: account.quotaReadState)
        }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(Envelope(endpoint: endpoint, entries: entries))
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func merging(_ fresh: [ProxyAccount], previous: [ProxyAccount]) -> [ProxyAccount] {
        fresh.map { new in
            var account = new
            if let prior = previous.first(where: { $0.name == new.name && $0.provider == new.provider }) {
                let priorQuota = prior.providerQuota()
                let freshQuota = new.providerQuota()
                if new.fetchedQuota == nil, prior.fetchedQuota != nil || priorQuota.hasDisplayData,
                   !freshQuota.hasDisplayData || priorQuota.lastUpdated > freshQuota.lastUpdated {
                    account.fetchedQuota = priorQuota
                }
                account.quotaIssue = prior.quotaIssue
                account.quotaState = prior.quotaState
                account.providerDisplayName = prior.providerDisplayName
            }
            return account
        }
    }
}
