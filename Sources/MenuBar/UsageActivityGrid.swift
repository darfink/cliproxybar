import AppKit
import SwiftUI

enum UsageActivityMeasure: String, CaseIterable {
    case tokens = "Tokens"
    case requests = "Requests"

    func value(for day: ProxyUsageDay) -> Int64 {
        self == .tokens ? day.tokens.total : day.requests
    }
}

struct UsageActivityScale {
    private let maximum: Int64
    private let thresholds: [Double]

    init(values: [Int64]) {
        let positive = values.filter { $0 > 0 }.sorted()
        maximum = positive.last ?? 0
        thresholds = [0.25, 0.5, 0.75].map { fraction in
            guard !positive.isEmpty else { return 0 }
            let position = Double(positive.count - 1) * fraction
            let lower = Int(position)
            let upper = min(lower + 1, positive.count - 1)
            let weight = position - Double(lower)
            return Double(positive[lower]) * (1 - weight) + Double(positive[upper]) * weight
        }
    }

    func level(for value: Int64) -> Int {
        guard value > 0, maximum > 0 else { return 0 }
        if value >= maximum { return 4 }
        return (thresholds.firstIndex { Double(value) <= $0 } ?? 3) + 1
    }

    static func opacity(for level: Int) -> Double {
        [0, 0.22, 0.46, 0.72, 1][min(4, max(0, level))]
    }
}

struct UsageActivityCalendar {
    enum Status { case upcoming, unrecorded, recorded }
    let calendar: Calendar
    let today: Date
    let start: Date
    let recordedStart: Date?
    let days: [Date: ProxyUsageDay]

    init(days: [ProxyUsageDay], startedAt: Date?, now: Date = Date(), calendar: Calendar = .current) {
        self.calendar = calendar
        today = calendar.startOfDay(for: now)
        let week = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        start = calendar.date(byAdding: .weekOfYear, value: -25, to: week)!
        recordedStart = startedAt.map { calendar.startOfDay(for: $0) }
        self.days = Dictionary(days.map { (calendar.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { _, last in last })
    }

    func date(week: Int, weekday: Int) -> Date {
        calendar.date(byAdding: .day, value: week * 7 + weekday, to: start)!
    }

    func status(on date: Date) -> Status {
        if date > today { return .upcoming }
        // A queue event can predate the time collection was first enabled.
        if days[date] != nil { return .recorded }
        return recordedStart.map { date >= $0 } == true ? .recorded : .unrecorded
    }

    func detail(on date: Date) -> String {
        switch status(on: date) {
        case .upcoming: return "Upcoming day"
        case .unrecorded: return "No recorded history"
        case .recorded:
            let day = days[date]
            var text = "\((day?.tokens.total ?? 0).formatted()) tokens · \((day?.requests ?? 0).formatted()) requests"
            if let failures = day?.failures, failures > 0 { text += " · \(failures) failed" }
            return text
        }
    }
}

struct ProxyUsageActivityGrid: View {
    let days: [ProxyUsageDay]
    let startedAt: Date?
    let tint: Color
    var interactive = true
    var now = Date()
    var calendar = Calendar.current
    @State private var hoveredDate: Date?
    @State private var measure = UsageActivityMeasure.tokens
    private let cellSize: CGFloat = 14
    private let spacing: CGFloat = 3
    private let labelWidth: CGFloat = 28
    private var activity: UsageActivityCalendar { UsageActivityCalendar(days: days, startedAt: startedAt, now: now, calendar: calendar) }
    private var gridWidth: CGFloat { cellSize * 26 + spacing * 25 }

    var body: some View {
        let data = activity
        let scale = UsageActivityScale(values: data.days.filter { $0.key >= data.start && $0.key <= data.today }
            .map { measure.value(for: $0.value) })
        let selection = hoveredDate ?? data.today
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Daily activity").font(.system(size: 11, weight: .semibold))
                Spacer()
                HStack(spacing: 1) {
                    ForEach(UsageActivityMeasure.allCases, id: \.self) { option in
                        Button { measure = option } label: {
                            Text(option.rawValue)
                                .font(.system(size: 10, weight: measure == option ? .semibold : .regular))
                                .foregroundStyle(measure == option ? Color.primary : Color.secondary)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(measure == option ? Color.secondary.opacity(0.14) : .clear,
                                            in: RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Color activity by " + option.rawValue.lowercased())
                        .accessibilityAddTraits(measure == option ? .isSelected : [])
                    }
                }
                .padding(2)
                .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                .help("One square is one day. Darker shades mean more " + measure.rawValue.lowercased() + ". Hover for exact totals.")
            }
            HStack(spacing: spacing) {
                Color.clear.frame(width: labelWidth, height: 12)
                ZStack(alignment: .topLeading) {
                    ForEach(0..<26, id: \.self) { week in
                        let date = data.date(week: week, weekday: 0)
                        if week == 0 || calendar.component(.month, from: date) != calendar.component(.month, from: data.date(week: week - 1, weekday: 0)) {
                            Text(date, format: .dateTime.month(.abbreviated))
                                .font(.system(size: 9)).foregroundStyle(.secondary).fixedSize()
                                .offset(x: CGFloat(week) * (cellSize + spacing))
                        }
                    }
                }.frame(width: gridWidth, height: 12, alignment: .leading)
            }
            HStack(alignment: .top, spacing: spacing) {
                VStack(spacing: spacing) {
                    ForEach(0..<7, id: \.self) { weekday in
                        Text(data.date(week: 0, weekday: weekday), format: .dateTime.weekday(.abbreviated))
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                            .frame(width: labelWidth, height: cellSize, alignment: .leading)
                    }
                }
                Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
                    ForEach(0..<7, id: \.self) { weekday in
                        GridRow {
                            ForEach(0..<26, id: \.self) { week in
                                let date = data.date(week: week, weekday: weekday)
                                cell(date, data: data, scale: scale)
                            }
                        }
                    }
                }
                .overlay {
                    if interactive {
                        ActivityGridPointerView(cellSize: cellSize, spacing: spacing) { index in
                            hoveredDate = index.map { data.date(week: $0.week, weekday: $0.weekday) }
                        }.allowsHitTesting(false)
                    }
                }
            }
            HStack(spacing: 10) {
                legend("Today", fill: tint.opacity(0.12), border: tint)
                legend("Upcoming", fill: .clear, border: .secondary.opacity(0.25), dashed: true)
                legend("No history", fill: .secondary.opacity(0.05))
                Spacer(minLength: 0)
                Text("Less").foregroundStyle(.tertiary)
                ForEach(1...4, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2).fill(tint.opacity(UsageActivityScale.opacity(for: level))).frame(width: 9, height: 9)
                }
                Text("More").foregroundStyle(.tertiary)
            }.font(.system(size: 9))
            HStack(spacing: 6) {
                Text(selection, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
                    .fontWeight(.medium)
                if selection == data.today { Text("Today").fontWeight(.semibold).foregroundStyle(tint) }
                Spacer(minLength: 4)
                Text(data.detail(on: selection)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(.system(size: 10)).monospacedDigit()
            .padding(.horizontal, 8).frame(height: 27)
            .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
            .accessibilityElement(children: .combine)
        }
    }

    private func cell(_ date: Date, data: UsageActivityCalendar, scale: UsageActivityScale) -> some View {
        let status = data.status(on: date)
        let today = date == data.today
        let selected = date == hoveredDate
        return RoundedRectangle(cornerRadius: 3)
            .fill(cellColor(data.days[date], status: status, scale: scale))
            .padding(today || selected ? 2 : 0)
            .overlay {
                RoundedRectangle(cornerRadius: 3).strokeBorder(
                    selected || today ? tint : status == .upcoming ? Color.secondary.opacity(0.25) : .clear,
                    style: StrokeStyle(lineWidth: selected || today ? 1.5 : 0.7, dash: status == .upcoming && !selected ? [2, 2] : []))
            }
            .frame(width: cellSize, height: cellSize)
            .help(date.formatted(date: .complete, time: .omitted) + ": " + data.detail(on: date))
            .accessibilityLabel((today ? "Today, " : "") + date.formatted(date: .complete, time: .omitted))
            .accessibilityValue(data.detail(on: date))
    }

    private func cellColor(_ day: ProxyUsageDay?, status: UsageActivityCalendar.Status, scale: UsageActivityScale) -> Color {
        switch status {
        case .upcoming: return .clear
        case .unrecorded: return .secondary.opacity(0.05)
        case .recorded:
            let level = scale.level(for: day.map { measure.value(for: $0) } ?? 0)
            return level == 0 ? .secondary.opacity(0.14) : tint.opacity(UsageActivityScale.opacity(for: level))
        }
    }

    private func legend(_ text: String, fill: Color, border: Color = .clear, dashed: Bool = false) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(fill)
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(border, style: StrokeStyle(lineWidth: 1, dash: dashed ? [2, 2] : [])))
                .frame(width: 9, height: 9)
            Text(text).foregroundStyle(.secondary)
        }
    }
}

// Menu tracking runs a dedicated run-loop mode. Sampling the pointer there
// keeps the inline day details responsive without waiting for a help tooltip.
private struct ActivityGridPointerView: NSViewRepresentable {
    let cellSize: CGFloat
    let spacing: CGFloat
    let changed: ((week: Int, weekday: Int)?) -> Void

    func makeNSView(context: Context) -> PointerView { PointerView() }
    func updateNSView(_ view: PointerView, context: Context) {
        view.cellSize = cellSize
        view.spacing = spacing
        view.changed = changed
    }
    static func dismantleNSView(_ view: PointerView, coordinator: ()) { view.stop() }

    final class PointerView: NSView {
        var cellSize: CGFloat = 14
        var spacing: CGFloat = 3
        var changed: (((week: Int, weekday: Int)?) -> Void)?
        private var timer: Timer?
        private var previous = -1
        override var isFlipped: Bool { true }
        func stop() {
            timer?.invalidate()
            timer = nil
        }
        override func viewDidMoveToWindow() {
            stop()
            guard window != nil else { return }
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.sample() }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
            RunLoop.main.add(timer, forMode: .eventTracking)
        }
        private func sample() {
            guard let window else { return }
            let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
            let week = Int(floor(point.x / (cellSize + spacing)))
            let weekday = Int(floor(point.y / (cellSize + spacing)))
            let inCell = bounds.contains(point) && (0..<26).contains(week) && (0..<7).contains(weekday)
                && point.x - CGFloat(week) * (cellSize + spacing) <= cellSize
                && point.y - CGFloat(weekday) * (cellSize + spacing) <= cellSize
            let index = inCell ? week * 7 + weekday : -1
            guard index != previous else { return }
            previous = index
            changed?(inCell ? (week, weekday) : nil)
        }
    }
}
