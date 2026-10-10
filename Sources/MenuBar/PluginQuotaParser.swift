import Foundation
import CoreFoundation
import CLIProxyBarCore

/// The backend owns provider credentials and quota capability discovery.
enum PluginQuotaParser {
    static func registry(_ data: Data) throws -> QuotaProviderRegistry {
        struct Envelope: Decodable {
            struct Entry: Decodable {
                let plugin_id: String?
                let provider: String
                let display_name: String?
                let supported_providers: [String]?
                let supports_reset: Bool?
            }
            let providers: [Entry]?
        }
        let response = try JSONDecoder().decode(Envelope.self, from: data)
        return QuotaProviderRegistry(entries: (response.providers ?? []).map {
            RegisteredQuotaProvider(pluginID: text($0.plugin_id), provider: QuotaProviderRegistry.normalize($0.provider),
                displayName: text($0.display_name), supportedProviders: ($0.supported_providers ?? [])
                    .map(QuotaProviderRegistry.normalize).filter { !$0.isEmpty }, supportsReset: $0.supports_reset ?? false)
        }.filter { !$0.identifiers.isEmpty })
    }

    static func number(_ raw: Any?) -> Double? {
        guard let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }

    static func text(_ values: Any?...) -> String? {
        for raw in values {
            if let value = raw as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    static func parse(_ data: Data, provider: String, now: Date = Date()) throws -> ProviderQuota {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], root["error"] == nil else {
            throw LocalClientError.noQuotaData
        }
        let subscription = root["subscription"] as? [String: Any] ?? [:]
        let plan = text(subscription["plan"], subscription["tierName"], subscription["tier_name"],
                        subscription["tierId"], subscription["tier_id"])
        let offset = number(root["serverTimeOffsetMs"] ?? root["server_time_offset_ms"]) ?? 0
        var models: [QuotaMetric] = []
        var occurrences: [String: Int] = [:]
        var invalidReadings = false
        for field in ["groups", "summary"] {
            if let value = root[field], !(value is NSNull), !(value is [[String: Any]]) { throw LocalClientError.noQuotaData }
        }
        for group in root["groups"] as? [[String: Any]] ?? [] {
            let groupName = text(group["displayName"], group["display_name"]) ?? ""
            if let value = group["buckets"], !(value is NSNull), !(value is [[String: Any]]) { throw LocalClientError.noQuotaData }
            let buckets = group["buckets"] as? [[String: Any]] ?? []
            // Unnamed groups can be distinguished by their labels, never by a reading
            // or reset date. Identical unlabeled groups have no stable backend identity.
            let groupKey = groupName.isEmpty ? buckets.map {
                (text($0["window"]) ?? "") + "\n" + (text($0["description"]) ?? "")
            }.sorted().joined(separator: "\n") : groupName
            let groupID = ProxyUsageHistory.digest(groupKey)
            let counts = Dictionary(grouping: buckets, by: { text($0["window"]) ?? "" }).mapValues(\.count)
            for bucket in buckets {
                guard let remaining = number(bucket["remainingFraction"] ?? bucket["remaining_fraction"]), (0...1).contains(remaining) else {
                    invalidReadings = true
                    continue
                }
                let window = text(bucket["window"]) ?? ""
                let description = text(bucket["description"])
                let duplicateWindow = (counts[window] ?? 0) > 1
                let identity = groupID + ":" + window + ":" + (description ?? "")
                let occurrence = occurrences[identity, default: 0]
                occurrences[identity] = occurrence + 1
                let bucketID = ProxyUsageHistory.digest(identity) + ":" + String(occurrence)
                let isOpenCode = QuotaProviderRegistry.normalize(provider) == "opencode-go"
                let name = isOpenCode && ["rolling", "weekly", "monthly"].contains(window)
                    ? "opencode-go-" + window : "plugin:\(groupID):\(bucketID):\(window)"
                guard !models.contains(where: { $0.name == name }) else { continue }
                let windowLabel = window.split(whereSeparator: { $0 == "-" || $0 == "_" }).map { $0.capitalized }.joined(separator: " ")
                let bucketLabel: String
                if duplicateWindow {
                    bucketLabel = description.map { $0 + (occurrence == 0 ? "" : " (\(occurrence + 1))") }
                        ?? (windowLabel.isEmpty ? "Quota" : windowLabel) + " \(occurrence + 1)"
                } else { bucketLabel = windowLabel }
                let label = isOpenCode ? windowLabel : [groupName, bucketLabel].filter { !$0.isEmpty }.joined(separator: " · ")
                let rawReset = text(bucket["resetTime"], bucket["reset_time"])
                let resetDate = ProxyAccount.observationDate(rawReset)
                let reset = resetDate == .distantPast ? "" : ISO8601DateFormatter()
                    .string(from: resetDate.addingTimeInterval(-offset / 1000))
                // The generic contract does not describe fixed versus rolling windows.
                // OpenCode Go's weekly limit is known; unfamiliar plugins get no guessed pace.
                let duration: TimeInterval? = isOpenCode && window == "weekly" ? 604800 : nil
                models.append(QuotaMetric(name: name, percentage: remaining * 100, resetTime: reset,
                    tooltip: description, windowDuration: duration, label: label.isEmpty ? "Quota" : label))
            }
        }
        var summaryKeys: Set<String> = []
        for summary in root["summary"] as? [[String: Any]] ?? [] {
            guard let value = number(summary["value"]), let key = text(summary["key"]), let label = text(summary["label"]) else {
                invalidReadings = true
                continue
            }
            guard summaryKeys.insert(key).inserted else { continue }
            let code = text(summary["currency"])?.uppercased()
            let currency = summary["format"] as? String == "currency" && code?.count == 3
                && code?.allSatisfy({ $0.isASCII && $0.isLetter }) == true ? code : nil
            models.append(QuotaMetric(name: "plugin-summary:" + ProxyUsageHistory.digest(key), percentage: -1, resetTime: "",
                label: label, summary: QuotaSummaryValue(key: key, value: value, unit: text(summary["unit"]), currency: currency)))
        }
        // Successful responses can contain only a subscription or no current limits.
        // Invalid numbers still stay unknown instead of becoming zero consumption.
        if models.isEmpty && plan == nil && invalidReadings { throw LocalClientError.noQuotaData }
        return ProviderQuota(models: models, lastUpdated: now, planType: plan)
    }
}
