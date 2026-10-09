import Foundation
import CLIProxyBarCore

/// Antigravity's quota summary, with the older per-model response as a fallback.
enum GoogleQuotaParser {
    static func summary(_ data: Data, now: Date = Date()) throws -> ProviderQuota {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], root["error"] == nil else { throw LocalClientError.noQuotaData }
        let groups = root["groups"] as? [[String: Any]]
            ?? (root["response"] as? [String: Any])?["groups"] as? [[String: Any]]
            ?? (root["summary"] as? [String: Any])?["groups"] as? [[String: Any]] ?? []
        var models: [QuotaMetric] = []
        for (groupIndex, group) in groups.enumerated() {
            let groupName = group["displayName"] as? String ?? group["name"] as? String ?? "Quota"
            let lower = groupName.lowercased()
            let groupID = lower.contains("claude") || lower.contains("gpt") ? "claude-gpt" : lower.contains("gemini") ? "gemini" : "group-\(groupIndex)"
            for (index, bucket) in (group["buckets"] as? [[String: Any]] ?? []).enumerated() {
                guard bucket["disabled"] as? Bool != true else { continue }
                let remaining = bucket["remaining"] as? [String: Any] ?? [:]
                let raw = bucket["remainingFraction"] ?? bucket["remaining_fraction"] ?? remaining["remainingFraction"] ?? remaining["remaining_fraction"]
                    ?? (remaining["case"] as? String == "remainingFraction" ? remaining["value"] : nil)
                let fraction = PluginQuotaParser.number(raw) ?? (raw as? String).flatMap(Double.init)
                guard let fraction, fraction.isFinite, (0...1).contains(fraction) else { continue }
                let window = bucket["window"] as? String ?? bucket["bucketId"] as? String ?? bucket["name"] as? String ?? bucket["id"] as? String ?? ""
                let period: String
                let duration: TimeInterval?
                switch window.lowercased() {
                case "weekly", "seven-day-weekly", "7d": period = "weekly"; duration = 604800
                case "five-hour-session", "five-hour", "5h": period = "session"; duration = 18000
                default: period = "bucket-\(index)"; duration = nil
                }
                let name = "antigravity-\(groupID)-\(period)"
                guard !models.contains(where: { $0.name == name }) else { continue }
                models.append(QuotaMetric(name: name, percentage: fraction * 100,
                    resetTime: bucket["resetTime"] as? String ?? bucket["reset_time"] as? String ?? bucket["resetAt"] as? String ?? "",
                    windowDuration: duration, label: groupName + " · " + (period == "session" ? "Session" : period == "weekly" ? "Weekly" : window.isEmpty ? "Quota" : window.capitalized)))
            }
        }
        guard !models.isEmpty else { throw LocalClientError.noQuotaData }
        return ProviderQuota(models: models, lastUpdated: now)
    }

    static func models(_ data: Data, now: Date = Date()) throws -> ProviderQuota {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], root["error"] == nil,
              let rawModels = root["models"] as? [String: Any] else { throw LocalClientError.noQuotaData }
        let models = rawModels.keys.sorted().compactMap { name -> QuotaMetric? in
            guard let model = rawModels[name] as? [String: Any], let info = model["quotaInfo"] as? [String: Any],
                  let fraction = PluginQuotaParser.number(info["remainingFraction"]), (0...1).contains(fraction) else { return nil }
            return QuotaMetric(name: name, percentage: fraction * 100, resetTime: info["resetTime"] as? String ?? "", label: model["displayName"] as? String)
        }
        guard !models.isEmpty else { throw LocalClientError.noQuotaData }
        return ProviderQuota(models: models, lastUpdated: now)
    }
}
