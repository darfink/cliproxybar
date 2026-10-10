import Foundation

enum QuotaReadState: String, Codable, Equatable, Sendable {
    case pending, unsupported, empty, current, cached, stale, failed

    var isFailure: Bool { self == .stale || self == .failed }
    var allowsPace: Bool { self == .current }
    var symbol: String? {
        switch self {
        case .cached: "clock"
        case .stale: "clock.badge.exclamationmark"
        case .failed: "exclamationmark.circle"
        default: nil
        }
    }

    func emptyMessage(refreshing: Bool) -> String {
        switch self {
        case .pending: refreshing ? "Fetching quota…" : "Quota not fetched yet"
        case .unsupported: "Quota API unavailable"
        case .failed: "Quota refresh failed"
        default: "No quota limits returned"
        }
    }
}

struct ProxyAccountIdentity: Equatable, Hashable, Sendable {
    let provider: String
    let name: String
    let authIndex: String?
}
