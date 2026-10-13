import Foundation
import CLIProxyBarCore

struct QuotaHistoryPoint: Codable, Equatable, Sendable, Identifiable {
    let date: Date
    let usedPercent: Double
    var id: Date { date }
}

struct QuotaHistorySeries: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let points: [QuotaHistoryPoint]
}

struct QuotaHistorySnapshot: Equatable, Sendable {
    var series: [QuotaHistorySeries] = []
    var recordingEnabled = true
    var issue: String?
}

/// Only timestamps and percentages reach disk. Account and window identifiers are hashed.
struct QuotaHistory {
    private struct Envelope: Codable {
        let version: Int
        let endpointHash: String
        var readings: [String: [String: [QuotaHistoryPoint]]] = [:]
    }
    static let retention: TimeInterval = 30 * 86400
    static let maximumPoints = 9000
    let url: URL
    private var saved: Envelope

    init(endpoint: String, directory: URL? = nil) {
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CLIProxyBar")
        let digest = ProxyUsageHistory.digest(endpoint)
        url = root.appendingPathComponent("quota-history-\(digest).json")
        saved = Envelope(version: 1, endpointHash: digest)
    }

    private static func accountKey(_ account: ProxyAccount) -> String {
        ProxyUsageHistory.digest((QuotaProvider(rawValue: account.provider)?.rawValue ?? account.provider) + "\n" + account.name)
    }

    mutating func load() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let value = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: url))
        guard value.version == 1, value.endpointHash == saved.endpointHash,
              value.readings.values.allSatisfy({ windows in
                  windows.values.allSatisfy { points in
                      points.count <= Self.maximumPoints && points.allSatisfy {
                          $0.date.timeIntervalSince1970.isFinite && $0.usedPercent.isFinite && (0...100).contains($0.usedPercent)
                      } && zip(points, points.dropFirst()).allSatisfy { $0.0.date < $0.1.date }
                  }
              }) else { throw CocoaError(.fileReadCorruptFile) }
        saved = value
    }

    @MainActor mutating func record(account: ProxyAccount, quota: ProviderQuota, now: Date = .now) {
        let date = quota.lastUpdated
        guard account.quotaReadState == .current, account.disabled != true,
              date >= now.addingTimeInterval(-Self.retention), date <= now.addingTimeInterval(60) else { return }
        let key = Self.accountKey(account)
        var windows = saved.readings[key] ?? [:]
        for metric in quota.models where !metric.isStandaloneMetric && metric.percentage.isFinite && (0...100).contains(metric.percentage) {
            let window = ProxyUsageHistory.digest(metric.id)
            var points = windows[window] ?? []
            let point = QuotaHistoryPoint(date: date, usedPercent: 100 - metric.percentage)
            if let last = points.last {
                guard date >= last.date else { continue }
                if date == last.date || (floor(date.timeIntervalSince1970 / 60) == floor(last.date.timeIntervalSince1970 / 60)
                    && point.usedPercent == last.usedPercent) {
                    points[points.count - 1] = point
                } else { points.append(point) }
            } else { points.append(point) }
            windows[window] = Array(points.suffix(Self.maximumPoints))
        }
        saved.readings[key] = windows
        prune(now: now)
    }

    private mutating func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.retention)
        for account in Array(saved.readings.keys) {
            var windows = saved.readings[account] ?? [:]
            for window in Array(windows.keys) {
                let points = windows[window]?.filter { $0.date >= cutoff } ?? []
                windows[window] = points.isEmpty ? nil : points
            }
            saved.readings[account] = windows.isEmpty ? nil : windows
        }
    }

    @MainActor func snapshot(for account: ProxyAccount, recordingEnabled: Bool = true, issue: String? = nil, now: Date = .now) -> QuotaHistorySnapshot {
        let windows = saved.readings[Self.accountKey(account)] ?? [:]
        let series = account.providerQuota().models.filter {
            !$0.isStandaloneMetric && $0.percentage.isFinite && (0...100).contains($0.percentage)
        }.map { metric in
            QuotaHistorySeries(id: metric.id, title: metric.displayName,
                points: (windows[ProxyUsageHistory.digest(metric.id)] ?? []).filter {
                    $0.date >= now.addingTimeInterval(-Self.retention) && $0.date <= now
                })
        }
        return QuotaHistorySnapshot(series: series, recordingEnabled: recordingEnabled, issue: issue)
    }

    func save() throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(saved).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

@MainActor
final class QuotaHistoryRecorder {
    private var history: QuotaHistory
    private var loaded = true
    private(set) var issue: String?
    var isEnabled = true

    init(endpoint: String, directory: URL? = nil) {
        history = QuotaHistory(endpoint: endpoint, directory: directory)
        do { try history.load() }
        catch {
            loaded = false
            issue = "Saved quota history could not be loaded. Recording stopped to preserve the file."
        }
    }

    func record(account: ProxyAccount, quota: ProviderQuota, now: Date = .now) {
        guard isEnabled, loaded else { return }
        history.record(account: account, quota: quota, now: now)
    }

    func save() {
        guard isEnabled, loaded else { return }
        do { try history.save(); issue = nil }
        catch { issue = "Could not save quota history. Recorded readings remain in memory." }
    }

    func snapshot(for account: ProxyAccount) -> QuotaHistorySnapshot {
        history.snapshot(for: account, recordingEnabled: isEnabled && loaded, issue: issue)
    }
}
