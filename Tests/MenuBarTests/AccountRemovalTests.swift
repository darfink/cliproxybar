import XCTest
@testable import MenuBar

final class AccountRemovalTests: XCTestCase {
    private func account(name: String = "workspace & team.json", source: String? = "file", runtimeOnly: Bool? = false,
                         authIndex: String? = "auth-index") -> ProxyAccount {
        var account = ProxyAccount(name: name, provider: "codex", email: nil, disabled: nil, unavailable: nil,
                                   quota: nil, model_quotas: nil)
        account.source = source
        account.runtime_only = runtimeOnly
        account.auth_index = authIndex
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

    func testRemovalRevalidatesIdentityThenDeletesEncodedFilename() async throws {
        let deleted = expectation(description: "Exact credential DELETE sent")
        let client = try client { request in
            if request.httpMethod == "GET" {
                XCTAssertEqual(request.url?.path, "/prefix/v0/management/auth-files")
                XCTAssertNil(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.query)
                return (200, #"{"files":[{"name":"workspace & team.json","provider":"codex","auth_index":"auth-index","source":"file","runtime_only":false}]}"#)
            }
            deleted.fulfill()
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/prefix/v0/management/auth-files")
            let components = try XCTUnwrap(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
            XCTAssertEqual(components.queryItems, [URLQueryItem(name: "name", value: "workspace & team.json")])
            XCTAssertFalse(components.queryItems?.contains(where: { $0.name == "all" }) ?? false)
            XCTAssertTrue(request.url!.absoluteString.contains("workspace%20%26%20team.json"))
            return (200, #"{"status":"ok"}"#)
        }

        try await client.removeCredential(account())
        await fulfillment(of: [deleted], timeout: 1)
    }

    func testRemovalRejectsChangedAuthIndexAfterFreshFetch() async throws {
        let client = try client { request in
            XCTAssertEqual(request.httpMethod, "GET")
            return (200, #"{"files":[{"name":"workspace & team.json","provider":"codex","auth_index":"new-auth-index","source":"file","runtime_only":false}]}"#)
        }
        do {
            try await client.removeCredential(account())
            XCTFail("Expected changed account identity to be rejected")
        } catch LocalClientError.accountChanged {
        }
    }

    func testNonFileRuntimeAndUnsafeNamesAreRejectedWithoutNetwork() async throws {
        let client = try client { _ in
            XCTFail("Invalid credentials must be rejected before making a request")
            return (200, "{}")
        }
        let invalid = [
            account(source: "config"),
            account(source: nil),
            account(authIndex: nil),
            account(name: ""),
            account(name: " leading-space.json"),
            account(name: "trailing-space.json\n"),
            account(runtimeOnly: true),
            account(name: "../credential.json"),
            account(name: "folder/credential.json"),
            account(name: "folder\\credential.json")
        ]
        for candidate in invalid {
            do {
                try await client.removeCredential(candidate)
                XCTFail("Expected non-removable account to be rejected")
            } catch LocalClientError.accountNotRemovable {
            }
        }
    }

    func testRemovalRejectsServerFailureAndInvalidSuccessBody() async throws {
        for (status, body) in [(500, #"{"status":"ok"}"#), (200, "not-json"), (200, #"{"status":"deleted"}"#)] {
            let client = try client { request in
                if request.httpMethod == "GET" {
                    return (200, #"{"files":[{"name":"workspace & team.json","provider":"codex","auth_index":"auth-index","source":"file","runtime_only":false}]}"#)
                }
                return (status, body)
            }
            do {
                try await client.removeCredential(account())
                XCTFail("Expected removal response to be rejected")
            } catch {
                if status == 500 {
                    guard case LocalClientError.http(500) = error else { return XCTFail("Unexpected error: \(error)") }
                }
            }
        }
    }

    func testNormalAccountFetchEndpointsRemainGET() async throws {
        let client = try client { request in
            XCTAssertEqual(request.httpMethod, "GET")
            if request.url!.path.hasSuffix("auth-files") { return (200, #"{"files":[]}"#) }
            if request.url!.path.hasSuffix("gemini-api-key") { return (200, #"{"gemini-api-key":[]}"#) }
            if request.url!.path.hasSuffix("usage-queue") { return (200, "[]") }
            if request.url!.path.hasSuffix("quota/providers") { return (200, #"{"providers":[]}"#) }
            return (404, "{}")
        }
        _ = try await client.fetch()
        _ = try await client.fetchUsageEvents()
        _ = try await client.fetchQuotaProviders()
    }
}
