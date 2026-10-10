import Foundation

struct RegisteredQuotaProvider: Codable, Equatable, Sendable {
    let pluginID: String?
    let provider: String
    let displayName: String?
    let supportedProviders: [String]
    let supportsReset: Bool

    var identifiers: Set<String> {
        Set(([provider] + supportedProviders + [pluginID].compactMap { $0 })
            .map(QuotaProviderRegistry.normalize).filter { !$0.isEmpty })
    }
}

struct QuotaProviderRegistry: Equatable, Sendable {
    var entries: [RegisteredQuotaProvider] = []
    var identifiers: Set<String> { Set(entries.flatMap(\.identifiers)) }

    static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func entry(for provider: String) -> RegisteredQuotaProvider? {
        let identifier = Self.normalize(provider)
        guard !identifier.isEmpty else { return nil }
        // Follow the backend's preference for exact IDs before supported aliases.
        return entries.first { Self.normalize($0.provider) == identifier || $0.pluginID.map(Self.normalize) == identifier }
            ?? entries.first { $0.identifiers.contains(identifier) }
    }
}
