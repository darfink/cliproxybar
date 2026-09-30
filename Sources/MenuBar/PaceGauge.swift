import SwiftUI
import CLIProxyBarCore

/// Shared gauge with explicit track and marker heights so neither overlaps captions.
struct PaceGauge: View {
    let percentage: Double
    let tint: Color
    let pace: QuotaPace?
    let displayMode: QuotaDisplayMode
    var trackHeight: CGFloat = 5

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.12)).frame(height: trackHeight)
                Capsule().fill(tint)
                    .frame(width: geometry.size.width * max(0, min(100, percentage)) / 100, height: trackHeight)
                ForEach(1..<4) { tick in
                    Rectangle().fill(Color.primary.opacity(0.16))
                        .frame(width: 1, height: trackHeight)
                        .offset(x: geometry.size.width * CGFloat(tick) / 4)
                }
                if let pace {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(pace.reservePoints >= 0 ? Color.green : Color.orange)
                        .frame(width: 3, height: trackHeight + 4)
                        .overlay(RoundedRectangle(cornerRadius: 1).stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1))
                        .offset(x: max(0, min(geometry.size.width - 3, geometry.size.width * pace.markerPercent(mode: displayMode) / 100)))
                }
            }
            .frame(height: trackHeight + 6)
        }
        .frame(height: trackHeight + 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Quota gauge")
        .accessibilityValue(percentage < 0 ? "No data" : "\(Int(percentage.rounded())) percent " + (displayMode == .used ? "used" : "remaining"))
    }
}
