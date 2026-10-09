import Foundation
import CoreFoundation
import CLIProxyBarCore

/// The backend owns provider credentials and quota capability discovery.
enum PluginQuotaParser {
    static func providers(_ data: Data) throws -> Set<String> {
        struct Envelope: Decodable {
            struct Entry: Decodable {
                let provider: String
                let supported_providers: [String]?
            }
            let providers: [Entry]?
        }
        let response = try JSONDecoder().decode(Envelope.self, from: data)
        return Set((response.providers ?? []).flatMap {
            ($0.supported_providers?.isEmpty == false ? $0.supported_providers! : [$0.provider])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
        })
    }

    static func number(_ raw: Any?) -> Double? {
        guard let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }

    static func parse(_ data: Data, provider: String, now: Date = Date()) throws -> ProviderQuota {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], root["error"] == nil else { throw LocalClientError.noQuotaData }
        let subscription = root["subscription"] as? [String: Any] ?? [:]
        let offset = number(root["serverTimeOffsetMs"] ?? root["server_time_offset_ms"]) ?? 0
        var models: [QuotaMetric] = []
        var occurrences: [String: Int] = [:]
        for (groupIndex, group) in (root["groups"] as? [[String: Any]] ?? []).enumerated() {
            let groupName = group["displayName"] as? String ?? group["display_name"] as? String ?? ""
            for bucket in group["buckets"] as? [[String: Any]] ?? [] {
                guard let remaining = number(bucket["remainingFraction"] ?? bucket["remaining_fraction"]), (0...1).contains(remaining) else { continue }
                let window = bucket["window"] as? String ?? ""
                let groupID = groupName.isEmpty ? String(groupIndex) : ProxyUsageHistory.digest(groupName)
                let identity = groupID + ":" + window
                let occurrence = occurrences[identity, default: 0]
                occurrences[identity] = occurrence + 1
                let name = provider == "opencode-go" && ["rolling", "weekly", "monthly"].contains(window)
                    ? "opencode-go-" + window : "plugin:\(groupID):\(occurrence):\(window)"
                guard !models.contains(where: { $0.name == name }) else { continue }
                let windowLabel = window.split(whereSeparator: { $0 == "-" || $0 == "_" }).map { $0.capitalized }.joined(separator: " ")
                let label = provider == "opencode-go" ? windowLabel : [groupName, windowLabel].filter { !$0.isEmpty }.joined(separator: " · ")
                var reset = bucket["resetTime"] as? String ?? bucket["reset_time"] as? String ?? ""
                let resetDate = ProxyAccount.observationDate(reset)
                if offset != 0, resetDate != .distantPast { reset = ISO8601DateFormatter().string(from: resetDate.addingTimeInterval(-offset / 1000)) }
                // A rolling or monthly label does not establish a fixed duration.
                let duration: TimeInterval? = switch window.lowercased() {
                case "daily": 86400
                case "weekly": 604800
                case "five-hour", "five-hour-session", "5h": 18000
                default: nil
                }
                models.append(QuotaMetric(name: name, percentage: remaining * 100, resetTime: reset,
                    tooltip: bucket["description"] as? String, windowDuration: duration, label: label.isEmpty ? "Quota" : label))
            }
        }
        for (index, summary) in (root["summary"] as? [[String: Any]] ?? []).enumerated() {
            guard let value = number(summary["value"]), let label = summary["label"] as? String, !label.isEmpty else { continue }
            let text: String
            if summary["format"] as? String == "currency", let currency = summary["currency"] as? String,
               currency.count == 3, currency.allSatisfy({ $0.isASCII && $0.isLetter }) {
                text = value.formatted(.currency(code: currency))
            } else {
                text = [value.formatted(.number.precision(.fractionLength(0...2))), summary["unit"] as? String ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
            }
            models.append(QuotaMetric(name: "plugin-summary:\(index)", percentage: -1, resetTime: "", presentation: .status(text: text), label: label))
        }
        guard !models.isEmpty else { throw LocalClientError.noQuotaData }
        return ProviderQuota(models: models, lastUpdated: now,
            planType: subscription["plan"] as? String ?? subscription["tierName"] as? String ?? subscription["tier_name"] as? String)
    }
}
