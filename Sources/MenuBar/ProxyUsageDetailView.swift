import SwiftUI
import CLIProxyBarCore

struct ProxyUsageSummary {
    let today: Date
    let yesterday: Date
    let days: [ProxyUsageDay]
    let calendar: Calendar

    init(usage: ProxyUsageSnapshot, now: Date = Date(), calendar: Calendar = .current) {
        self.calendar = calendar
        let today = calendar.startOfDay(for: now)
        self.today = today
        yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let start = calendar.date(byAdding: .day, value: -29, to: today)!
        days = usage.days.filter { $0.date >= start && $0.date <= today }
    }

    var tokens: ProxyUsageTokens {
        days.reduce(into: ProxyUsageTokens()) { $0.add($1.tokens) }
    }

    func value(on date: Date? = nil, measure: UsageActivityMeasure) -> Int64 {
        days.filter { day in date.map { calendar.isDate(day.date, inSameDayAs: $0) } ?? true }
            .reduce(0) { ProxyUsageTokens.sum($0, measure.value(for: $1)) }
    }

    func models(measure: UsageActivityMeasure) -> [(String, ProxyUsageModelTotals)] {
        var totals: [String: ProxyUsageModelTotals] = [:]
        for day in days {
            for (name, model) in day.models {
                var total = totals[name] ?? ProxyUsageModelTotals()
                total.requests = ProxyUsageTokens.sum(total.requests, model.requests)
                total.tokens.add(model.tokens)
                totals[name] = total
            }
        }
        return totals.sorted {
            let left = measure.value(for: $0.value)
            let right = measure.value(for: $1.value)
            return left == right ? $0.key < $1.key : left > right
        }
    }
}

struct ProxyUsageDetailView: View {
    let usage: ProxyUsageSnapshot
    let provider: QuotaProvider
    let interactive: Bool
    let now: Date
    let calendar: Calendar
    @State private var measure: UsageActivityMeasure

    init(usage: ProxyUsageSnapshot, provider: QuotaProvider, interactive: Bool = true,
         now: Date = Date(), calendar: Calendar = .current, initialMeasure: UsageActivityMeasure = .tokens) {
        self.usage = usage
        self.provider = provider
        self.interactive = interactive
        self.now = now
        self.calendar = calendar
        _measure = State(initialValue: initialMeasure)
    }

    var body: some View {
        let summary = ProxyUsageSummary(usage: usage, now: now, calendar: calendar)
        let monthTokens = summary.tokens
        let models = summary.models(measure: measure)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                metric("Today", value: compact(summary.value(on: summary.today, measure: measure)))
                Divider().frame(height: 34)
                metric("Yesterday", value: compact(summary.value(on: summary.yesterday, measure: measure)),
                       available: usage.startedAt.map { calendar.startOfDay(for: $0) <= summary.yesterday } ?? false)
                Divider().frame(height: 34)
                metric("Last 30 days", value: compact(summary.value(measure: measure)))
            }
            .padding(.vertical, 10)
            .background(provider.color.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityValue(measure.rawValue)

            VStack(alignment: .leading, spacing: 7) {
                Text("Tokens · last 30 days").font(.system(size: 10)).foregroundStyle(.secondary)
                HStack(spacing: 0) {
                    metric("Input", value: compact(monthTokens.input), small: true)
                    metric("Output", value: compact(monthTokens.output), small: true)
                    metric("Cache reads", value: compact(monthTokens.cached), small: true)
                    metric("Reasoning", value: compact(monthTokens.reasoning), small: true)
                }
            }
            .help("Token breakdown for the last 30 days. Cache and reasoning counts are subsets where the provider reports them. They are not added to the total again.")
            if monthTokens.cacheWrite > 0 {
                Text("Cache writes: \(compact(monthTokens.cacheWrite)) tokens")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }

            if usage.days.isEmpty {
                Text(usage.trackingEnabled ? "Waiting for requests through this proxy…" : "Enable Collect token usage in Settings (⌘,) to start a history.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }

            ProxyUsageActivityGrid(days: usage.days, startedAt: usage.startedAt, tint: provider.color,
                measure: $measure, interactive: interactive, now: now, calendar: calendar)

            if !models.isEmpty {
                HStack {
                    Text("Models · last 30 days").font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text(measure.rawValue).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                VStack(spacing: 6) {
                    ForEach(Array(models.prefix(4)), id: \.0) { name, total in
                        HStack(spacing: 10) {
                            Text(name).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 4)
                            Text(compact(measure.value(for: total))).monospacedDigit().foregroundStyle(provider.color)
                        }.font(.system(size: 11))
                    }
                }
            }

            Divider()
            VStack(alignment: .leading, spacing: 3) {
                if let issue = usage.issue {
                    Text(issue).foregroundStyle(.orange)
                } else if !usage.trackingEnabled {
                    Text("Collection paused").foregroundStyle(.secondary)
                } else if let last = usage.lastCollectedAt {
                    Text("Collection active · checked \(last, style: .relative) ago").foregroundStyle(.secondary)
                } else {
                    Text("Starting collection…").foregroundStyle(.secondary)
                }
                if let start = usage.startedAt {
                    Text("Recorded since \(start.formatted(date: .abbreviated, time: .shortened))")
                        .foregroundStyle(.tertiary)
                }
                Text("Traffic through this proxy · gaps while the app is closed or asleep")
                    .foregroundStyle(.tertiary)
            }.font(.system(size: 10))
        }
        .padding(14)
    }

    private func metric(_ title: String, value: String, small: Bool = false, available: Bool = true) -> some View {
        VStack(spacing: 4) {
            Text(usage.startedAt == nil || !available ? "—" : value)
                .font(.system(size: small ? 14 : 19, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(small ? title : title + " · " + measure.rawValue.lowercased())
                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity)
    }

    private func compact(_ value: Int64) -> String {
        value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }
}
