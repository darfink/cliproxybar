import XCTest
import CLIProxyBarCore
@testable import MenuBar

final class GeminiAPIKeyTests: XCTestCase {
    private func client(_ reply: @escaping @Sendable (URLRequest) throws -> (Int, String)) throws -> LocalProxyClient {
        var client = try LocalProxyClient(endpoint: "https://proxy.example.test/prefix")
        client.managementKey = { "fixture-management-key" }
        client.transport = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-management-key")
            XCTAssertEqual(request.httpMethod, "GET")
            let (status, body) = try reply(request)
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        return client
    }

    func testConfigurationKeyAppearsAlongsideOAuthAccountsWithoutRetainingTheKey() async throws {
        let client = try client { request in
            switch request.url?.path {
            case "/prefix/v0/management/auth-files":
                return (200, #"{"files":[{"name":"fixture.json","provider":"codex","auth_index":"oauth-index"}]}"#)
            case "/prefix/v0/management/gemini-api-key":
                return (200, #"{"gemini-api-key":[{"api-key":"provider-secret-not-to-retain","auth-index":"gemini-index"}]}"#)
            default: throw LocalClientError.http(404)
            }
        }
        let accounts = try await client.fetch()
        XCTAssertEqual(accounts.map(\.provider), ["codex", "gemini"])
        let gemini = try XCTUnwrap(accounts.last)
        XCTAssertEqual(gemini.auth_index, "gemini-index")
        XCTAssertEqual(gemini.displayName, "Google AI Studio")
        XCTAssertFalse(gemini.name.contains("gemini-index"))
        XCTAssertFalse(ActiveQuotaParser.supports(gemini, pluginProviders: []))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = QuotaCache(endpoint: "https://proxy.example.test", directory: directory)
        try cache.save(accounts)
        let saved = try String(contentsOf: cache.url, encoding: .utf8)
        XCTAssertFalse(saved.contains("provider-secret-not-to-retain"))
        XCTAssertFalse(saved.contains("gemini-index"))
        XCTAssertEqual(try cache.load().last?.displayName, "Google AI Studio")
    }

    func testRegisteredKeysAreNotDuplicatedAndMissingIndicesStayHidden() async throws {
        let client = try client { request in
            if request.url!.path.hasSuffix("auth-files") {
                return (200, #"{"files":[{"name":"native-entry","provider":"gemini","auth_index":"same-index"}]}"#)
            }
            return (200, #"{"gemini-api-key":[{"auth-index":"same-index"},{"auth-index":" "},{"api-key":"not-registered"},{"auth-index":"different-index","label":"Work","disabled":true}]}"#)
        }
        let accounts = try await client.fetch()
        XCTAssertEqual(accounts.count, 2)
        XCTAssertEqual(accounts.first?.name, "native-entry")
        XCTAssertEqual(accounts.last?.displayName, "Work")
        XCTAssertEqual(accounts.last?.disabled, true)
    }

    func testIdentitiesSurviveKeyReordering() async throws {
        var identities: [Set<String>] = []
        for body in [#"{"gemini-api-key":[{"auth-index":"first"},{"auth-index":"second"}]}"#,
                     #"{"gemini-api-key":[{"auth-index":"second"},{"auth-index":"first"}]}"#] {
            let client = try client { request in
                (200, request.url!.path.hasSuffix("auth-files") ? #"{"files":[]}"# : body)
            }
            identities.append(Set(try await client.fetch().map(\.name)))
        }
        XCTAssertEqual(identities[0], identities[1])
    }

    func testOlderBackendsKeepTheirAccountList() async throws {
        for status in [404, 501] {
            let client = try client { request in
                request.url!.path.hasSuffix("auth-files")
                    ? (200, #"{"files":[{"name":"fixture","provider":"claude"}]}"#) : (status, "{}")
            }
            let accounts = try await client.fetch()
            XCTAssertEqual(accounts.map(\.provider), ["claude"])
        }
    }

    func testCredentialDiscoveryFailuresDoNotSilentlyErasePreviousKeys() async throws {
        for status in [401, 403, 503] {
            let client = try client { request in
                request.url!.path.hasSuffix("auth-files") ? (200, #"{"files":[]}"#) : (status, "{}")
            }
            do { _ = try await client.fetch(); XCTFail("Expected discovery failure") }
            catch LocalClientError.http(let actual) { XCTAssertEqual(actual, status) }
        }
    }
}
