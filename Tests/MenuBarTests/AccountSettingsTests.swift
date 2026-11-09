import AppKit
import SwiftUI
import XCTest
@testable import MenuBar

private actor RemovalGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var started = false
    func wait() async {
        started = true
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
}

final class AccountSettingsTests: XCTestCase {
    private func client(endpoint: String = "https://proxy.example.test", removalStatus: Int = 200,
                        gate: RemovalGate? = nil) throws -> LocalProxyClient {
        var client = try LocalProxyClient(endpoint: endpoint)
        client.managementKey = { "fixture" }
        client.transport = { request in
            let status: Int
            let body: String
            if request.httpMethod == "DELETE" {
                await gate?.wait()
                status = removalStatus
                body = #"{"status":"ok"}"#
            } else if request.url!.path.hasSuffix("auth-files") {
                status = 200
                body = #"{"files":[{"name":"account.json","provider":"codex","source":"file","runtime_only":false,"auth_index":"account-index"}]}"#
            } else { status = 200; body = #"{"gemini-api-key":[]}"# }
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        return client
    }

    @MainActor func testSuccessfulRemovalUpdatesRowsAndNotifiesTheApp() async throws {
        let client = try client()
        let model = AccountSettingsModel()
        await model.reload(client: client)
        let account = try XCTUnwrap(model.accounts.first)
        var calls = 0
        await model.remove(account, client: client) { removed, endpoint in
            calls += 1
            XCTAssertEqual(removed.identity, account.identity)
            XCTAssertEqual(endpoint, client.baseURL)
        }
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(model.accounts.isEmpty)
        XCTAssertNotNil(model.message)
        XCTAssertNil(model.issue)
        XCTAssertFalse(model.busy)
    }

    @MainActor func testFailedRemovalKeepsRowAndDoesNotReportSuccess() async throws {
        let client = try client(removalStatus: 500)
        let model = AccountSettingsModel()
        await model.reload(client: client)
        let account = try XCTUnwrap(model.accounts.first)
        await model.remove(account, client: client) { _, _ in XCTFail("Removal failed") }
        XCTAssertEqual(model.accounts.map(\.identity), [account.identity])
        XCTAssertNotNil(model.issue)
        XCTAssertNil(model.message)
        XCTAssertFalse(model.busy)
    }

    @MainActor func testEndpointChangeRejectsOldConfirmationAndIgnoresOldCompletion() async throws {
        let gate = RemovalGate()
        let oldClient = try client(gate: gate)
        let newClient = try client(endpoint: "https://other.example.test")
        let model = AccountSettingsModel()
        await model.reload(client: oldClient)
        let oldAccount = try XCTUnwrap(model.accounts.first)
        var completedEndpoint: URL?
        let removal = Task { await model.remove(oldAccount, client: oldClient) { _, endpoint in completedEndpoint = endpoint } }
        while !(await gate.started) { await Task.yield() }
        await model.reload(client: newClient)
        await gate.release()
        await removal.value
        XCTAssertEqual(completedEndpoint, oldClient.baseURL)
        XCTAssertEqual(model.accounts.count, 1)
        XCTAssertNil(model.message)
        XCTAssertFalse(model.busy)
        await model.remove(oldAccount, client: oldClient) { _, _ in XCTFail("Stale confirmation must not delete") }
        XCTAssertEqual(model.accounts.count, 1)
    }
    @MainActor func testAccountListFitsAndExportsOptionalPreview() async throws {
        var client = try client()
        client.transport = { request in
            let body = request.url!.path.hasSuffix("auth-files")
                ? #"{"files":[{"name":"OpenCode-Go-2.json","provider":"opencode-go","label":"Personal","source":"file","auth_index":"new"},{"name":"OpenCode-Go.json","provider":"opencode-go","label":"Personal","source":"file","auth_index":"old","disabled":true},{"name":"work-account.json","provider":"claude","email":"alex@example.com","source":"file","auth_index":"claude"},{"name":"gemini-config","provider":"gemini","label":"Google AI Studio","source":"config"}]}"#
                : #"{"gemini-api-key":[]}"#
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let model = AccountSettingsModel()
        await model.reload(client: client)
        _ = NSApplication.shared
        for (name, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
            let view = NSHostingView(rootView: AccountSettingsContent(model: model, reload: {}, remove: { _ in })
                .frame(width: 456, height: 580)
                .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, scheme))
            view.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
            view.setFrameSize(NSSize(width: 456, height: 580))
            view.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(view.fittingSize.width, 456)
            guard let path = ProcessInfo.processInfo.environment["CLIPROXYBAR_ACCOUNTS_PREVIEW"] else { continue }
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: path + "-" + name + ".png"))
        }
    }

}
