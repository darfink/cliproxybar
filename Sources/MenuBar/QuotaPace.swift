import Foundation
import CLIProxyBarCore

/// Window-average projection, not a measurement of recent request throughput.
struct QuotaPace: Equatable {
    let expectedUsedPercent: Double
    let reservePoints: Double
    let timeUntilReset: TimeInterval
    let timeUntilExhaustion: TimeInterval?

    var lastsUntilReset: Bool {
        timeUntilExhaustion.map { $0 >= timeUntilReset } ?? true
    }

    static func calculate(metric: QuotaMetric, observedAt: Date, now: Date = Date()) -> QuotaPace? {
        guard let duration = metric.windowDuration, duration.isFinite, duration > 0,
              metric.percentage.isFinite, (0...100).contains(metric.percentage),
              now.timeIntervalSince(observedAt) >= -60, now.timeIntervalSince(observedAt) <= 900 else { return nil }
        let reset = ProxyAccount.observationDate(metric.resetTime)
        guard reset > now else { return nil }
        let elapsed = duration - reset.timeIntervalSince(observedAt)
        guard elapsed > 0, elapsed <= duration else { return nil }
        let used = 100 - metric.percentage
        let expected = elapsed / duration * 100
        let exhaustionAt = used > 0 ? observedAt.addingTimeInterval(elapsed * metric.percentage / used) : nil
        return QuotaPace(expectedUsedPercent: expected, reservePoints: expected - used,
                         timeUntilReset: reset.timeIntervalSince(now),
                         timeUntilExhaustion: exhaustionAt.map { max(0, $0.timeIntervalSince(now)) })
    }

    func markerPercent(mode: QuotaDisplayMode) -> Double {
        mode == .used ? expectedUsedPercent : 100 - expectedUsedPercent
    }
}
