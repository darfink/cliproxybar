import SwiftUI
import CLIProxyBarCore

struct ProxyUsageDetailView: View {
    let usage: ProxyUsageSnapshot
    let provider: QuotaProvider
    let accountName: String
    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: Date()) }
    private var yesterday: Date { calendar.date(byAdding: .day, value: -1, to: today)! }
    private var monthStart: Date { calendar.date(byAdding: .day, value: -29, to: today)! }
    private var recentDays: [ProxyUsageDay] { usage.days.filter { $0.date >= monthStart } }
    private var monthTokens: ProxyUsageTokens { usage.totals(since: monthStart) }
    private var models: [(String, ProxyUsageModelTotals)] {
        var totals: [String: ProxyUsageModelTotals] = [:]
        for day in recentDays {
            for (name, model) in day.models {
                var total = totals[name] ?? ProxyUsageModelTotals()
                total.requests = ProxyUsageTokens.sum(total.requests, model.requests)
                total.tokens.add(model.tokens)
                totals[name] = total
            }
        }
        return totals.sorted {
            $0.value.tokens.total == $1.value.tokens.total ? $0.key < $1.key : $0.value.tokens.total > $1.value.tokens.total
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                ProviderIconMono(provider: provider, size: 15, tint: provider.color)
                Text("Proxy usage").font(.system(size: 14, weight: .bold)).foregroundStyle(provider.color)
                Spacer()
                if let success = usage.successCount {
                    Text("\(compact(success)) successful").foregroundStyle(.secondary)
                        .help("Current request counter reported by CLIProxyAPI. It can reset when the proxy restarts.")
                }
                if let failed = usage.failedCount, failed > 0 {
                    Text("\(compact(failed)) failed").foregroundStyle(.secondary)
                }
            }.font(.system(size: 10))
            Text(accountName).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)

            HStack(spacing: 0) {
                metric("Today", value: compact(usage.days.first { calendar.isDate($0.date, inSameDayAs: today) }?.tokens.total ?? 0))
                Divider().frame(height: 34)
                metric("Yesterday", value: compact(usage.days.first { calendar.isDate($0.date, inSameDayAs: yesterday) }?.tokens.total ?? 0),
                       available: usage.startedAt.map { calendar.startOfDay(for: $0) <= yesterday } ?? false)
                Divider().frame(height: 34)
                metric("Last 30 days", value: compact(monthTokens.total))
            }
            .padding(.vertical, 10)
            .background(provider.color.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 0) {
                metric("Input", value: compact(monthTokens.input), small: true)
                metric("Output", value: compact(monthTokens.output), small: true)
                metric("Cache reads", value: compact(monthTokens.cached), small: true)
                metric("Reasoning", value: compact(monthTokens.reasoning), small: true)
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

            ProxyUsageActivityGrid(days: usage.days, startedAt: usage.startedAt, tint: provider.color)

            if !models.isEmpty {
                HStack {
                    Text("Models · last 30 days").font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text("Tokens / requests").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                VStack(spacing: 6) {
                    ForEach(Array(models.prefix(4)), id: \.0) { name, total in
                        HStack(spacing: 10) {
                            Text(name).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 4)
                            Text(compact(total.tokens.total)).monospacedDigit().foregroundStyle(provider.color)
                            Text("/ \(compact(total.requests))").monospacedDigit().foregroundStyle(.secondary)
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
                Text("Local proxy traffic only · gaps while the app is closed or asleep")
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
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity)
    }

    private func compact(_ value: Int64) -> String {
        value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }
}

private struct ProxyUsageActivityGrid: View {
    let days: [ProxyUsageDay]
    let startedAt: Date?
    let tint: Color
    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: Date()) }
    private var start: Date {
        let week = calendar.dateInterval(of: .weekOfYear, for: today)!.start
        return calendar.date(byAdding: .day, value: -175, to: week)!
    }
    private var maximum: Double { Double(days.map(\.tokens.total).max() ?? 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Daily activity").font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("26 weeks").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                ForEach(0..<7, id: \.self) { weekday in
                    GridRow {
                        ForEach(0..<26, id: \.self) { week in
                            let date = calendar.date(byAdding: .day, value: week * 7 + weekday, to: start)!
                            let day = days.first { calendar.isDate($0.date, inSameDayAs: date) }
                            let recorded = startedAt.map { date >= calendar.startOfDay(for: $0) && date <= today } ?? false
                            RoundedRectangle(cornerRadius: 3)
                                .fill(cellColor(day, recorded: recorded))
                                .frame(width: 15, height: 15)
                                .help(date.formatted(date: .abbreviated, time: .omitted) + ": " +
                                    (recorded ? "\(day?.tokens.total ?? 0) tokens · \(day?.requests ?? 0) requests recorded" : "No recorded history"))
                                .accessibilityLabel(date.formatted(date: .abbreviated, time: .omitted))
                                .accessibilityValue(recorded ? "\(day?.tokens.total ?? 0) tokens recorded" : "No recorded history")
                        }
                    }
                }
            }
        }
    }

    private func cellColor(_ day: ProxyUsageDay?, recorded: Bool) -> Color {
        guard recorded else { return Color.secondary.opacity(0.06) }
        guard let day, day.requests > 0 else { return Color.secondary.opacity(0.14) }
        let intensity = maximum > 0 ? log1p(Double(day.tokens.total)) / log1p(maximum) : 0
        return tint.opacity(0.25 + 0.75 * intensity)
    }
}
