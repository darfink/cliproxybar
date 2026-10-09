import Foundation
import Security
import CLIProxyBarCore

struct AuthEnvelope: Decodable, Sendable { let files: [ProxyAccount] }
struct QuotaSignals: Decodable, Sendable {
    let observed_at: String?
    let signals: [String: String]?
}
struct CodexAccountMetadata: Decodable, Sendable {
    let chatgpt_account_id: String?
}
struct ProxyAccount: Decodable, Sendable {
    let name: String
    let provider: String
    let email: String?
    let disabled: Bool?
    let unavailable: Bool?
    let quota: QuotaSignals?
    let model_quotas: [String: QuotaSignals]?
    var label: String? = nil
    var displayName: String { label?.isEmpty == false ? label! : (email ?? fetchedQuota?.accountDisplayName ?? name) }
    var auth_index: String? = nil
    var id_token: CodexAccountMetadata? = nil
    var fetchedQuota: ProviderQuota? = nil
    var quotaIssue: String? = nil
    var success: Int64? = nil
    var failed: Int64? = nil

    static func observationDate(_ raw: String?) -> Date {
        guard let raw else { return .distantPast }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) ?? .distantPast
    }
    func providerQuota() -> ProviderQuota {
        if var fetchedQuota {
            // Proxy unavailability includes temporary rate-limit cooldowns.
            // It does not mean the account is disabled or quota access failed.
            fetchedQuota.isForbidden = disabled == true
            return fetchedQuota
        }
        let candidates = ([quota].compactMap { $0 } + Array((model_quotas ?? [:]).values))
            .filter { !($0.signals ?? [:]).isEmpty }
            .sorted { Self.observationDate($0.observed_at) > Self.observationDate($1.observed_at) }
        let latest = candidates.first
        let signals = Dictionary((latest?.signals ?? [:]).map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
        var models: [QuotaMetric] = []
        func append(_ name: String, used: String, reset: String, scale: Double) {
            guard let raw = signals[used], let value = Double(raw), value.isFinite, value >= 0 else { return }
            let resetDate = signals[reset].flatMap(Double.init).map { Date(timeIntervalSince1970: $0) }
            models.append(QuotaMetric(name: name, percentage: max(0, min(100, 100 - value * scale)), resetTime: resetDate.map { ISO8601DateFormatter().string(from: $0) } ?? ""))
        }
        if provider == "claude" {
            append("five-hour-session", used: "anthropic-ratelimit-unified-5h-utilization", reset: "anthropic-ratelimit-unified-5h-reset", scale: 100)
            append("seven-day-weekly", used: "anthropic-ratelimit-unified-7d-utilization", reset: "anthropic-ratelimit-unified-7d-reset", scale: 100)
        } else if provider == "codex" {
            for window in ["primary", "secondary"] {
                let prefix = "x-codex-\(window)-"
                guard let minutes = signals[prefix + "window-minutes"].flatMap(Double.init), minutes > 0 else { continue }
                append(minutes >= 10080 ? "codex-weekly" : "codex-session", used: prefix + "used-percent", reset: prefix + "reset-at", scale: 1)
            }
        }
        let observed = Self.observationDate(latest?.observed_at)
        return ProviderQuota(models: models, lastUpdated: observed, isForbidden: disabled == true, planType: signals["x-codex-plan-type"], accountDisplayName: displayName)
    }
}

enum LocalClientError: LocalizedError {
    case missingKey, keychain(OSStatus), http(Int), invalidEndpoint, missingAuthIndex, providerHTTP(Int), noQuotaData
    var errorDescription: String? {
        switch self {
        case .missingAuthIndex: "Account has no proxy authentication index."
        case .providerHTTP(let status): "Quota request returned HTTP \(status). Previous readings are retained."
        case .noQuotaData: "The provider returned no supported quota readings."
        case .missingKey: "Add your CLIProxyAPI management key in Settings (⌘,)."
        case .keychain(let status): "Keychain access failed (\(status))."
        case .http(let status): status == 401 || status == 403 ? "Management key was rejected. Update it in Settings (⌘,)." : "CLIProxyAPI returned HTTP \(status)."
        case .invalidEndpoint: "Use an HTTP or HTTPS proxy URL without credentials, a query, or a fragment."
        }
    }
}

enum ManagementKey {
    static let service = "io.github.darfink.CLIProxyBar.management"
    static func read() throws -> String {
        do { return try read(service: service) }
        catch LocalClientError.missingKey {
            let key = try read(service: "local.QuotioMenuBar.management")
            // Keep the legacy item intact if copying fails or the old app still uses it.
            try? save(key)
            return key
        }
    }
    private static func read(service: String) throws -> String {
        var result: CFTypeRef?
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "local", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { throw status == errSecItemNotFound ? LocalClientError.missingKey : LocalClientError.keychain(status) }
        guard let data = result as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else { throw LocalClientError.missingKey }
        return key
    }
    static func save(_ key: String) throws {
        guard !key.isEmpty else { throw LocalClientError.missingKey }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "local"]
        let attributes = [kSecValueData as String: Data(key.utf8)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let added = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
            guard added == errSecSuccess else { throw LocalClientError.keychain(added) }
        } else if status != errSecSuccess { throw LocalClientError.keychain(status) }
    }
}

struct LocalProxyClient: Sendable {
    let baseURL: URL
    var defaultPort: Int { baseURL.scheme == "https" ? 443 : 80 }
    var isLoopback: Bool { ["127.0.0.1", "localhost", "[::1]"].contains(baseURL.host?.lowercased() ?? "") }
    var displayAddress: String {
        let host = baseURL.host ?? "Proxy"
        return baseURL.port.map { "\(host):\($0)" } ?? host
    }
    init(endpoint: String) throws {
        guard let url = URL(string: endpoint), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { throw LocalClientError.invalidEndpoint }
        guard (1...65535).contains(url.port ?? 80) else { throw LocalClientError.invalidEndpoint }
        baseURL = url
    }
    func fetch() async throws -> [ProxyAccount] {
        try JSONDecoder().decode(AuthEnvelope.self, from: await send(path: "auth-files")).files
    }

    func enableUsageStatistics() async throws {
        _ = try await send(path: "usage-statistics-enabled", body: Data(#"{"value":true}"#.utf8), method: "PUT")
    }

    func fetchUsageEvents() async throws -> [ProxyUsageEvent] {
        let data = try await send(path: "usage-queue", query: [URLQueryItem(name: "count", value: "500")])
        return try JSONDecoder().decode([ProxyUsageEvent].self, from: data)
    }

    func fetchQuota(for account: ProxyAccount) async throws -> ProviderQuota {
        if account.provider == "opencode-go" {
            guard let index = account.auth_index, !index.isEmpty else { throw LocalClientError.missingAuthIndex }
            let data = try await send(path: "quota/fetch", body: JSONEncoder().encode(["auth_index": index]))
            var quota = try ActiveQuotaParser.parsePlugin(data)
            quota.accountDisplayName = account.displayName
            return quota
        }
        let call = try ActiveQuotaParser.request(for: account)
        let data = try await send(path: "api-call", body: JSONEncoder().encode(call))
        let result = try JSONDecoder().decode(ProxyAPICallResult.self, from: data)
        guard (200...299).contains(result.statusCode) else { throw LocalClientError.providerHTTP(result.statusCode) }
        guard let body = result.body?.data(using: .utf8) else { throw LocalClientError.noQuotaData }
        var quota = try ActiveQuotaParser.parse(body, provider: account.provider)
        quota.accountDisplayName = account.displayName
        return quota
    }

    private func send(path: String, body: Data? = nil, method: String = "POST", query: [URLQueryItem] = []) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent("v0/management/" + path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer " + (try ManagementKey.read()), forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        if let body {
            request.httpMethod = method
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForResource = 25
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw LocalClientError.http((response as? HTTPURLResponse)?.statusCode ?? 0) }
        return data
    }
}
private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
