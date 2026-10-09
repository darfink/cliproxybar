import Foundation
import CLIProxyBarCore

struct StatusBarMenuAccountSnapshot: Equatable, Sendable {
    let id: QuotaAccountID
    let email: String
    let quota: ProviderQuota
    let subscription: QuotaSubscriptionInfo?
    let isActiveInIDE: Bool
    let isRefreshing: Bool
    let isRefreshBlocked: Bool
    var refreshIssue: String? = nil
    var proxyUsage: ProxyUsageSnapshot? = nil
}

struct StatusBarMenuProviderSnapshot: Equatable, Sendable {
    let provider: QuotaProvider
    let accounts: [StatusBarMenuAccountSnapshot]
    let isRefreshing: Bool
    let supportsScopedRefresh: Bool
}

struct StatusBarMenuDisplaySettings: Equatable, Sendable {
    let quotaDisplayMode: QuotaDisplayMode
    let quotaDisplayStyle: QuotaDisplayStyle
    let hideSensitiveInfo: Bool
    let modelAggregationMode: ModelAggregationMode

    func aggregateModelPercentages(_ percentages: [Double]) -> Double {
        let validPercentages = percentages.filter { $0 >= 0 }
        guard !validPercentages.isEmpty else { return -1 }

        switch modelAggregationMode {
        case .lowest:
            return validPercentages.min() ?? -1
        case .average:
            return validPercentages.reduce(0, +) / Double(validPercentages.count)
        }
    }
}

public struct StatusBarMenuSnapshot: Equatable, Sendable {
    let connectionMessage: String
    let isLocalProxyMode: Bool
    let proxyPort: UInt16
    let isProxyRunning: Bool
    let tunnel: CloudflareTunnelSnapshot
    let providers: [StatusBarMenuProviderSnapshot]
    let selectedProvider: QuotaProvider?
    let isLoadingQuotas: Bool
    let displaySettings: StatusBarMenuDisplaySettings
    let appearanceMode: AppearanceMode
    let language: AppLanguage
}
