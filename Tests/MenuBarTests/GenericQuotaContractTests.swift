import AppKit
import XCTest
import CLIProxyBarCore
@testable import MenuBar

final class GenericQuotaContractTests: XCTestCase {
    private func parse(_ body: String, provider: String = "fixture-service") throws -> ProviderQuota {
        try PluginQuotaParser.parse(Data(body.utf8), provider: provider)
    }

    private func account(_ provider: String = "fixture-service", name: String = "fixture.json") -> ProxyAccount {
        var account = ProxyAccount(name: name, provider: provider, email: nil, disabled: false,
            unavailable: false, quota: nil, model_quotas: nil)
        account.auth_index = "private-fixture-index"
        return account
    }

    private func client(_ response: @escaping @Sendable (URLRequest) throws -> (Int, String)) throws -> LocalProxyClient {
        var client = try LocalProxyClient(endpoint: "https://proxy.example.test/prefix")
        client.managementKey = { "fixture-key" }
        client.transport = { request in
            let (status, body) = try response(request)
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status,
                httpVersion: nil, headerFields: nil)!)
        }
        return client
    }

    func testEmptyAndSubscriptionOnlyResponsesAreSuccessfulWithoutInventedBars() throws {
        for body in ["{}", #"{"groups":[]}"#, #"{"groups":[{"buckets":[]}] }"#,
                     #"{"subscription":{"plan":"Pro"}}"#] {
            let quota = try parse(body)
            XCTAssertTrue(quota.models.isEmpty)
            var account = account()
            account.recordQuota(quota)
            XCTAssertEqual(account.quotaReadState, .empty)
            XCTAssertNil(account.quotaIssue)
            XCTAssertNil(account.quotaReadState.symbol)
        }
    }

    func testSubscriptionFallsBackThroughNonemptyTierFields() throws {
        for (body, expected) in [
            (#"{"subscription":{"plan":" ","tierName":"Premium"}}"#, "Premium"),
            (#"{"subscription":{"tierName":"","tier_name":"Team"}}"#, "Team"),
            (#"{"subscription":{"tierId":"business"}}"#, "business"),
            (#"{"subscription":{"tier_id":"enterprise"}}"#, "enterprise")
        ] {
            XCTAssertEqual(try parse(body).planType, expected)
        }
    }

    @MainActor func testDescriptionsDistinguishDuplicateWindowsAndIdentitySurvivesReordering() throws {
        let first = try parse(#"{"groups":[{"displayName":"Credits","buckets":[{"window":"monthly","description":"Base credits","remainingFraction":0.8},{"window":"monthly","description":"Bonus credits","remainingFraction":0.2}]}]}"#)
        let second = try parse(#"{"groups":[{"displayName":"Credits","buckets":[{"window":"monthly","description":"Bonus credits","remainingFraction":0.1},{"window":"monthly","description":"Base credits","remainingFraction":0.7}]}]}"#)
        XCTAssertEqual(first.models.map(\.displayName), ["Credits · Base credits", "Credits · Bonus credits"])
        XCTAssertEqual(first.models.map(\.id), second.models.reversed().map(\.id))
        XCTAssertEqual(Set(first.models.map(\.id)).count, 2)
        XCTAssertEqual(second.models.map(\.percentage), [10, 70])
    }

    func testUnnamedDistinctGroupsKeepIdentityWhenReordered() throws {
        let first = try parse(#"{"groups":[{"buckets":[{"window":"weekly","description":"Fast","remainingFraction":0.8}]},{"buckets":[{"window":"weekly","description":"Deep","remainingFraction":0.2}]}]}"#)
        let second = try parse(#"{"groups":[{"buckets":[{"window":"weekly","description":"Deep","remainingFraction":0.1}]},{"buckets":[{"window":"weekly","description":"Fast","remainingFraction":0.7}]}]}"#)
        XCTAssertEqual(first.models.map(\.id), second.models.reversed().map(\.id))
    }

    func testSummaryKeysAndRawValuesSurviveReorderingAndCacheEncoding() throws {
        let first = try parse(#"{"summary":[{"key":"used","label":"Used","value":0,"unit":"tokens"},{"key":"balance","label":"Balance","value":1234.5,"format":"currency","currency":"USD"}]}"#)
        let second = try parse(#"{"summary":[{"key":"balance","label":"Balance","value":1200,"format":"currency","currency":"USD"},{"key":"used","label":"Used","value":34,"unit":"tokens"}]}"#)
        XCTAssertEqual(first.models.map(\.id), second.models.reversed().map(\.id))
        XCTAssertEqual(first.models.first?.summary?.key, "used")
        XCTAssertEqual(first.models.first?.summary?.value, 0)
        XCTAssertTrue(first.models.allSatisfy { $0.percentage == -1 })
        XCTAssertEqual(first, try JSONDecoder().decode(ProviderQuota.self, from: JSONEncoder().encode(first)))
        let balance = try XCTUnwrap(first.models.last?.summary)
        XCTAssertEqual(balance.formatted(locale: Locale(identifier: "en_US")), "$1,234.50")
        XCTAssertTrue(balance.formatted(locale: Locale(identifier: "sv_SE")).contains(",50"))
        XCTAssertEqual(first.models.first?.summary?.formatted(locale: Locale(identifier: "en_US")), "0 tokens")
    }

    func testInvalidReadingsAreRejectedWhileValidOptionalMetricsRemainUsable() throws {
        for body in [#"{"groups":"invalid"}"#, #"{"groups":[{"buckets":true}]}"#,
                     #"{"groups":[{"buckets":[{"remainingFraction":true}]}]}"#,
                     #"{"summary":[{"key":"balance","label":"Balance","value":true}]}"#,
                     #"{"summary":[{"key":"","label":"Balance","value":0}]}"#] {
            XCTAssertThrowsError(try parse(body))
        }
        let mixed = try parse(#"{"groups":[{"buckets":[{"window":"weekly","remainingFraction":0},{"remainingFraction":2}]}],"summary":[{"key":"invalid","value":true}]}"#)
        XCTAssertEqual(mixed.models.map(\.percentage), [0])
    }

    func testRegistryPreservesMetadataAndIncludesPrimaryPluginAndAliasIDs() throws {
        let registry = try PluginQuotaParser.registry(Data(#"{"providers":[{"plugin_id":"fixture-plugin","provider":"fixture-quota","display_name":"Fixture AI","supported_providers":["fixture-account"," OTHER "],"supports_reset":true}]}"#.utf8))
        XCTAssertEqual(registry.identifiers, ["fixture-plugin", "fixture-quota", "fixture-account", "other"])
        for id in registry.identifiers {
            XCTAssertEqual(registry.entry(for: id)?.displayName, "Fixture AI")
            XCTAssertEqual(registry.entry(for: id)?.supportsReset, true)
        }
    }

    func testBackendQuotaProviderOverrideStaysInTheGenericRequest() async throws {
        let client = try client { request in
            XCTAssertEqual(request.url?.path, "/prefix/v0/management/quota/fetch")
            let body = try JSONDecoder().decode([String: String].self, from: request.httpBody!)
            XCTAssertEqual(body, ["auth_index": "private-fixture-index", "provider": "fixture-quota"])
            return (200, #"{"subscription":{"tierId":"team"}}"#)
        }
        var account = account()
        account.quota_provider = "fixture-quota"
        XCTAssertTrue(ActiveQuotaParser.supports(account, pluginProviders: []))
        let quota = try await client.fetchQuota(for: account)
        XCTAssertEqual(quota.planType, "team")
        XCTAssertTrue(quota.models.isEmpty)
    }

    func testUnsupportedQuotaIsDistinctFromTransportAndAuthenticationFailures() async throws {
        let unsupported = try client { _ in (501, "{}") }
        var account = account()
        account.supports_quota = true
        do { _ = try await unsupported.fetchQuota(for: account); XCTFail("Expected unsupported capability") }
        catch LocalClientError.quotaUnsupported { }
        for status in [401, 403, 429, 502] {
            let failed = try client { _ in (status, "{}") }
            do { _ = try await failed.fetchQuota(for: account); XCTFail("Expected HTTP failure") }
            catch LocalClientError.http(let actual) { XCTAssertEqual(actual, status) }
        }
    }

    func testFailedRefreshRetainsReadingAndSuccessfulEmptyResponseClearsIt() throws {
        var account = account()
        let reading = try parse(#"{"groups":[{"buckets":[{"window":"weekly","remainingFraction":0.5}]}]}"#)
        account.recordQuota(reading)
        account.recordQuotaFailure("Fixture request failed")
        XCTAssertEqual(account.quotaReadState, .stale)
        XCTAssertEqual(account.providerQuota().models.map(\.percentage), [50])
        account.recordQuota(try parse("{}"))
        XCTAssertEqual(account.quotaReadState, .empty)
        XCTAssertTrue(account.providerQuota().models.isEmpty)
        XCTAssertNil(account.quotaIssue)
        var unsupported = self.account()
        unsupported.recordQuotaFailure("No quota API", unsupported: true)
        XCTAssertEqual(unsupported.quotaReadState, .unsupported)
        XCTAssertFalse(unsupported.quotaReadState.isFailure)
        var failed = self.account()
        failed.recordQuotaFailure("Cannot fetch quota")
        XCTAssertEqual(failed.quotaReadState, .failed)
    }

    func testCacheKeepsMetadataOnlyEmptyAndUnsupportedAccountsWithoutCredentialIndices() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = QuotaCache(endpoint: "https://proxy.example.test", directory: directory)
        var metadata = account(name: "metadata.json")
        metadata.providerDisplayName = "Fixture AI"
        metadata.label = "Personal"
        metadata.recordQuota(try parse(#"{"subscription":{"tierName":"Pro"}}"#))
        var empty = account(name: "empty.json")
        empty.recordQuota(try parse("{}"))
        var unsupported = account(name: "unsupported.json")
        unsupported.quotaState = .unsupported
        try cache.save([metadata, empty, unsupported])
        let restored = try cache.load()
        XCTAssertEqual(restored.count, 3)
        XCTAssertEqual(restored[0].providerQuota().planType, "Pro")
        XCTAssertEqual(restored[0].providerDisplayName, "Fixture AI")
        XCTAssertEqual(restored[0].displayName, "Personal")
        XCTAssertEqual(restored[0].quotaReadState, .cached)
        XCTAssertFalse(restored[0].quotaReadState.isFailure)
        XCTAssertEqual(restored[2].quotaReadState, .unsupported)
        XCTAssertTrue(restored.allSatisfy { $0.auth_index == nil })
        XCTAssertFalse(try String(contentsOf: cache.url, encoding: .utf8).contains("private-fixture-index"))
        let fresh = restored.map { account(name: $0.name) }
        XCTAssertTrue(QuotaCache.merging(fresh, previous: restored).allSatisfy { $0.fetchedQuota != nil })
    }

    func testGenericLabelsCannotEnableGuessedPaceOrResetAlerts() throws {
        let quota = try parse(#"{"groups":[{"buckets":[{"window":"daily","remainingFraction":0.5,"resetTime":"2099-01-02T00:00:00Z"},{"window":"weekly","remainingFraction":0.7},{"window":"rolling","remainingFraction":0.8}]}]}"#)
        for metric in quota.models {
            XCTAssertNil(metric.windowDuration)
            XCTAssertNil(QuotaPace.calculate(metric: metric, observedAt: quota.lastUpdated))
            XCTAssertNil(QuotaResetKind.classify(metric.name))
        }
        XCTAssertEqual(QuotaResetKind.classify("opencode-go-weekly"), .long)
        XCTAssertEqual(QuotaResetKind.classify("five-hour-session"), .short)
    }

    func testResetDateUsesAliasAndServerClockCorrection() throws {
        let quota = try parse(#"{"serverTimeOffsetMs":60000,"groups":[{"displayName":" ","display_name":"Credits","buckets":[{"window":"weekly","remaining_fraction":0.5,"resetTime":" ","reset_time":"2026-10-10T01:00:00Z"}]}]}"#)
        XCTAssertEqual(quota.models.first?.resetTime, "2026-10-10T00:59:00Z")
        XCTAssertEqual(quota.models.first?.label, "Credits · Weekly")
    }

    func testRefreshIdentityDistinguishesSameNamesAcrossProvidersAndCredentials() {
        let first = account()
        var second = account("another-service")
        XCTAssertNotEqual(first.identity, second.identity)
        second = first
        second.auth_index = "another-private-index"
        XCTAssertNotEqual(first.identity, second.identity)
    }

    @MainActor func testProviderNamesAndReadStatesReachMenusAndSettings() throws {
        var account = account()
        account.providerDisplayName = "Fixture AI"
        account.recordQuota(try parse(#"{"subscription":{"plan":"Pro"}}"#))
        let providers = StatusBarMenuProviderSnapshot.grouping([account], refreshing: false)
        XCTAssertEqual(providers.first?.title, "Fixture AI")
        XCTAssertEqual(providers.first?.accounts.first?.quotaReadState, .empty)
        let suite = "GenericQuotaContractTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DisplayPreferences(defaults: defaults)
        preferences.updateAvailableProviders([account])
        XCTAssertEqual(preferences.providerName(try XCTUnwrap(QuotaProvider(rawValue: account.provider))), "Fixture AI")
    }

    func testOldCacheFormatWithoutNewFieldsStillLoads() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cache = QuotaCache(endpoint: "https://proxy.example.test", directory: directory)
        try Data(#"{"endpoint":"https://proxy.example.test","entries":[{"name":"old.json","provider":"fixture-service","quota":{"models":[{"name":"old-weekly","percentage":25,"resetTime":""}],"lastUpdated":0,"isForbidden":false}}]}"#.utf8).write(to: cache.url)
        let restored = try cache.load()
        XCTAssertEqual(restored.first?.providerQuota().models.first?.percentage, 25)
        XCTAssertEqual(restored.first?.quotaReadState, .cached)
    }

    @MainActor func testMenusFitManyProvidersAndMixedQuotaShapes() throws {
        var accounts: [ProxyAccount] = []
        for index in 0..<12 {
            var account = account("fixture-service-\(index)")
            account.providerDisplayName = "Provider with a long display name \(index)"
            if index % 3 == 0 { account.quotaState = .unsupported }
            else if index % 3 == 1 { account.recordQuota(try parse(#"{"subscription":{"plan":"Pro"}}"#)) }
            else { account.recordQuota(try parse(#"{"groups":[{"displayName":"Credits","buckets":[{"window":"monthly","description":"Base credits","remainingFraction":0.8},{"window":"monthly","description":"Bonus credits","remainingFraction":0.2}]}],"summary":[{"key":"balance","label":"Balance","value":0}]}"#)) }
            accounts.append(account)
        }
        let snapshot = StatusBarMenuSnapshot(connectionMessage: "Connected", isLocalProxyMode: false,
            proxyPort: 443, isProxyRunning: true, tunnel: CloudflareTunnelSnapshot(),
            providers: StatusBarMenuProviderSnapshot.grouping(accounts, refreshing: false), selectedProvider: nil,
            isLoadingQuotas: false, displaySettings: StatusBarMenuDisplaySettings(quotaDisplayMode: .used,
                quotaDisplayStyle: .lowestBar, hideSensitiveInfo: false, modelAggregationMode: .lowest),
            appearanceMode: .system, language: .english, quotaDiscoveryIssue: "Fixture registry unavailable")
        let commands = StatusBarCommandDispatcher(handlers: StatusBarCommandHandlers(
            refreshAll: {}, refreshProvider: { _ in }, refreshAccount: { _ in }, toggleProxy: {}, toggleTunnel: { _ in },
            copyText: { _ in }, switchAntigravityAccount: { _ in }, isAntigravityIDERunning: { false },
            confirmAntigravitySwitch: { _, _ in false }, selectProvider: { _ in }, settings: {}, openApp: {},
            quit: {}, menuNeedsRebuild: {}))
        for expanded in [false, true] {
            let menu = StatusBarMenuRenderer(snapshot: snapshot, commands: commands, expanded: expanded).buildMenu()
            let views = menu.items.compactMap(\.view)
            XCTAssertGreaterThan(views.count, accounts.count)
            for view in views {
                XCTAssertEqual(view.frame.width, expanded ? 360 : 280)
                XCTAssertTrue(view.frame.height.isFinite)
                XCTAssertGreaterThan(view.frame.height, 0)
            }
        }
    }
}
