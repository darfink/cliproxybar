import Foundation
import CLIProxyBarCore

enum QuotaResetKind: String, Codable, Sendable {
    case short, long

    static func classify(_ name: String) -> Self? {
        switch name {
        case "five-hour-session", "codex-session", "opencode-go-rolling": return .short
        case "seven-day-weekly", "seven-day-sonnet", "seven-day-opus", "codex-weekly",
             "opencode-go-weekly", "opencode-go-monthly": return .long
        default:
            if name.hasPrefix("antigravity-") {
                if name.hasSuffix("-session") { return .short }
                if name.hasSuffix("-weekly") { return .long }
            }
            // Generic labels do not establish whether a reset restores the whole
            // allowance or only expires part of a rolling window.
            return nil
        }
    }

    static func label(_ name: String) -> String {
        switch name {
        case "five-hour-session", "codex-session": return "Session"
        case "opencode-go-rolling": return "Rolling"
        case "opencode-go-monthly": return "Monthly"
        case "seven-day-sonnet": return "Weekly (Sonnet)"
        case "seven-day-opus": return "Weekly (Opus)"
        default:
            if name.hasPrefix("plugin:"), let window = name.split(separator: ":").last {
                return window == "rolling" ? "Rolling" : window == "monthly" ? "Monthly" : window == "weekly" ? "Weekly" : "Session"
            }
            return name.hasSuffix("-session") ? "Session" : "Weekly"
        }
    }
}

struct QuotaResetEvent: Equatable, Sendable {
    let accountID: String
    let provider: String
    let accountName: String
    let metric: String
    let kind: QuotaResetKind
    let resetAt: Date

    var identifier: String {
        ProxyUsageHistory.digest(accountID + "\n" + metric + "\n" + String(resetAt.timeIntervalSince1970))
    }
    var windowName: String { QuotaResetKind.label(metric) }
}

/// Compare fresh provider readings, never a countdown or a cached display value.
/// Disk state contains only hashed account identities and quota observations.
struct QuotaResetMonitor {
    struct Observation: Codable {
        let remaining: Double
        let resetAt: Date?
        let observedAt: Date
        let plan: String?
        let handledReset: Date?
        let pendingReset: Date?
    }
    struct State: Codable {
        let version: Int
        var observations: [String: Observation]
    }
    let url: URL
    private let endpointHash: String
    private(set) var observations: [String: Observation] = [:]

    init(endpoint: String, directory: URL? = nil) {
        endpointHash = ProxyUsageHistory.digest(endpoint)
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CLIProxyBar")
        url = root.appendingPathComponent("quota-resets-\(endpointHash).json")
    }

    mutating func load() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let state = try JSONDecoder().decode(State.self, from: Data(contentsOf: url))
        guard state.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
        observations = state.observations
    }

    func save() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(State(version: 1, observations: observations)).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    mutating func observe(account: ProxyAccount, quota: ProviderQuota, now: Date = Date()) -> [QuotaResetEvent] {
        let observedAt = quota.lastUpdated
        guard account.disabled != true, !quota.isForbidden,
              observedAt <= now.addingTimeInterval(60), observedAt >= now.addingTimeInterval(-600) else { return [] }
        let accountID = ProxyUsageHistory.digest(endpointHash + "\n" + account.provider + "\n" + account.name)
        let plan = quota.planType?.lowercased()
        var events: [QuotaResetEvent] = []
        for metric in quota.models {
            guard let kind = QuotaResetKind.classify(metric.name), metric.percentage.isFinite,
                  (0...100).contains(metric.percentage) else { continue }
            let key = accountID + ":" + metric.name
            let previous = observations[key]
            guard previous.map({ observedAt > $0.observedAt }) ?? true else { continue }
            let parsed = ProxyAccount.observationDate(metric.resetTime)
            let reset = parsed == .distantPast ? nil : parsed
            var handled = previous?.handledReset
            if let previous, previous.plan == plan {
                var confirmed: Date?
                if metric.name == "opencode-go-rolling" || (metric.name.hasPrefix("plugin:") && metric.name.hasSuffix(":rolling")) {
                    // A rolling reset date can move as requests expire. Wait for
                    // a full refill rather than treating each increase as a reset.
                    if previous.remaining < 99.5, metric.percentage >= 99.5,
                       observedAt.timeIntervalSince(previous.observedAt) <= 900,
                       previous.handledReset.map({ observedAt.timeIntervalSince($0) >= 900 }) ?? true {
                        confirmed = observedAt
                    }
                } else if let deadline = previous.pendingReset,
                          deadline <= observedAt,
                          observedAt.timeIntervalSince(deadline) <= (kind == .long ? 86400 : 900),
                          previous.handledReset != deadline {
                    let advanced = reset.map { $0 > deadline.addingTimeInterval(60) && $0 > observedAt } ?? false
                    // Some providers clear resets_at when a window is unused.
                    let cleared = reset == nil && previous.remaining < 99.5 && metric.percentage >= 99.5
                    if advanced || cleared { confirmed = deadline }
                }
                if let confirmed {
                    handled = confirmed
                    events.append(QuotaResetEvent(accountID: accountID, provider: account.provider,
                        accountName: account.displayName, metric: metric.name, kind: kind, resetAt: confirmed))
                }
            }
            let pending: Date?
            if let reset, reset > observedAt { pending = reset }
            else if previous?.plan == plan, let prior = previous?.pendingReset, handled != prior { pending = prior }
            else { pending = nil }
            observations[key] = Observation(remaining: metric.percentage, resetAt: reset,
                observedAt: observedAt, plan: plan, handledReset: handled, pendingReset: pending)
        }
        observations = observations.filter { $0.value.observedAt >= now.addingTimeInterval(-65 * 86400) }
        return events
    }
}
