import SwiftUI
import CLIProxyBarCore

struct PaceQuotaRow: View {
    let metric: QuotaMetric
    let provider: QuotaProvider
    let displayMode: QuotaDisplayMode
    let observedAt: Date
    let hasRefreshIssue: Bool

    var body: some View {
        let pace = hasRefreshIssue ? nil : QuotaPace.calculate(metric: metric, observedAt: observedAt)
        let percent = displayMode.displayValue(from: metric.percentage)
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(metric.displayName + " " + (percent < 0 ? "—" : "\(Int(percent.rounded()))%") + (displayMode == .used ? " used" : " left"))
                    .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 5)
                if !metric.resetTime.isEmpty {
                    Text("Resets in " + metric.formattedResetTime)
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            PaceGauge(percentage: percent, tint: provider.color, pace: pace, displayMode: displayMode)
            if let pace {
                Text(summary(pace)).font(.system(size: 10)).foregroundStyle(.secondary)
                    .help("The marker shows an even-use budget at the observation time. Reserve/deficit is the difference in percentage points. Exhaustion is estimated from average usage since the window started, not recent activity.")
            } else if metric.windowDuration != nil {
                Text("Pace unavailable").font(.system(size: 10)).foregroundStyle(.tertiary)
                    .help("Pace requires a known window duration, a future reset, and a successful reading from the last 15 minutes.")
            }
        }
        .padding(.vertical, 1)
    }

    private func summary(_ pace: QuotaPace) -> String {
        let difference = Int(abs(pace.reservePoints).rounded())
        let balance = difference == 0 ? "On pace" : "\(difference)% " + (pace.reservePoints > 0 ? "in reserve" : "in deficit")
        if pace.lastsUntilReset { return balance + " · Est. lasts until reset" }
        guard let time = pace.timeUntilExhaustion else { return balance }
        return balance + (time <= 0 ? " · Exhausted at this pace" : " · Est. runs out in " + duration(time))
    }

    private func duration(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int(interval / 60))
        if minutes >= 1440 { return "\(minutes / 1440)d \((minutes % 1440) / 60)h" }
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes)m"
    }
}
