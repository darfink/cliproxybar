import Foundation
import CoreFoundation
import CLIProxyBarCore

/// Uses CLIProxyAPI's credential substitution; no provider token leaves the proxy.
enum ActiveQuotaParser {
    static func supports(_ provider: String) -> Bool { ["claude", "codex", "opencode-go", "antigravity"].contains(provider) }
    static func supports(_ account: ProxyAccount, pluginProviders: Set<String>) -> Bool {
        supports(account.provider) || account.supports_quota == true || PluginQuotaParser.text(account.quota_provider) != nil
            || pluginProviders.contains(QuotaProviderRegistry.normalize(account.provider))
    }

    static func googleRequest(for account: ProxyAccount, operation: String, payload: String) throws -> ProxyAPICall {
        guard let index = account.auth_index, !index.isEmpty else { throw LocalClientError.missingAuthIndex }
        return ProxyAPICall(authIndex: index, method: "POST", url: "https://cloudcode-pa.googleapis.com/v1internal:" + operation,
            header: ["Authorization": "Bearer $TOKEN$", "Content-Type": "application/json", "User-Agent": "antigravity/1.11.3 Darwin/arm64"], data: payload)
    }

    static func request(for account: ProxyAccount) throws -> ProxyAPICall {
        guard let index = account.auth_index, !index.isEmpty else { throw LocalClientError.missingAuthIndex }
        var headers = ["Authorization": "Bearer $TOKEN$", "Accept": "application/json"]
        let url: String
        switch account.provider {
        case "claude":
            url = "https://api.anthropic.com/api/oauth/usage"
            headers["anthropic-beta"] = "oauth-2025-04-20"
        case "codex":
            url = "https://chatgpt.com/backend-api/wham/usage"
            if let id = account.id_token?.chatgpt_account_id, !id.isEmpty { headers["ChatGPT-Account-Id"] = id }
        default: throw LocalClientError.noQuotaData
        }
        return ProxyAPICall(authIndex: index, method: "GET", url: url, header: headers, data: nil)
    }

    static func parse(_ data: Data, provider: String, now: Date = Date()) throws -> ProviderQuota {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], json["error"] == nil else { throw LocalClientError.noQuotaData }
        var models: [QuotaMetric] = []
        func metric(_ name: String, used: Any?, reset: String, duration: TimeInterval?) {
            guard let value = used as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite, (0...100).contains(value.doubleValue) else { return }
            models.append(QuotaMetric(name: name, percentage: 100 - value.doubleValue, resetTime: reset, windowDuration: duration))
        }
        switch provider {
        case "claude":
            for (key, name) in [("five_hour", "five-hour-session"), ("seven_day", "seven-day-weekly"), ("seven_day_sonnet", "seven-day-sonnet"), ("seven_day_opus", "seven-day-opus")] {
                guard let window = json[key] as? [String: Any] else { continue }
                metric(name, used: window["utilization"], reset: window["resets_at"] as? String ?? "", duration: key == "five_hour" ? 18000 : 604800)
            }
        case "codex":
            let rate = json["rate_limit"] as? [String: Any] ?? [:]
            for (key, fallback) in [("primary_window", "codex-session"), ("secondary_window", "codex-weekly")] {
                guard let window = rate[key] as? [String: Any] else { continue }
                let seconds = (window["limit_window_seconds"] as? NSNumber)?.doubleValue
                if let seconds, seconds <= 0 { continue }
                let name = seconds.map { $0 >= 518400 ? "codex-weekly" : "codex-session" } ?? fallback
                guard !models.contains(where: { $0.name == name }) else { continue }
                let reset = (window["reset_at"] as? NSNumber).map { ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: $0.doubleValue)) } ?? ""
                metric(name, used: window["used_percent"], reset: reset, duration: seconds)
            }
        default: throw LocalClientError.noQuotaData
        }
        guard !models.isEmpty else { throw LocalClientError.noQuotaData }
        let resets = json["rate_limit_reset_credits"] as? [String: Any]
        let resetCount = provider == "codex" ? availableResets(resets?["available_count"]) : nil
        return ProviderQuota(models: models, lastUpdated: now, planType: json["plan_type"] as? String, availableResetCredits: resetCount)
    }
    static func parsePlugin(_ data: Data, now: Date = Date()) throws -> ProviderQuota {
        try PluginQuotaParser.parse(data, provider: "opencode-go", now: now)
    }

    private static func availableResets(_ raw: Any?) -> Int? {
        let value: Double?
        if let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            value = number.doubleValue
        } else if let text = raw as? String {
            value = Double(text)
        } else {
            return nil
        }
        guard let value, value.isFinite, value >= 0 else { return nil }
        return Int(exactly: value)
    }

}
