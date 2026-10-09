import XCTest
import CLIProxyBarCore
@testable import MenuBar

final class ProviderIntegrationTests: XCTestCase {
    private func account(_ provider: String, supportsQuota: Bool = false) -> ProxyAccount {
        var account = ProxyAccount(name: "fixture.json", provider: provider, email: nil, disabled: false, unavailable: false, quota: nil, model_quotas: nil)
        account.auth_index = "fixture-index"
        account.supports_quota = supportsQuota
        return account
    }

    private func client(_ reply: @escaping @Sendable (URLRequest) throws -> (Int, String)) throws -> LocalProxyClient {
        var client = try LocalProxyClient(endpoint: "https://proxy.example.test/prefix")
        client.managementKey = { "fixture-management-key" }
        client.transport = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-management-key")
            let (status, body) = try reply(request)
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        return client
    }

    @MainActor func testUnknownProvidersAppearAndPreferencesPreserveIdentity() throws {
        let provider = try XCTUnwrap(QuotaProvider(rawValue: "new-service"))
        XCTAssertEqual(provider.displayName, "New Service")
        XCTAssertEqual(try JSONDecoder().decode(QuotaProvider.self, from: JSONEncoder().encode(provider)), provider)
        XCTAssertEqual(String(decoding: try JSONEncoder().encode(QuotaProvider.claude), as: UTF8.self), #""claude""#)
        XCTAssertEqual(QuotaProvider(rawValue: "xai"), .grok)
        XCTAssertEqual(QuotaProvider(rawValue: "kimi-ai"), .kimi)
        XCTAssertNil(QuotaProvider(rawValue: " "))
        let suite = "ProviderIntegrationTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DisplayPreferences(defaults: defaults)
        preferences.updateAvailableProviders([account("new-service"), account("xai")])
        XCTAssertTrue(preferences.availableProviders.contains(provider))
        XCTAssertTrue(preferences.availableProviders.contains(.grok))
        preferences.setMenuBarVisible(false, for: provider)
        XCTAssertFalse(DisplayPreferences(defaults: defaults).showsInMenuBar(provider))
    }

    @MainActor func testUnknownAccountIsIncludedInBothMenusWithoutInventedQuotas() throws {
        let providers = StatusBarMenuProviderSnapshot.grouping([account("new-service"), account("xai")], refreshing: false)
        let snapshot = StatusBarMenuSnapshot(connectionMessage: "Fixture", isLocalProxyMode: false, proxyPort: 443,
            isProxyRunning: true, tunnel: CloudflareTunnelSnapshot(), providers: providers, selectedProvider: nil,
            isLoadingQuotas: false, displaySettings: StatusBarMenuDisplaySettings(quotaDisplayMode: .used,
                quotaDisplayStyle: .lowestBar, hideSensitiveInfo: false, modelAggregationMode: .lowest),
            appearanceMode: .system, language: .english)
        XCTAssertEqual(Set(snapshot.providers.map(\.provider.rawValue)), ["new-service", "grok"])
        XCTAssertTrue(snapshot.providers.allSatisfy { $0.accounts[0].quota.models.isEmpty && $0.accounts[0].refreshIssue == nil })
        let dispatcher = StatusBarCommandDispatcher(handlers: StatusBarCommandHandlers(
            refreshAll: {}, refreshProvider: { _ in }, refreshAccount: { _ in },
            toggleProxy: {}, toggleTunnel: { _ in }, copyText: { _ in },
            switchAntigravityAccount: { _ in }, isAntigravityIDERunning: { false }, confirmAntigravitySwitch: { _, _ in false },
            selectProvider: { _ in }, settings: {}, openApp: {}, quit: {}, menuNeedsRebuild: {}))
        for expanded in [false, true] {
            let menu = StatusBarMenuRenderer(snapshot: snapshot, commands: dispatcher, expanded: expanded).buildMenu()
            XCTAssertFalse(menu.items.isEmpty)
        }
    }

    func testResetClassificationUsesKnownWindowsAndLeavesUnfamiliarWindowsAlone() {
        XCTAssertEqual(QuotaResetKind.classify("plugin:0:0:rolling"), .short)
        XCTAssertEqual(QuotaResetKind.classify("plugin:1:0:weekly"), .long)
        XCTAssertEqual(QuotaResetKind.classify("antigravity-gemini-session"), .short)
        XCTAssertNil(QuotaResetKind.classify("plugin:0:0:custom-period"))
        XCTAssertEqual(QuotaResetKind.label("plugin:0:0:monthly"), "Monthly")
    }

    func testDiscoveryUsesSupportedAliasesAndOlderBackendsRemainCompatible() async throws {
        let client = try client { request in
            XCTAssertEqual(request.url?.path, "/prefix/v0/management/quota/providers")
            XCTAssertEqual(request.httpMethod, "GET")
            return (200, #"{"providers":[{"provider":"quota-implementation","supported_providers":["first","second"]},{"provider":"third"}]}"#)
        }
        let providers = try await client.fetchQuotaProviders()
        XCTAssertEqual(providers, ["first", "second", "third"])
        let older = try self.client { _ in (404, "") }
        let missing = try await older.fetchQuotaProviders()
        XCTAssertTrue(missing.isEmpty)
        let unauthorized = try self.client { _ in (401, "") }
        do { _ = try await unauthorized.fetchQuotaProviders(); XCTFail("Unauthorized discovery must be reported") }
        catch LocalClientError.http(let status) { XCTAssertEqual(status, 401) }
    }

    @MainActor func testAnyDiscoveredProviderUsesNormalizedQuotaAndKeepsGroupsDistinct() async throws {
        let client = try client { request in
            XCTAssertEqual(request.url?.path, "/prefix/v0/management/quota/fetch")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try JSONDecoder().decode([String: String].self, from: request.httpBody!)
            XCTAssertEqual(body, ["auth_index": "fixture-index"])
            return (200, #"{"subscription":{"tier_name":"Team"},"groups":[{"displayName":"Fast","buckets":[{"window":"daily","remainingFraction":1}]},{"display_name":"Deep","buckets":[{"window":"daily","remaining_fraction":0}]}]}"#)
        }
        let account = account("new-service")
        XCTAssertTrue(ActiveQuotaParser.supports(account, pluginProviders: ["new-service"]))
        let quota = try await client.fetchQuota(for: account, pluginProviders: ["new-service"])
        XCTAssertEqual(quota.models.map(\.percentage), [100, 0])
        XCTAssertEqual(quota.models.map(\.displayName), ["Fast · Daily", "Deep · Daily"])
        XCTAssertEqual(Set(quota.models.map(\.id)).count, 2)
        XCTAssertEqual(quota.planType, "Team")
        XCTAssertEqual(quota.models.map(\.windowDuration), [86400, 86400])
    }

    func testAccountCapabilityWorksWithoutDiscovery() async throws {
        let client = try client { request in
            XCTAssertTrue(request.url!.path.hasSuffix("quota/fetch"))
            return (200, #"{"groups":[{"buckets":[{"window":"hourly","remainingFraction":0.25}]}]}"#)
        }
        let account = account("new-service", supportsQuota: true)
        XCTAssertTrue(ActiveQuotaParser.supports(account, pluginProviders: []))
        let quota = try await client.fetchQuota(for: account)
        XCTAssertEqual(quota.models.first?.percentage, 25)
        XCTAssertNil(quota.models.first?.windowDuration)
        XCTAssertFalse(ActiveQuotaParser.supports(self.account("no-quota-api"), pluginProviders: []))
    }

    @MainActor func testGenericQuotaPreservesUnknownWindowsSummariesAndServerOffset() throws {
        let quota = try PluginQuotaParser.parse(Data(#"{"serverTimeOffsetMs":60000,"groups":[{"buckets":[{"window":"custom-period","remainingFraction":0.3,"resetTime":"2026-10-10T01:00:00Z"}]}],"summary":[{"key":"spend","label":"Spend","value":1.5,"format":"currency","currency":"USD"}]}"#.utf8), provider: "custom")
        XCTAssertEqual(quota.models.count, 2)
        XCTAssertEqual(quota.models[0].displayName, "Custom Period")
        XCTAssertNil(quota.models[0].windowDuration)
        XCTAssertEqual(quota.models[0].resetTime, "2026-10-10T00:59:00Z")
        XCTAssertEqual(quota.models[1].percentage, -1)
        XCTAssertTrue(quota.models[1].isStandaloneMetric)
        XCTAssertEqual(quota.models[1].displayName, "Spend")
        XCTAssertNotNil(quota.models[1].formattedUsage)
        for body in [#"{"error":"denied"}"#, #"{"groups":[{"buckets":[{"window":"daily"}]}]}"#, #"{"groups":[{"buckets":[{"remainingFraction":true},{"remainingFraction":-1},{"remainingFraction":1.1}]}]}"#] {
            XCTAssertThrowsError(try PluginQuotaParser.parse(Data(body.utf8), provider: "custom"))
        }
    }

    func testAntigravityRequestsKeepCredentialsInProxyAndUseProjectFromSubscription() async throws {
        let client = try client { request in
            XCTAssertTrue(request.url!.path.hasSuffix("api-call"))
            let call = try JSONDecoder().decode(ProxyAPICall.self, from: request.httpBody!)
            XCTAssertEqual(call.authIndex, "fixture-index")
            XCTAssertEqual(call.header?["Authorization"], "Bearer $TOKEN$")
            XCTAssertEqual(call.method, "POST")
            let reply: String
            if call.url.hasSuffix("loadCodeAssist") {
                reply = #"{"cloudaicompanionProject":"fixture-project","currentTier":{"name":"Pro"}}"#
            } else {
                XCTAssertTrue(call.url.hasSuffix("retrieveUserQuotaSummary"))
                XCTAssertEqual(try JSONDecoder().decode([String: String].self, from: Data(call.data!.utf8)), ["project": "fixture-project"])
                reply = #"{"groups":[{"displayName":"Gemini","buckets":[{"bucketId":"five-hour-session","remainingFraction":0.25},{"bucketId":"weekly","remaining":{"case":"remainingFraction","value":"0.75"}}]}]}"#
            }
            return (200, String(decoding: try JSONSerialization.data(withJSONObject: ["status_code": 200, "body": reply]), as: UTF8.self))
        }
        let quota = try await client.fetchQuota(for: account("antigravity"))
        XCTAssertEqual(quota.models.map(\.percentage), [25, 75])
        XCTAssertEqual(quota.models.map(\.windowDuration), [18000, 604800])
        XCTAssertEqual(quota.planType, "Pro")
    }

    func testAntigravityFallbackDoesNotTurnMissingOrInvalidQuotaIntoZero() async throws {
        let client = try client { request in
            let call = try JSONDecoder().decode(ProxyAPICall.self, from: request.httpBody!)
            let status = call.url.hasSuffix("loadCodeAssist") ? 503 : call.url.hasSuffix("retrieveUserQuotaSummary") ? 404 : 200
            let body = status == 200 ? #"{"models":{"gemini-test":{"quotaInfo":{"remainingFraction":0}},"missing":{"quotaInfo":{}},"invalid":{"quotaInfo":{"remainingFraction":true}}}}"# : "{}"
            return (200, String(decoding: try JSONSerialization.data(withJSONObject: ["status_code": status, "body": body]), as: UTF8.self))
        }
        let quota = try await client.fetchQuota(for: account("antigravity"))
        XCTAssertEqual(quota.models.map(\.name), ["gemini-test"])
        XCTAssertEqual(quota.models.map(\.percentage), [0])
        XCTAssertNil(quota.models[0].windowDuration)
        XCTAssertThrowsError(try GoogleQuotaParser.summary(Data(#"{"groups":[{"buckets":[{"remainingFraction":true}]}]}"#.utf8)))
    }
}
