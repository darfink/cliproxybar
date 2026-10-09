import Foundation
import XCTest
@testable import MenuBar

final class NotificationCallbackTests: XCTestCase {
    // Like UNNotificationSettings in older SDKs, this object is not Sendable.
    private final class Settings {
        let authorization: Int
        init(authorization: Int) { self.authorization = authorization }
    }
    private enum Failure: Error { case service }

    @MainActor
    func testSettingsReplyConstructedOnMainActorAcceptsBackgroundSDKObject() async {
        let status: Int = await withCheckedContinuation { continuation in
            let reply = NotificationCallbackBridge.value(continuation) { (settings: Settings) in
                XCTAssertFalse(Thread.isMainThread)
                return settings.authorization
            }
            DispatchQueue.global().async { reply(Settings(authorization: 2)) }
        }
        XCTAssertEqual(status, 2)
    }

    @MainActor
    func testPermissionRepliesCanArriveOnBackgroundQueue() async throws {
        for granted in [false, true] {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let reply = NotificationCallbackBridge.authorization(continuation)
                DispatchQueue.global().async { reply(granted, nil) }
            }
        }
    }

    @MainActor
    func testDeliveryReplyCanArriveOnBackgroundQueue() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let reply = NotificationCallbackBridge.completion(continuation)
            DispatchQueue.global().async { reply(nil) }
        }
    }

    @MainActor
    func testBackgroundServiceErrorsReachTheAwaitingCaller() async {
        for permissionRequest in [false, true] {
            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    if permissionRequest {
                        let reply = NotificationCallbackBridge.authorization(continuation)
                        DispatchQueue.global().async { reply(false, Failure.service) }
                    } else {
                        let reply = NotificationCallbackBridge.completion(continuation)
                        DispatchQueue.global().async { reply(Failure.service) }
                    }
                }
                XCTFail("Expected the service error")
            } catch {
                XCTAssertEqual(error as? Failure, .service)
            }
        }
    }
}
