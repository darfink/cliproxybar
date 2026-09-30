import SwiftUI
import CLIProxyBarCore
public extension String {
    /// Masks sensitive information with asterisks (*)
    /// Email: `john.doe@gmail.com` → `********@*****.com`
    /// Other: `account-name` → `************`
    func masked() -> String {
        // Check if it's an email
        if self.contains("@") {
            let components = self.split(separator: "@", maxSplits: 1)
            if components.count == 2 {
                let localPart = String(repeating: "*", count: min(components[0].count, 8))
                let domainParts = components[1].split(separator: ".", maxSplits: 1)
                if domainParts.count == 2 {
                    let domainName = String(repeating: "*", count: min(domainParts[0].count, 5))
                    return "\(localPart)@\(domainName).\(domainParts[1])"
                }
                return "\(localPart)@\(String(repeating: "*", count: 5))"
            }
        }
        
        // For non-email strings, mask entirely but keep reasonable length
        let maskedLength = min(self.count, 12)
        return String(repeating: "*", count: max(maskedLength, 4))
    }
    
    /// Conditionally masks the string based on a flag
    func masked(if shouldMask: Bool) -> String {
        shouldMask ? masked() : self
    }
}

public struct MenuBarQuotaMetric: Equatable, Sendable {
    public let labelKey: String
    public let remainingPercentage: Double

    public init(labelKey: String, remainingPercentage: Double) {
        self.labelKey = labelKey
        self.remainingPercentage = remainingPercentage
    }
}

/// Two related quota metrics rendered together in the compact menu bar layout.
public struct MenuBarQuotaPair: Equatable, Sendable {
    public let top: MenuBarQuotaMetric
    public let bottom: MenuBarQuotaMetric

    public init(top: MenuBarQuotaMetric, bottom: MenuBarQuotaMetric) {
        self.top = top
        self.bottom = bottom
    }

    public static func resolve(for provider: QuotaProvider, from models: [QuotaMetric]) -> MenuBarQuotaPair? {
        switch provider {
        case .claude:
            return makePair(
                from: models,
                topNames: ["five-hour-session"],
                topLabelKey: "quota.metric.fiveHour",
                bottomNames: ["seven-day-weekly", "seven-day-sonnet", "seven-day-opus"],
                bottomLabelKey: "quota.metric.weekly"
            )
        case .codex:
            let sessionNames: Set<String> = ["codex-session", "codex-spark"]
            guard let sessionPercentage = minimumPercentage(in: models, named: sessionNames),
                  sessionPercentage >= 0 else {
                return nil
            }
            return makePair(
                from: models,
                topNames: sessionNames,
                topLabelKey: "quota.metric.session",
                bottomNames: ["codex-weekly", "codex-spark-weekly"],
                bottomLabelKey: "quota.metric.weekly"
            )
        case .amp:
            return makePair(
                from: models,
                topNames: ["amp-agent-usage"],
                topLabelKey: "amp.quota.agent",
                bottomNames: ["amp-orb-usage"],
                bottomLabelKey: "amp.quota.orb",
                requiresBoth: true
            )
        case .antigravity:
            return makePair(
                from: models,
                topNames: ["antigravity-gemini-session", "antigravity-claude-gpt-session"],
                topLabelKey: "quota.metric.session",
                bottomNames: ["antigravity-gemini-weekly", "antigravity-claude-gpt-weekly"],
                bottomLabelKey: "quota.metric.weekly"
            )
        case .devin:
            return makePair(
                from: models,
                topNames: ["devin-daily"],
                topLabelKey: "quota.metric.daily",
                bottomNames: ["devin-weekly"],
                bottomLabelKey: "quota.metric.weekly",
                requiresBoth: true
            )
        case .cursor:
            guard models.contains(where: {
                $0.name == "on-demand"
                    && ($0.limit ?? 0) > 0
                    && $0.remaining != nil
                    && $0.percentage >= 0
            }) else {
                return nil
            }
            return makePair(
                from: models,
                topNames: ["plan-usage"],
                topLabelKey: "quota.metric.planUsage",
                bottomNames: ["on-demand"],
                bottomLabelKey: "quota.metric.onDemand",
                requiresBoth: true
            )
        default:
            return nil
        }
    }

    private static func makePair(
        from models: [QuotaMetric],
        topNames: Set<String>,
        topLabelKey: String,
        bottomNames: Set<String>,
        bottomLabelKey: String,
        requiresBoth: Bool = false
    ) -> MenuBarQuotaPair? {
        let topPercentage = minimumPercentage(in: models, named: topNames)
        let bottomPercentage = minimumPercentage(in: models, named: bottomNames)

        if requiresBoth {
            guard topPercentage != nil, bottomPercentage != nil else { return nil }
        } else {
            guard topPercentage != nil || bottomPercentage != nil else { return nil }
        }

        return MenuBarQuotaPair(
            top: MenuBarQuotaMetric(
                labelKey: topLabelKey,
                remainingPercentage: topPercentage ?? -1
            ),
            bottom: MenuBarQuotaMetric(
                labelKey: bottomLabelKey,
                remainingPercentage: bottomPercentage ?? -1
            )
        )
    }

    private static func minimumPercentage(in models: [QuotaMetric], named names: Set<String>) -> Double? {
        let matching = models.filter { names.contains($0.name) }
        guard !matching.isEmpty else { return nil }
        return matching.lazy.map(\.percentage).filter { $0 >= 0 }.min() ?? -1
    }
}

/// Data for displaying a single quota item in menu bar
public struct MenuBarQuotaDisplayItem: Identifiable, Equatable {
    public let id: String
    public let providerSymbol: String
    public let accountShort: String
    public let percentage: Double
    public let provider: QuotaProvider
    public var isForbidden: Bool
    public var quotaPair: MenuBarQuotaPair?

    public init(
        id: String,
        providerSymbol: String,
        accountShort: String,
        percentage: Double,
        provider: QuotaProvider,
        isForbidden: Bool = false,
        quotaPair: MenuBarQuotaPair? = nil
    ) {
        self.id = id
        self.providerSymbol = providerSymbol
        self.accountShort = accountShort
        self.percentage = percentage
        self.provider = provider
        self.isForbidden = isForbidden
        self.quotaPair = quotaPair
    }
    
    public var statusColor: Color {
        statusColor(for: percentage)
    }

    public func statusColor(for percentage: Double) -> Color {
        if isForbidden { return .orange }
        if percentage > 50 { return .green }
        if percentage > 20 { return .orange }
        return .red
    }
}

