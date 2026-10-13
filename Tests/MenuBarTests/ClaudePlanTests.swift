import Foundation
import XCTest
import CLIProxyBarCore
@testable import MenuBar

final class ClaudePlanTests: XCTestCase {
    private func account(_ index: String = "pro-account") -> ProxyAccount {
        var account = ProxyAccount(name: index + ".json", provider: "claude", email: nil,
            disabled: false, unavailable: false, quota: nil, model_quotas: nil)
        account.auth_index = index
        return account
    }

    private actor Requests {
        private var count = 0
        func record() { count += 1 }
        func total() -> Int { count }
    }

    @MainActor func testProfileDistinguishesProAndMaxMultipliersWithoutGuessingUnknownPlans() throws {
        for (profile, expected) in [
            (#"{"organization":{"organization_type":"claude_pro","rate_limit_tier":"default_claude_ai"}}"#, "pro"),
            (#"{"organization":{"organization_type":"claude_max","rate_limit_tier":"default_claude_max_5x"}}"#, "max_5x"),
            (#"{"organization":{"organization_type":"claude_max","rate_limit_tier":"default_claude_max_20x"}}"#, "max_20x"),
            (#"{"organization":{"organization_type":"claude_max","rate_limit_tier":"unfamiliar"}}"#, "max"),
            (#"{"organization":{"organization_type":"claude_team"},"account":{"has_claude_pro":true}}"#, "team"),
            (#"{"account":{"has_claude_max":true,"has_claude_pro":false},"organization":{"rate_limit_tier":"default_claude_max_5x"}}"#, "max_5x"),
            (#"{"account":{"has_claude_pro":true,"has_claude_max":false}}"#, "pro")
        ] {
            XCTAssertEqual(try ClaudePlanParser.parse(Data(profile.utf8)), expected)
        }
        for profile in [
            #"{"organization":{"rate_limit_tier":"default_claude_ai"}}"#,
            #"{"organization":{"organization_type":"unfamiliar"},"account":{"has_claude_max":false,"has_claude_pro":false}}"#,
            #"{"account":{"has_claude_max":true,"has_claude_pro":true}}"#
        ] {
            XCTAssertNil(try ClaudePlanParser.parse(Data(profile.utf8)))
        }
        for profile in ["{}", #"{"error":"denied"}"#, #"{"account":{"has_claude_max":1}}"#] {
            XCTAssertThrowsError(try ClaudePlanParser.parse(Data(profile.utf8)))
        }
        XCTAssertEqual(ProviderQuota(planType: "max_5x").planDisplayName, "Max 5×")
        XCTAssertEqual(ProviderQuota(planType: "max_20x").planDisplayName, "Max 20×")
    }

    func testProfileRequestKeepsCredentialsInProxyAndRequiresAccountIndex() throws {
        let request = try ClaudePlanParser.request(for: account())
        XCTAssertEqual(request.url, "https://api.anthropic.com/api/oauth/profile")
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.authIndex, "pro-account")
        XCTAssertEqual(request.header?["Authorization"], "Bearer $TOKEN$")
        XCTAssertEqual(request.header?["anthropic-beta"], "oauth-2025-04-20")
        XCTAssertNil(request.data)
        var missing = account()
        missing.auth_index = nil
        XCTAssertThrowsError(try ClaudePlanParser.request(for: missing))
    }

    func testCacheExpiresAndCoalescesConcurrentProfileLookups() async throws {
        let cache = ClaudePlanCache()
        let identity = account().identity
        let requests = Requests()
        let now = Date(timeIntervalSince1970: 1800000000)
        let fetch: @Sendable () async throws -> String? = {
            await requests.record()
            try await Task.sleep(for: .milliseconds(30))
            return "pro"
        }
        async let first = cache.plan(for: identity, now: now, fetch: fetch)
        async let second = cache.plan(for: identity, now: now, fetch: fetch)
        let results = await [first, second]
        XCTAssertEqual(results, ["pro", "pro"])
        let reused = await cache.plan(for: identity, now: now.addingTimeInterval(3599), fetch: fetch)
        XCTAssertEqual(reused, "pro")
        let firstCount = await requests.total()
        XCTAssertEqual(firstCount, 1)
        let renewed = await cache.plan(for: identity, now: now.addingTimeInterval(3600), fetch: fetch)
        XCTAssertEqual(renewed, "pro")
        let finalCount = await requests.total()
        XCTAssertEqual(finalCount, 2)
    }

    func testFailureRetainsKnownPlanAndRetriesWhileValidUnknownProfileClearsLabel() async {
        let cache = ClaudePlanCache()
        let identity = account().identity
        let now = Date(timeIntervalSince1970: 1800000000)
        let failed = await cache.plan(for: identity, fallback: "max_5x", now: now) { throw LocalClientError.providerHTTP(503) }
        XCTAssertEqual(failed, "max_5x")
        let waiting = await cache.plan(for: identity, now: now.addingTimeInterval(299)) {
            XCTFail("Profile failures must back off")
            return "pro"
        }
        XCTAssertEqual(waiting, "max_5x")
        let recovered = await cache.plan(for: identity, now: now.addingTimeInterval(300)) { "max_20x" }
        XCTAssertEqual(recovered, "max_20x")
        let retained = await cache.plan(for: identity, now: now.addingTimeInterval(3900)) { throw LocalClientError.providerHTTP(429) }
        XCTAssertEqual(retained, "max_20x")
        let unknown = await cache.plan(for: identity, fallback: "pro", now: now.addingTimeInterval(4200)) { nil }
        XCTAssertNil(unknown)
    }

    func testClientKeepsIndependentPlansAcrossAccountsAndCachesOnlyParsedLabels() async throws {
        let requests = Requests()
        var client = try LocalProxyClient(endpoint: "https://proxy.example.test/prefix")
        client.managementKey = { "fixture-management-key" }
        client.transport = { request in
            XCTAssertEqual(request.url?.path, "/prefix/v0/management/api-call")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-management-key")
            let call = try JSONDecoder().decode(ProxyAPICall.self, from: request.httpBody!)
            XCTAssertEqual(call.header?["Authorization"], "Bearer $TOKEN$")
            if call.url.hasSuffix("/profile") {
                XCTAssertEqual(request.timeoutInterval, 5)
                await requests.record()
                let type = call.authIndex == "pro-account" ? "claude_pro" : "claude_max"
                let tier = call.authIndex == "pro-account" ? "default_claude_ai" : "default_claude_max_5x"
                let body = #"{"account":{"email":"profile-only-email@example.test","uuid":"profile-only-uuid"},"organization":{"name":"profile-only-name","organization_type":"\#(type)","rate_limit_tier":"\#(tier)"}}"#
                let data = try JSONSerialization.data(withJSONObject: ["status_code": 200, "body": body])
                return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            XCTAssertTrue(call.url.hasSuffix("/usage"))
            let body = #"{"five_hour":{"utilization":25},"seven_day":{"utilization":50}}"#
            let data = try JSONSerialization.data(withJSONObject: ["status_code": 200, "body": body])
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        var accounts = [account(), account("max-account")]
        for index in accounts.indices {
            let quota = try await client.fetchQuota(for: accounts[index])
            XCTAssertEqual(quota.planType, index == 0 ? "pro" : "max_5x")
            XCTAssertEqual(quota.models.map(\.percentage), [75, 50])
            accounts[index].recordQuota(quota)
            _ = try await client.fetchQuota(for: accounts[index])
        }
        let count = await requests.total()
        XCTAssertEqual(count, 2)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = QuotaCache(endpoint: client.baseURL.absoluteString, directory: directory)
        try cache.save(accounts)
        let serialized = try String(contentsOf: cache.url, encoding: .utf8)
        for privateValue in ["profile-only-email", "profile-only-uuid", "profile-only-name", "default_claude_max_5x"] {
            XCTAssertFalse(serialized.contains(privateValue))
        }
        let restored = try cache.load()
        XCTAssertEqual(restored.map { $0.providerQuota().planType }, ["pro", "max_5x"])
    }

    func testProfileFailureStillReturnsFreshQuotasAndKeepsPreviousLabel() async throws {
        var client = try LocalProxyClient(endpoint: "https://proxy.example.test")
        client.managementKey = { "fixture" }
        client.transport = { request in
            let call = try JSONDecoder().decode(ProxyAPICall.self, from: request.httpBody!)
            let profile = call.url.hasSuffix("/profile")
            let data = try JSONSerialization.data(withJSONObject: ["status_code": profile ? 403 : 200,
                "body": profile ? "{}" : #"{"five_hour":{"utilization":12},"seven_day":{"utilization":34}}"#])
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        var account = account()
        account.fetchedQuota = ProviderQuota(planType: "max_5x")
        let quota = try await client.fetchQuota(for: account)
        XCTAssertEqual(quota.planType, "max_5x")
        XCTAssertEqual(quota.models.map(\.percentage), [88, 66])
    }

    func testNewerPassiveQuotaRetainsKnownPlanWithoutRestoringOlderUsage() throws {
        var previous = account()
        previous.fetchedQuota = ProviderQuota(models: [QuotaMetric(name: "five-hour-session", percentage: 80, resetTime: "")],
            lastUpdated: Date(timeIntervalSince1970: 123), planType: "max_5x")
        let fresh = try JSONDecoder().decode(ProxyAccount.self, from: Data(#"{"name":"pro-account.json","provider":"claude","auth_index":"pro-account","quota":{"observed_at":"2026-10-13T12:00:00Z","signals":{"anthropic-ratelimit-unified-5h-utilization":"0.1"}}}"#.utf8))
        let merged = try XCTUnwrap(QuotaCache.merging([fresh], previous: [previous]).first)
        XCTAssertEqual(merged.providerQuota().planType, "max_5x")
        XCTAssertEqual(merged.providerQuota().models.map(\.percentage), [90])
        XCTAssertEqual(merged.providerQuota().lastUpdated, ProxyAccount.observationDate("2026-10-13T12:00:00Z"))
    }

    func testBackendPlanTakesPrecedenceAndDoesNotRequestProfile() async throws {
        for usesGenericEndpoint in [false, true] {
            var client = try LocalProxyClient(endpoint: "https://proxy.example.test")
            client.managementKey = { "fixture" }
            client.transport = { request in
                if request.url!.path.hasSuffix("quota/fetch") {
                    let body = #"{"subscription":{"tier_name":"Team"},"groups":[{"buckets":[{"window":"weekly","remainingFraction":0.5}]}]}"#
                    return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                }
                let call = try JSONDecoder().decode(ProxyAPICall.self, from: request.httpBody!)
                XCTAssertTrue(call.url.hasSuffix("/usage"), "Backend plan metadata must avoid the supplementary profile lookup")
                let data = try JSONSerialization.data(withJSONObject: ["status_code": 200, "body": #"{"plan_type":"Team","five_hour":{"utilization":25}}"#])
                return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            var account = account()
            account.supports_quota = usesGenericEndpoint
            let quota = try await client.fetchQuota(for: account)
            XCTAssertEqual(quota.planType, "Team")
        }
    }
}
