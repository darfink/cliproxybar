import Foundation
import CLIProxyBarCore

enum ClaudePlanParser {
    private struct Profile: Decodable {
        struct Account: Decodable {
            let has_claude_pro: Bool?
            let has_claude_max: Bool?
        }
        struct Organization: Decodable {
            let organization_type: String?
            let rate_limit_tier: String?
        }
        let account: Account?
        let organization: Organization?
    }

    static func request(for account: ProxyAccount) throws -> ProxyAPICall {
        guard account.provider == "claude" else { throw LocalClientError.noQuotaData }
        guard let index = account.auth_index, !index.isEmpty else { throw LocalClientError.missingAuthIndex }
        return ProxyAPICall(authIndex: index, method: "GET", url: "https://api.anthropic.com/api/oauth/profile",
            header: ["Authorization": "Bearer $TOKEN$", "Accept": "application/json", "anthropic-beta": "oauth-2025-04-20"], data: nil)
    }

    static func parse(_ data: Data) throws -> String? {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], root["error"] == nil else {
            throw LocalClientError.noQuotaData
        }
        let profile = try JSONDecoder().decode(Profile.self, from: data)
        guard profile.account != nil || profile.organization != nil else { throw LocalClientError.noQuotaData }
        let organization = profile.organization?.organization_type?.lowercased()
        let tier = profile.organization?.rate_limit_tier?.lowercased()
        let maxPlan: String = switch tier {
        case "default_claude_max_5x": "max_5x"
        case "default_claude_max_20x": "max_20x"
        default: "max"
        }
        switch organization {
        case "claude_pro": return "pro"
        case "claude_max": return maxPlan
        case "claude_team": return "team"
        case "claude_enterprise": return "enterprise"
        case "claude_free": return "free"
        default: break
        }
        // Generic rate-limit tiers do not identify a subscription. Fall back
        // only to explicit profile flags; unfamiliar profiles stay unlabeled.
        if profile.account?.has_claude_max == true, profile.account?.has_claude_pro != true { return maxPlan }
        if profile.account?.has_claude_pro == true, profile.account?.has_claude_max != true { return "pro" }
        return nil
    }
}

/// Only the parsed plan is retained. The cache belongs to one proxy client.
actor ClaudePlanCache {
    static let lifetime: TimeInterval = 3600
    static let retryDelay: TimeInterval = 300
    private struct Entry {
        let plan: String?
        let retryAt: Date
    }
    private var entries: [ProxyAccountIdentity: Entry] = [:]
    private var pending: [ProxyAccountIdentity: Task<String?, Never>] = [:]

    func plan(for account: ProxyAccountIdentity, fallback: String? = nil, now: Date = .now,
              fetch: @escaping @Sendable () async throws -> String?) async -> String? {
        if let entry = entries[account], entry.retryAt > now { return entry.plan }
        if let task = pending[account] { return await task.value }
        let task = Task { await self.refresh(account, fallback: fallback, now: now, fetch: fetch) }
        pending[account] = task
        let plan = await task.value
        pending[account] = nil
        return plan
    }

    private func refresh(_ account: ProxyAccountIdentity, fallback: String?, now: Date,
                         fetch: @Sendable () async throws -> String?) async -> String? {
        let previous = entries[account]?.plan ?? fallback
        do {
            let plan = try await fetch()
            entries[account] = Entry(plan: plan, retryAt: now.addingTimeInterval(Self.lifetime))
            return plan
        } catch {
            entries[account] = Entry(plan: previous, retryAt: now.addingTimeInterval(Self.retryDelay))
            return previous
        }
    }
}
