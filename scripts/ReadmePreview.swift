import AppKit
import SwiftUI
import CLIProxyBarCore

@main
struct ReadmePreview {
    @MainActor static func main() throws {
        guard let path = ProcessInfo.processInfo.environment["CLIPROXYBAR_README_SCREENSHOTS"] else {
            throw NSError(domain: "ReadmePreview", code: 1, userInfo: [NSLocalizedDescriptionKey: "Set CLIPROXYBAR_README_SCREENSHOTS"])
        }
        _ = NSApplication.shared
        let destination = URL(fileURLWithPath: path, isDirectory: true)
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -79, to: today)!
        var days: [ProxyUsageDay] = []
        for offset in 0..<80 {
            let date = calendar.date(byAdding: .day, value: -offset, to: today)!
            let requests = Int64(offset % 9 == 4 ? 0 : (offset * 17 + 11) % 19 + 2)
            let total = requests * Int64(47000 + (offset * 7139) % 42000)
            let output = total / 19
            let input = total - output
            let tokens = ProxyUsageTokens(input: input, output: output, cached: input * 7 / 10,
                cacheWrite: input / 23, reasoning: output / 4, total: total)
            let firstTokens = ProxyUsageTokens(input: input * 2 / 3, output: output * 2 / 3,
                cached: tokens.cached * 2 / 3, cacheWrite: tokens.cacheWrite * 2 / 3,
                reasoning: tokens.reasoning * 2 / 3, total: total * 2 / 3)
            let secondTokens = ProxyUsageTokens(input: input - firstTokens.input, output: output - firstTokens.output,
                cached: tokens.cached - firstTokens.cached, cacheWrite: tokens.cacheWrite - firstTokens.cacheWrite,
                reasoning: tokens.reasoning - firstTokens.reasoning, total: total - firstTokens.total)
            days.append(ProxyUsageDay(date: date, requests: requests, tokens: tokens, models: [
                "claude-opus-4-6": ProxyUsageModelTotals(requests: requests * 2 / 3, tokens: firstTokens),
                "claude-sonnet-4-6": ProxyUsageModelTotals(requests: requests - requests * 2 / 3, tokens: secondTokens)
            ]))
        }
        let usage = ProxyUsageSnapshot(days: days, startedAt: start, trackingEnabled: true,
            lastCollectedAt: now.addingTimeInterval(-18), successCount: days.reduce(0) { $0 + $1.requests }, failedCount: 0)

        let history = quotaHistory(endingAt: now)
        let observed = now.addingTimeInterval(-180)
        func metric(_ name: String, remaining: Double, reset: TimeInterval? = nil, duration: TimeInterval? = nil) -> QuotaMetric {
            QuotaMetric(name: name, percentage: remaining,
                resetTime: reset.map { ISO8601DateFormatter().string(from: now.addingTimeInterval($0)) } ?? "", windowDuration: duration)
        }
        func account(_ provider: QuotaProvider, name: String, metrics: [QuotaMetric], plan: String? = nil,
                     resets: Int? = nil) -> StatusBarMenuAccountSnapshot {
            StatusBarMenuAccountSnapshot(id: QuotaAccountID(provider: provider, accountKey: name), email: name,
                quota: ProviderQuota(models: metrics, lastUpdated: observed, planType: plan, availableResetCredits: resets),
                subscription: nil, isActiveInIDE: false, isRefreshing: false, isRefreshBlocked: false, proxyUsage: usage, quotaHistory: provider == .claude ? history : nil)
        }
        let providers = [
            StatusBarMenuProviderSnapshot(provider: .claude, accounts: [
                account(.claude, name: "work@example.com", metrics: [
                    metric("five-hour-session", remaining: 58, reset: 5400, duration: 18000),
                    metric("seven-day-weekly", remaining: 64, reset: 345600, duration: 604800)], plan: "pro"),
                account(.claude, name: "personal@example.com", metrics: [
                    metric("five-hour-session", remaining: 0, reset: 4500, duration: 18000),
                    metric("seven-day-weekly", remaining: 78, reset: 172800, duration: 604800)], plan: "max_5x")
            ], isRefreshing: false, supportsScopedRefresh: true),
            StatusBarMenuProviderSnapshot(provider: .codex, accounts: [
                account(.codex, name: "work@example.com", metrics: [
                    metric("codex-weekly", remaining: 45, reset: 417600, duration: 604800)], plan: "self_serve_business_prolite", resets: 2)
            ], isRefreshing: false, supportsScopedRefresh: true),
            StatusBarMenuProviderSnapshot(provider: .opencodeGo, accounts: [
                account(.opencodeGo, name: "Personal", metrics: [
                    metric("opencode-go-rolling", remaining: 83, reset: 7200, duration: 18000),
                    metric("opencode-go-weekly", remaining: 35, reset: 248400, duration: 604800),
                    metric("opencode-go-monthly", remaining: 68, reset: 20 * 86400, duration: 31 * 86400)], plan: "Go Lite")
            ], isRefreshing: false, supportsScopedRefresh: true)
        ]
        let commands = StatusBarCommandDispatcher(handlers: StatusBarCommandHandlers(refreshAll: {}, refreshProvider: { _ in },
            refreshAccount: { _ in }, toggleProxy: {}, toggleTunnel: { _ in }, copyText: { _ in },
            switchAntigravityAccount: { _ in }, isAntigravityIDERunning: { false }, confirmAntigravitySwitch: { _, _ in false },
            selectProvider: { _ in }, settings: {}, openApp: {}, quit: {}, menuNeedsRebuild: {}))
        for scheme in [ColorScheme.light, .dark] {
            let appearance = scheme == .light ? AppearanceMode.light : .dark
            NSApp.appearance = appearance.appKitAppearance
            let variant = scheme == .light ? "" : "-dark"
            let snapshot = StatusBarMenuSnapshot(connectionMessage: "Connected", isLocalProxyMode: true, proxyPort: 8317,
                isProxyRunning: true, tunnel: CloudflareTunnelSnapshot(), providers: providers, selectedProvider: nil,
                isLoadingQuotas: false, displaySettings: StatusBarMenuDisplaySettings(quotaDisplayMode: .used,
                    quotaDisplayStyle: .lowestBar, hideSensitiveInfo: false, modelAggregationMode: .lowest, showsResetCountdownInCompactMenu: true),
                appearanceMode: appearance, language: .english, proxyAddress: "127.0.0.1:8317")
            for expanded in [false, true] {
                let menu = StatusBarMenuRenderer(snapshot: snapshot, commands: commands, expanded: expanded).buildMenu()
                let width: CGFloat = expanded ? 360 : 280
                var rendered: [(CGImage?, CGFloat, Bool)] = []
                for item in menu.items where !item.isHidden {
                    if item.isSeparatorItem { rendered.append((nil, 9, true)); continue }
                    guard let view = item.view else { continue }
                    let image = try capture(view, appearance: appearance.appKitAppearance)
                    rendered.append((image, view.frame.height, false))
                }
                let height = rendered.reduce(CGFloat(8)) { $0 + $1.1 }
                let output = try canvas(width: width, height: height, scheme: scheme) { context in
                    var y: CGFloat = 4
                    for (image, itemHeight, separator) in rendered {
                        if separator {
                            context.setStrokeColor(NSColor(white: scheme == .light ? 0 : 1, alpha: 0.13).cgColor)
                            context.setLineWidth(0.5)
                            context.move(to: CGPoint(x: 12, y: height - y - 4.5))
                            context.addLine(to: CGPoint(x: width - 12, y: height - y - 4.5))
                            context.strokePath()
                        } else if let image {
                            context.draw(image, in: CGRect(x: 0, y: height - y - itemHeight, width: width, height: itemHeight))
                        }
                        y += itemHeight
                    }
                }
                try write(output, to: destination.appendingPathComponent((expanded ? "expanded" : "compact") + variant + ".png"))
            }

            let suite = "ReadmeScreenshots." + UUID().uuidString
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            for tab in [AccountHistoryTab.tokens, .quota] {
                let view = NSHostingView(rootView: AccountDetailView(usage: usage, quotaHistory: history,
                    provider: .claude, defaults: defaults, tab: tab).frame(width: 520).fixedSize(horizontal: false, vertical: true)
                    .environment(\.colorScheme, scheme).environment(\.locale, Locale(identifier: "en")))
                view.setFrameSize(view.intrinsicContentSize)
                let content = try capture(view, appearance: appearance.appKitAppearance)
                let image = try canvas(width: 520, height: view.frame.height, scheme: scheme) { context in
                    context.draw(content, in: CGRect(origin: .zero, size: view.frame.size))
                }
                try write(image, to: destination.appendingPathComponent((tab == .quota ? "quota-history" : "usage") + variant + ".png"))
            }
        }
        print("Rendered eight previews with fictional accounts and activity.")
    }

    private static func quotaHistory(endingAt now: Date) -> QuotaHistorySnapshot {
        // Fictional work periods increase at different rates, with quiet time
        // between them. Only session resets produce abrupt drops.
        let sessions: [(start: Double, work: [(start: Double, duration: Double, amount: Double)])] = [
            (-1.5, [(-1.4, 1.5, 10), (0.4, 1.2, 21), (2.0, 1.0, 16)]),
            (4.25, [(4.4, 0.6, 6), (5.5, 1.8, 24), (7.8, 0.7, 11)]),
            (20.5, [(20.5, 1.0, 8), (21.8, 1.4, 27), (23.3, 0.7, 7)])
        ]
        func consumption(_ work: [(start: Double, duration: Double, amount: Double)], at hour: Double) -> Double {
            work.reduce(0) { used, period in
                let progress = min(1, max(0, (hour - period.start) / period.duration))
                return used + period.amount * progress * progress * (3 - 2 * progress)
            }
        }
        let work = sessions.flatMap(\.work)
        let baseline = consumption(work, at: 0)
        let total = consumption(work, at: 24) - baseline
        let start = now.addingTimeInterval(-86400)
        var session: [QuotaHistoryPoint] = []
        var weekly: [QuotaHistoryPoint] = []
        for index in 0...288 {
            let hour = Double(index) / 12
            let date = start.addingTimeInterval(Double(index * 300))
            let active = sessions.first { hour >= $0.start && hour < $0.start + 5 }
            session.append(QuotaHistoryPoint(date: date, usedPercent: active.map { consumption($0.work, at: hour) } ?? 0))
            weekly.append(QuotaHistoryPoint(date: date, usedPercent: 22 + 14 * (consumption(work, at: hour) - baseline) / total))
        }
        // End at the same 42% session and 36% weekly usage as the sample account.
        return QuotaHistorySnapshot(series: [
            QuotaHistorySeries(id: "five-hour-session", title: "Session", points: session),
            QuotaHistorySeries(id: "seven-day-weekly", title: "Weekly", points: weekly)
        ])
    }

    @MainActor private static func capture(_ view: NSView, appearance: NSAppearance?) throws -> CGImage {
        view.appearance = appearance
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: view.frame.width, height: view.frame.height),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView?.addSubview(view)
        defer { view.removeFromSuperview(); window.orderOut(nil) }
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        view.layoutSubtreeIfNeeded()
        let bitmap = try previewUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return try previewUnwrap(bitmap.cgImage)
    }

    @MainActor private static func canvas(width: CGFloat, height: CGFloat, scheme: ColorScheme,
                                 draw: (CGContext) -> Void) throws -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: Int(width * 2), height: Int(height * 2), bitsPerComponent: 8,
            bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: 2, y: 2)
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        let path = CGPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 12, cornerHeight: 12, transform: nil)
        context.addPath(path)
        context.clip()
        context.setFillColor(NSColor(white: scheme == .light ? 0.975 : 0.125, alpha: 1).cgColor)
        context.fill(rect)
        draw(context)
        context.resetClip()
        context.addPath(path)
        context.setStrokeColor(NSColor(white: scheme == .light ? 0 : 1, alpha: 0.18).cgColor)
        context.setLineWidth(0.5)
        context.strokePath()
        return context.makeImage()!
    }

    private static func write(_ image: CGImage, to url: URL) throws {
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
        try png.write(to: url)
    }
}

private func previewUnwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw NSError(domain: "ReadmePreview", code: 2) }
    return value
}
