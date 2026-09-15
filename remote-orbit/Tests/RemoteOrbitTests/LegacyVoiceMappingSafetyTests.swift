import XCTest
@testable import RemoteOrbit

final class LegacyVoiceMappingSafetyTests: XCTestCase {
    func testMappingSafetyIsFailClosedUntilTheLatestClearSucceeds() {
        var safety = LegacyVoiceMappingSafety()

        XCTAssertFalse(safety.isSafe)

        safety.recordClearResult(false)
        XCTAssertFalse(safety.isSafe)

        safety.recordClearResult(true)
        XCTAssertTrue(safety.isSafe)

        safety.recordClearResult(false)
        XCTAssertFalse(safety.isSafe)
    }
}
