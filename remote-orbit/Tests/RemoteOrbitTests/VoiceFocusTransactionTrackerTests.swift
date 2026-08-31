import XCTest
@testable import RemoteOrbit

final class VoiceFocusTransactionTrackerTests: XCTestCase {
    func testOnlyActiveGestureCanCompleteTransaction() {
        let tracker = VoiceFocusTransactionTracker()
        let first = UUID()
        let second = UUID()

        XCTAssertNil(tracker.begin(first))
        XCTAssertEqual(tracker.begin(second), first)
        XCTAssertFalse(tracker.complete(first))
        XCTAssertEqual(tracker.activeGestureID, second)
        XCTAssertTrue(tracker.complete(second))
        XCTAssertNil(tracker.activeGestureID)
    }

    func testCancellationCannotClearNewerGesture() {
        let tracker = VoiceFocusTransactionTracker()
        let first = UUID()
        let second = UUID()

        tracker.begin(first)
        tracker.begin(second)

        XCTAssertFalse(tracker.cancel(first))
        XCTAssertEqual(tracker.activeGestureID, second)
        XCTAssertTrue(tracker.cancel(second))
        XCTAssertNil(tracker.activeGestureID)
    }
}
