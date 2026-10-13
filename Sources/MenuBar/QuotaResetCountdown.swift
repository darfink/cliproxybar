import Foundation

/// Display only reported future reset times for quotas that are actually exhausted.
enum QuotaResetCountdown {
    struct Value: Equatable {
        let text: String
        let accessibilityText: String
    }

    static func resetDate(_ raw: String) -> Date? {
        let date = ProxyAccount.observationDate(raw)
        return date == .distantPast ? nil : date
    }

    static func value(remainingPercentage: Double, resetAt: Date?, now: Date = .now) -> Value? {
        guard remainingPercentage == 0, let resetAt else { return nil }
        let interval = resetAt.timeIntervalSince(now)
        guard interval.isFinite, interval > 0 else { return nil }
        if interval < 60 {
            return Value(text: "<1m", accessibilityText: "Resets in less than a minute")
        }
        let unit: (seconds: Double, short: String, long: String)
        if interval < 3600 { unit = (60, "m", "minute") }
        else if interval < 86400 { unit = (3600, "h", "hour") }
        else { unit = (86400, "d", "day") }
        // Round up so the label never promises an earlier reset.
        let count = ceil(interval / unit.seconds)
        let number = String(format: "%.0f", count)
        return Value(text: number + unit.short,
            accessibilityText: "Resets in " + number + " " + unit.long + (count == 1 ? "" : "s"))
    }
}
