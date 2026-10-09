import Foundation
import CryptoKit

/// Display counters only. Raw events, keys, headers, and error bodies never reach disk.
struct ProxyUsageTokens: Codable, Equatable, Sendable {
    var input: Int64 = 0
    var output: Int64 = 0
    var cached: Int64 = 0
    var cacheWrite: Int64 = 0
    var reasoning: Int64 = 0
    var total: Int64 = 0

    mutating func add(_ other: Self) {
        input = Self.sum(input, other.input)
        output = Self.sum(output, other.output)
        cached = Self.sum(cached, other.cached)
        cacheWrite = Self.sum(cacheWrite, other.cacheWrite)
        reasoning = Self.sum(reasoning, other.reasoning)
        total = Self.sum(total, other.total)
    }

    static func sum(_ left: Int64, _ right: Int64) -> Int64 {
        let result = max(0, left).addingReportingOverflow(max(0, right))
        return result.overflow ? .max : result.partialValue
    }
}

struct ProxyUsageEvent: Decodable, Sendable {
    let provider: String
    let authIndex: String
    let model: String
    let timestamp: Date
    let identifier: String
    let failed: Bool
    let tokens: ProxyUsageTokens

    private enum CodingKeys: String, CodingKey {
        case provider, model, timestamp, failed, tokens
        case authIndex = "auth_index", executionID = "execution_id", requestID = "request_id"
        case breakdown = "token_breakdown"
    }

    private struct RawTokens: Decodable {
        var input_tokens: Int64?
        var output_tokens: Int64?
        var cached_tokens: Int64?
        var cache_read_tokens: Int64?
        var cache_creation_tokens: Int64?
        var reasoning_tokens: Int64?
        var total_tokens: Int64?
    }

    private struct Breakdown: Decodable {
        struct Input: Decodable {
            let total_tokens: Int64
            let cache_read_tokens: Int64
            let cache_write_tokens: Int64
        }
        struct Output: Decodable { let total_tokens: Int64; let reasoning_tokens: Int64 }
        let schema_version: Int
        let total_tokens: Int64
        let input: Input
        let output: Output
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        provider = try values.decodeIfPresent(String.self, forKey: .provider) ?? ""
        authIndex = try values.decodeIfPresent(String.self, forKey: .authIndex) ?? ""
        model = String((try values.decodeIfPresent(String.self, forKey: .model) ?? "Unknown model").prefix(120))
        let rawTimestamp = try values.decodeIfPresent(String.self, forKey: .timestamp)
        timestamp = ProxyAccount.observationDate(rawTimestamp)
        failed = try values.decodeIfPresent(Bool.self, forKey: .failed) ?? false
        let raw = try values.decodeIfPresent(RawTokens.self, forKey: .tokens)
        let cached = max(0, raw?.cache_read_tokens ?? raw?.cached_tokens ?? 0)
        let cacheWrite = max(0, raw?.cache_creation_tokens ?? 0)
        let input = max(0, raw?.input_tokens ?? 0)
        let output = max(0, raw?.output_tokens ?? 0)
        // Legacy Anthropic input counts exclude cache reads and writes.
        let totalInput = provider == "claude" ? ProxyUsageTokens.sum(ProxyUsageTokens.sum(input, cached), cacheWrite) : input
        tokens = if let breakdown = try values.decodeIfPresent(Breakdown.self, forKey: .breakdown), breakdown.schema_version == 2 {
            ProxyUsageTokens(input: max(0, breakdown.input.total_tokens), output: max(0, breakdown.output.total_tokens),
                cached: max(0, breakdown.input.cache_read_tokens), cacheWrite: max(0, breakdown.input.cache_write_tokens),
                reasoning: max(0, breakdown.output.reasoning_tokens), total: max(0, breakdown.total_tokens))
        } else {
            ProxyUsageTokens(input: totalInput, output: output, cached: cached, cacheWrite: cacheWrite,
                reasoning: max(0, raw?.reasoning_tokens ?? 0), total: max(0, raw?.total_tokens ?? ProxyUsageTokens.sum(totalInput, output)))
        }
        let requestID = try values.decodeIfPresent(String.self, forKey: .requestID) ?? ""
        let executionID = try values.decodeIfPresent(String.self, forKey: .executionID) ?? ""
        let eventID = executionID.isEmpty ? [requestID, rawTimestamp ?? "", model, String(tokens.total), String(failed)].joined(separator: "\n") : executionID
        identifier = ProxyUsageHistory.digest([provider, authIndex, eventID].joined(separator: "\n"))
    }
}

struct ProxyUsageModelTotals: Codable, Equatable, Sendable {
    var requests: Int64 = 0
    var tokens = ProxyUsageTokens()
}

struct ProxyUsageDay: Codable, Equatable, Sendable {
    let date: Date
    var requests: Int64 = 0
    var failures: Int64 = 0
    var tokens = ProxyUsageTokens()
    var models: [String: ProxyUsageModelTotals] = [:]
}

struct ProxyUsageSnapshot: Equatable, Sendable {
    var days: [ProxyUsageDay] = []
    var startedAt: Date?
    var trackingEnabled = false
    var issue: String?
    var lastCollectedAt: Date?
    var successCount: Int64?
    var failedCount: Int64?

    func totals(since date: Date) -> ProxyUsageTokens {
        days.filter { $0.date >= date }.reduce(into: ProxyUsageTokens()) { $0.add($1.tokens) }
    }
}

struct ProxyUsageHistory {
    private struct Envelope: Codable {
        let version: Int
        let endpointHash: String
        var startedAt: Date?
        var accounts: [String: [ProxyUsageDay]] = [:]
        var seen: [String: Date] = [:]
    }

    let url: URL
    private var saved: Envelope

    init(endpoint: String, directory: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let root = directory ?? support.appendingPathComponent("CLIProxyBar")
        let endpointHash = Self.digest(endpoint)
        url = root.appendingPathComponent("proxy-usage-\(endpointHash).json")
        saved = Envelope(version: 1, endpointHash: endpointHash)
    }

    static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func accountKey(provider: String, authIndex: String) -> String {
        digest(provider + "\n" + authIndex)
    }

    mutating func load() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let value = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: url))
        guard value.version == 1, value.endpointHash == saved.endpointHash else {
            throw CocoaError(.fileReadCorruptFile)
        }
        saved = value
    }

    mutating func start(at date: Date = Date()) {
        if saved.startedAt == nil { saved.startedAt = date }
    }

    mutating func ingest(_ events: [ProxyUsageEvent], now: Date = Date(), calendar: Calendar = .current) {
        let cutoff = calendar.date(byAdding: .day, value: -365, to: calendar.startOfDay(for: now))!
        for event in events {
            guard !event.provider.isEmpty, !event.authIndex.isEmpty, event.timestamp >= cutoff,
                  event.timestamp <= now.addingTimeInterval(60), saved.seen[event.identifier] == nil else { continue }
            saved.seen[event.identifier] = now
            saved.startedAt = min(saved.startedAt ?? now, event.timestamp)
            let key = Self.accountKey(provider: event.provider, authIndex: event.authIndex)
            let date = calendar.startOfDay(for: event.timestamp)
            var days = saved.accounts[key] ?? []
            let index: Int
            if let existing = days.firstIndex(where: { $0.date == date }) { index = existing }
            else { days.append(ProxyUsageDay(date: date)); index = days.count - 1 }
            days[index].requests = ProxyUsageTokens.sum(days[index].requests, 1)
            if event.failed { days[index].failures = ProxyUsageTokens.sum(days[index].failures, 1) }
            days[index].tokens.add(event.tokens)
            var model = days[index].models[event.model] ?? ProxyUsageModelTotals()
            model.requests = ProxyUsageTokens.sum(model.requests, 1)
            model.tokens.add(event.tokens)
            days[index].models[event.model] = model
            saved.accounts[key] = days
        }
        for key in Array(saved.accounts.keys) {
            saved.accounts[key] = saved.accounts[key]?.filter { $0.date >= cutoff }
        }
        saved.seen = saved.seen.filter { $0.value >= now.addingTimeInterval(-86400) }
        if saved.seen.count > 10000 {
            saved.seen = Dictionary(uniqueKeysWithValues: saved.seen.sorted { $0.value > $1.value }.prefix(10000).map { ($0.key, $0.value) })
        }
    }

    func snapshot(for account: ProxyAccount, trackingEnabled: Bool, issue: String?, lastCollectedAt: Date?) -> ProxyUsageSnapshot {
        let days = account.auth_index.map { saved.accounts[Self.accountKey(provider: account.provider, authIndex: $0)] ?? [] } ?? []
        return ProxyUsageSnapshot(days: days.sorted { $0.date < $1.date }, startedAt: saved.startedAt,
            trackingEnabled: trackingEnabled, issue: issue, lastCollectedAt: lastCollectedAt,
            successCount: account.success, failedCount: account.failed)
    }

    func save() throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(saved).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
