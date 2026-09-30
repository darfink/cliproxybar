import XCTest
import CLIProxyBarCore
@testable import MenuBar

final class ResetCreditsTests: XCTestCase {
    func quota(_ raw: Any?) throws -> ProviderQuota {
        var response: [String: Any] = ["rate_limit": ["primary_window": ["used_percent": 39, "limit_window_seconds": 604800]]]
        if let raw { response["rate_limit_reset_credits"] = ["available_count": raw] }
        return try ActiveQuotaParser.parse(JSONSerialization.data(withJSONObject: response), provider: "codex")
    }
    func testParsesZeroAndPositiveCountsAndPersistsInCacheModel() throws {
        for count in [0, 1, 2] {
            let parsed = try quota(count)
            XCTAssertEqual(parsed.availableResetCredits, count)
            let restored = try JSONDecoder().decode(ProviderQuota.self, from: JSONEncoder().encode(parsed))
            XCTAssertEqual(restored.availableResetCredits, count)
        }
        XCTAssertEqual(try quota("2").availableResetCredits, 2)
    }
    func testMissingAndInvalidCountsStayUnknown() throws {
        XCTAssertNil(try quota(nil).availableResetCredits)
        for value: Any in [NSNull(), true, -1, 1.5, "invalid", "NaN", "1e100"] {
            XCTAssertNil(try quota(value).availableResetCredits)
        }
    }
    func testOldCacheWithoutResetCountStillDecodes() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(quota(2))) as? [String: Any])
        json.removeValue(forKey: "availableResetCredits")
        let restored = try JSONDecoder().decode(ProviderQuota.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(restored.availableResetCredits)
        XCTAssertFalse(restored.models.isEmpty)
    }
}
