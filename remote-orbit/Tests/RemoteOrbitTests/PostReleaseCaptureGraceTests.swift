import XCTest
@testable import RemoteOrbit

final class PostReleaseCaptureGraceTests: XCTestCase {
    func testStartOwnsWaitingGraceWithoutImmediateExpiration() {
        let grace = PostReleaseCaptureGraceController()
        var expirations: [(String, UInt64)] = []
        grace.onExpire = { expirations.append(($0, $1)) }

        let generation = grace.start(sessionID: "session-a")

        XCTAssertTrue(grace.isWaitingForTesting)
        XCTAssertEqual(grace.activeSessionIDForTesting, "session-a")
        XCTAssertEqual(grace.configuredDurationForTesting, 1.0, accuracy: 0.001)
        XCTAssertTrue(expirations.isEmpty)
        XCTAssertTrue(grace.cancel(sessionID: "session-a"))
        XCTAssertFalse(grace.isWaitingForTesting)
        XCTAssertFalse(grace.expireForTesting(sessionID: "session-a", generation: generation))
    }

    func testCurrentGenerationExpiresExactlyOnce() {
        let grace = PostReleaseCaptureGraceController()
        var expirations: [(String, UInt64)] = []
        grace.onExpire = { expirations.append(($0, $1)) }

        let generation = grace.start(sessionID: "session-a")

        XCTAssertTrue(grace.expireForTesting(sessionID: "session-a", generation: generation))
        XCTAssertEqual(expirations.map(\.0), ["session-a"])
        XCTAssertFalse(grace.isWaitingForTesting)
        XCTAssertFalse(grace.expireForTesting(sessionID: "session-a", generation: generation))
        XCTAssertEqual(expirations.count, 1)
    }

    func testCancellationPreventsExpirationCallback() {
        let grace = PostReleaseCaptureGraceController()
        var expirationCount = 0
        grace.onExpire = { _, _ in expirationCount += 1 }
        let generation = grace.start(sessionID: "session-a")

        XCTAssertTrue(grace.cancel(sessionID: "session-a"))
        XCTAssertFalse(grace.cancel(sessionID: "session-a"))
        XCTAssertFalse(grace.expireForTesting(sessionID: "session-a", generation: generation))
        XCTAssertEqual(expirationCount, 0)
    }

    func testStaleGenerationCannotExpireNewSession() {
        let grace = PostReleaseCaptureGraceController()
        var expirations: [String] = []
        grace.onExpire = { (sessionID: String, _: UInt64) in
            expirations.append(sessionID)
        }

        let oldGeneration = grace.start(sessionID: "old-session")
        let newGeneration = grace.start(sessionID: "new-session")

        XCTAssertFalse(
            grace.expireForTesting(
                sessionID: "old-session",
                generation: oldGeneration
            )
        )
        XCTAssertTrue(
            grace.expireForTesting(
                sessionID: "new-session",
                generation: newGeneration
            )
        )
        XCTAssertEqual(expirations, ["new-session"])
    }

    func testMismatchedSessionCannotExpireCurrentGeneration() {
        let grace = PostReleaseCaptureGraceController()
        let generation = grace.start(sessionID: "session-a")

        XCTAssertFalse(
            grace.expireForTesting(
                sessionID: "session-b",
                generation: generation
            )
        )
        XCTAssertTrue(grace.isWaitingForTesting)
        XCTAssertTrue(grace.cancel(sessionID: "session-a"))
    }

    func testInjectedQueuePreservesOneShotGenerationSemantics() {
        let queue = DispatchQueue(label: "com.remoteorbit.tests.grace")
        let grace = PostReleaseCaptureGraceController(queue: queue)
        var expirations: [String] = []
        grace.onExpire = { sessionID, _ in expirations.append(sessionID) }

        let generation = grace.start(sessionID: "session-a")
        XCTAssertTrue(grace.expireForTesting(sessionID: "session-a", generation: generation))
        XCTAssertEqual(expirations, ["session-a"])
        XCTAssertFalse(grace.expireForTesting(sessionID: "session-a", generation: generation))
    }
}
