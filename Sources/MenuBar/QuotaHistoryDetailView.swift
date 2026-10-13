import SwiftUI
import Charts
import AppKit
import Observation
import CLIProxyBarCore

enum QuotaHistoryRange: String, CaseIterable, Identifiable {
    case fiveHours = "5h", day = "24h", week = "7d", month = "30d"
    var id: String { rawValue }
    var duration: TimeInterval {
        switch self {
        case .fiveHours: 18000
        case .day: 86400
        case .week: 7 * 86400
        case .month: 30 * 86400
        }
    }
}

struct QuotaHistoryPlotPoint: Identifiable {
    let point: QuotaHistoryPoint
    let segment: Int
    var id: Date { point.date }

    static func plot(_ points: [QuotaHistoryPoint], start: Date, end: Date) -> [Self] {
        let visible = points.filter { $0.date >= start && $0.date <= end }
        var result: [Self] = []
        var segment = 0
        for (index, point) in visible.enumerated() {
            if index > 0, point.date.timeIntervalSince(visible[index - 1].date) > 900 { segment += 1 }
            result.append(Self(point: point, segment: segment))
        }
        // Preserve extremes and the edges of each gap while limiting chart work.
        guard result.count > 600 else { return result }
        let bucketSize = Int(ceil(Double(result.count) / 150))
        var kept = Set([0, result.count - 1])
        for index in 1..<result.count where result[index].segment != result[index - 1].segment {
            kept.insert(index - 1); kept.insert(index)
        }
        for start in stride(from: 0, to: result.count, by: bucketSize) {
            let indices = Array(start..<min(start + bucketSize, result.count))
            if let minIndex = indices.min(by: { result[$0].point.usedPercent < result[$1].point.usedPercent }) { kept.insert(minIndex) }
            if let maxIndex = indices.max(by: { result[$0].point.usedPercent < result[$1].point.usedPercent }) { kept.insert(maxIndex) }
            kept.insert(indices.last!)
        }
        return kept.sorted().map { result[$0] }
    }

    static func nearest(_ date: Date, in points: [QuotaHistoryPoint]) -> QuotaHistoryPoint? {
        var lower = 0
        var upper = points.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if points[middle].date < date { lower = middle + 1 } else { upper = middle }
        }
        let indices = [lower - 1, lower].filter { points.indices.contains($0) }
        guard let point = indices.map({ points[$0] }).min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }), abs(point.date.timeIntervalSince(date)) <= 900 else { return nil }
        return point
    }
}

struct QuotaHistoryChartSeries: Identifiable {
    let id: String
    let title: String
    let colorIndex: Int
    let points: [QuotaHistoryPoint]
    let plot: [QuotaHistoryPlotPoint]
    let reading: QuotaHistoryPoint?
    let isolatedDates: Set<Date>

    func lineID(segment: Int) -> String { id + ":" + String(segment) }

    static func project(_ history: QuotaHistorySnapshot, start: Date, end: Date,
                        hoveredDate: Date? = nil) -> [Self] {
        let identifiers = history.series.map(\.id).sorted()
        return history.series.map { series in
            let points = series.points.filter { $0.date >= start && $0.date <= end }
            let plot = QuotaHistoryPlotPoint.plot(points, start: start, end: end)
            let segments = Dictionary(grouping: plot, by: \.segment)
            let isolated = Set(segments.values.filter { $0.count == 1 }.map { $0[0].point.date })
            return Self(id: series.id, title: series.title, colorIndex: identifiers.firstIndex(of: series.id) ?? 0,
                points: points, plot: plot,
                reading: hoveredDate == nil ? points.last : hoveredDate.flatMap { QuotaHistoryPlotPoint.nearest($0, in: points) },
                isolatedDates: isolated)
        }
    }
}

struct QuotaHistoryDetailView: View {
    let history: QuotaHistorySnapshot
    let provider: QuotaProvider
    var now: Date = .now
    var interactive = true
    var expandsChart = false
    @State private var range = QuotaHistoryRange.day
    @State private var hoveredDate: Date?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let start = now.addingTimeInterval(-range.duration)
        let series = QuotaHistoryChartSeries.project(history, start: start, end: now, hoveredDate: hoveredDate)
        let count = series.reduce(0) { $0 + $1.points.count }
        let readings = series.compactMap(\.reading)
        let timestamp = hoveredDate.flatMap { date in
            readings.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }?.date
        } ?? readings.map(\.date).max()
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Quota usage over time").font(.system(size: 11, weight: .semibold))
                Spacer()
                if let timestamp {
                    Text(timestamp.formatted(date: range == .fiveHours || range == .day ? .omitted : .abbreviated,
                        time: .shortened)).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 4) {
                ForEach(QuotaHistoryRange.allCases) { choice in
                    Button { range = choice; hoveredDate = nil } label: {
                        Text(choice.rawValue).font(.system(size: 11, weight: range == choice ? .semibold : .regular))
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                            .background(range == choice ? provider.color.opacity(0.14) : Color.secondary.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(HistoryChoiceButtonStyle()).disabled(!interactive)
                }
            }
            Chart {
                ForEach(series) { window in
                    ForEach(window.plot) { value in
                        LineMark(x: .value("Time", value.point.date), y: .value("Used", value.point.usedPercent),
                            series: .value("Window segment", window.lineID(segment: value.segment)))
                            .interpolationMethod(.linear).foregroundStyle(seriesColor(window.colorIndex))
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        if window.isolatedDates.contains(value.point.date) {
                            PointMark(x: .value("Time", value.point.date), y: .value("Used", value.point.usedPercent))
                                .foregroundStyle(seriesColor(window.colorIndex)).symbolSize(12)
                        }
                    }
                    if let reading = window.reading {
                        PointMark(x: .value("Time", reading.date), y: .value("Used", reading.usedPercent))
                            .foregroundStyle(seriesColor(window.colorIndex)).symbolSize(30)
                    }
                }
                if hoveredDate != nil, let timestamp {
                    RuleMark(x: .value("Time", timestamp)).foregroundStyle(Color.secondary.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartXScale(domain: start...now).chartYScale(domain: 0...100)
            .chartYAxis { AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine().foregroundStyle(Color.secondary.opacity(0.12))
                AxisValueLabel { if let percent = value.as(Int.self) { Text("\(percent)%").font(.system(size: 9)) } }
            } }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5, roundLowerBound: false, roundUpperBound: false)) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(anchor: value.index == 0 ? .topLeading : value.index == value.count - 1 ? .topTrailing : .top,
                        collisionResolution: .greedy)
                }
            }
            .chartLegend(.hidden)
            .chartOverlay { proxy in GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle()).onContinuousHover { phase in
                    guard interactive else { return }
                    switch phase {
                    case .active(let location):
                        guard let frame = proxy.plotFrame, geometry[frame].contains(location) else { hoveredDate = nil; return }
                        hoveredDate = proxy.value(atX: location.x - geometry[frame].minX, as: Date.self)
                    case .ended: hoveredDate = nil
                    }
                }
            } }
            .frame(minHeight: 215, idealHeight: 215, maxHeight: expandsChart ? .infinity : 215)
            FlowLayout(spacing: 12) {
                ForEach(series) { window in
                    HStack(spacing: 5) {
                        Circle().fill(seriesColor(window.colorIndex)).frame(width: 6, height: 6)
                        Text(window.title).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                        Text(percentage(window.reading)).fontWeight(.semibold).monospacedDigit()
                            .foregroundStyle(seriesColor(window.colorIndex)).fixedSize()
                    }.font(.system(size: 11)).frame(maxWidth: 240, alignment: .leading)
                        .help(window.title).accessibilityElement(children: .combine)
                }
            }
            if count == 0 {
                Text(history.recordingEnabled ? "History starts with fresh quota readings. Earlier usage cannot be recovered." : "Enable Record quota history in Settings (⌘,) to record readings.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                Text(series.allSatisfy { $0.points.count <= 1 }
                    ? "First readings recorded · trends appear after the next refresh"
                    : "\(count) observations · gaps show periods without observations")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Text(history.issue ?? (history.recordingEnabled ? "Recorded at quota refreshes · up to 30 days saved locally" : "Recording paused · saved history retained"))
                .font(.system(size: 10)).foregroundStyle(history.issue == nil ? Color.secondary : .orange)
        }.padding(14)
    }

    private func percentage(_ point: QuotaHistoryPoint?) -> String {
        point.map { $0.usedPercent.formatted(.number.precision(.fractionLength(0...1))) + "%" } ?? "—"
    }

    private func seriesColor(_ index: Int) -> Color {
        guard index > 0 else { return provider.color }
        guard let rgb = NSColor(provider.color).usingColorSpace(.deviceRGB) else { return .blue }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let shifted = (Double(hue) + Double(index) * 0.381966).truncatingRemainder(dividingBy: 1)
        return Color(hue: shifted, saturation: colorScheme == .dark ? 0.65 : 0.8,
            brightness: colorScheme == .dark ? 0.90 : 0.68)
    }
}

enum AccountHistoryTab: String {
    case quota, tokens
    static let preferenceKey = "accountHistoryTab"

    static func preferred(in defaults: UserDefaults) -> Self {
        defaults.string(forKey: preferenceKey).flatMap(Self.init(rawValue:)) ?? .tokens
    }
}

@MainActor
@Observable
final class AccountHistorySelection {
    var tab: AccountHistoryTab

    init(_ tab: AccountHistoryTab) { self.tab = tab }
}

struct AccountDetailView: View {
    let usage: ProxyUsageSnapshot
    let quotaHistory: QuotaHistorySnapshot?
    let provider: QuotaProvider
    private let selection: AccountHistorySelection
    private let onSelectTab: (AccountHistoryTab) -> Void

    init(usage: ProxyUsageSnapshot, quotaHistory: QuotaHistorySnapshot?, provider: QuotaProvider,
         defaults: UserDefaults = .standard, tab: AccountHistoryTab? = nil,
         selection: AccountHistorySelection? = nil,
         onSelectTab: @escaping (AccountHistoryTab) -> Void = { _ in }) {
        self.usage = usage
        self.quotaHistory = quotaHistory
        self.provider = provider
        self.selection = selection ?? AccountHistorySelection(tab ?? AccountHistoryTab.preferred(in: defaults))
        self.onSelectTab = onSelectTab
    }

    var selectedTab: AccountHistoryTab {
        quotaHistory?.series.isEmpty == false ? selection.tab : .tokens
    }

    var body: some View {
        if let history = quotaHistory, !history.series.isEmpty {
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    tab("Token history", selected: selectedTab == .tokens) { onSelectTab(.tokens) }
                    tab("Quota history", selected: selectedTab == .quota) { onSelectTab(.quota) }
                }.padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)
                // Both panels stay mounted. The larger panel sets the shared
                // height, so changing tabs cannot move the header or menu.
                ZStack(alignment: .topLeading) {
                    ProxyUsageDetailView(usage: usage, provider: provider)
                        .opacity(selectedTab == .tokens ? 1 : 0)
                        .allowsHitTesting(selectedTab == .tokens)
                        .accessibilityHidden(selectedTab != .tokens)
                    QuotaHistoryDetailView(history: history, provider: provider, expandsChart: true)
                        .opacity(selectedTab == .quota ? 1 : 0)
                        .allowsHitTesting(selectedTab == .quota)
                        .accessibilityHidden(selectedTab != .quota)
                }
            }
        } else { ProxyUsageDetailView(usage: usage, provider: provider) }
    }

    private func tab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: selected ? .semibold : .regular))
                .frame(maxWidth: .infinity).padding(.vertical, 6)
                .background(selected ? provider.color.opacity(0.14) : Color.secondary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(HistoryChoiceButtonStyle())
    }
}

private struct HistoryChoiceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { HoverLabel(configuration: configuration) }

    private struct HoverLabel: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovered = false

        var body: some View {
            configuration.label
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(isEnabled ? (configuration.isPressed ? 0.10 : hovered ? 0.06 : 0) : 0)))
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .onHover { hovered = $0 }
        }
    }
}
