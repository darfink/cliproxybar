import Foundation

/// Compatibility rules for the current quota contract, which has no cycle start or duration.
enum OpenCodeQuotaTiming {
    static func duration(window: String, resetAt: Date, observedAt: Date) -> TimeInterval? {
        switch window {
        case "rolling": return 18000
        case "weekly": return 604800
        case "monthly": return monthlyDuration(resetAt: resetAt, observedAt: observedAt)
        default: return nil
        }
    }

    private static func monthlyDuration(resetAt: Date, observedAt: Date) -> TimeInterval? {
        guard resetAt > observedAt, resetAt != .distantPast else { return nil }
        // OpenCode keeps the original subscription day and UTC time, clamping the
        // day to the month's last day when necessary. Its published implementation:
        // https://github.com/anomalyco/opencode/blob/a5312e169b13c0f08b93c4b6e0c3076c94785aca/packages/console/core/src/util/date.ts
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let resetMonth = calendar.dateInterval(of: .month, for: resetAt),
              let resetDays = calendar.range(of: .day, in: .month, for: resetAt),
              let previousMonth = calendar.date(byAdding: .month, value: -1, to: resetMonth.start),
              let previousDays = calendar.range(of: .day, in: .month, for: previousMonth) else { return nil }
        let resetDay = calendar.component(.day, from: resetAt)
        let possibleAnchors = resetDay...(resetDay == resetDays.count ? 31 : resetDay)
        let timeOfDay = resetAt.timeIntervalSince(calendar.startOfDay(for: resetAt))
        var cycleStart: Date?
        for anchor in possibleAnchors {
            guard let startDay = calendar.date(byAdding: .day, value: min(anchor, previousDays.count) - 1,
                                              to: previousMonth) else { return nil }
            let start = startDay.addingTimeInterval(timeOfDay)
            // A future start cannot belong to the cycle containing this reading.
            guard start <= observedAt else { continue }
            if let cycleStart, cycleStart != start { return nil }
            cycleStart = start
        }
        return cycleStart.map { resetAt.timeIntervalSince($0) }
    }
}
