import XCTest
@testable import RemoteOrbit

final class DualReceiverVoiceGestureRecognizerTests: XCTestCase {
    func testDirectHoldAt350MillisecondsClassifiesAExactlyOnce() {
        let fixture = makeFixture()
        let gestureID = requiredGestureID(fixture.recognizer.handleDown(at: 10.0))

        fixture.scheduler.advance(to: 10.349)
        XCTAssertTrue(fixture.events.isEmpty)
        XCTAssertEqual(fixture.recognizer.stateForTesting, .firstPressPending)

        fixture.scheduler.advance(to: 10.350)

        XCTAssertEqual(
            fixture.events,
            [.classified(gestureID: gestureID, receiver: .a)]
        )
        XCTAssertEqual(fixture.recognizer.stateForTesting, .activeA)

        fixture.scheduler.advance(to: 10.700)
        XCTAssertEqual(fixture.events.count, 1)
        XCTAssertEqual(fixture.recognizer.handleUp(at: 10.710), gestureID)
        XCTAssertEqual(fixture.recognizer.stateForTesting, .idle)
    }

    func test349MillisecondFirstReleaseDoesNotClassifyAndExpiresAsNoAction() {
        let fixture = makeFixture()
        let gestureID = requiredGestureID(fixture.recognizer.handleDown(at: 20.0))

        fixture.scheduler.advance(to: 20.349)
        XCTAssertEqual(fixture.recognizer.handleUp(at: 20.349), gestureID)
        XCTAssertTrue(fixture.events.isEmpty)
        XCTAssertEqual(fixture.recognizer.stateForTesting, .awaitingSecondPress)

        fixture.scheduler.advance(to: 20.650)

        XCTAssertEqual(fixture.events, [.noAction(gestureID: gestureID)])
        XCTAssertEqual(fixture.recognizer.stateForTesting, .idle)
    }

    func testSingleQuickTapResolvesToNoActionAfterDoubleWindow() {
        let fixture = makeFixture()
        let gestureID = requiredGestureID(fixture.recognizer.handleDown(at: 30.0))
        XCTAssertEqual(fixture.recognizer.handleUp(at: 30.050), gestureID)

        fixture.scheduler.advance(to: 30.351)

        XCTAssertEqual(fixture.events, [.noAction(gestureID: gestureID)])
        XCTAssertEqual(fixture.recognizer.stateForTesting, .idle)
    }

    func testTwoQuickTapsResolveToNoActionWithoutReceiverClassification() {
        let fixture = makeFixture()
        let firstGestureID = requiredGestureID(
            fixture.recognizer.handleDown(at: 40.0)
        )
        XCTAssertEqual(fixture.recognizer.handleUp(at: 40.050), firstGestureID)

        XCTAssertEqual(fixture.recognizer.handleDown(at: 40.200), firstGestureID)
        XCTAssertEqual(fixture.recognizer.stateForTesting, .secondPressPending)
        XCTAssertEqual(fixture.recognizer.handleUp(at: 40.250), firstGestureID)

        XCTAssertEqual(fixture.events, [.noAction(gestureID: firstGestureID)])
        XCTAssertEqual(fixture.recognizer.stateForTesting, .idle)
    }

    func testSecondDownAt299MillisecondsCanClassifyB() {
        assertSecondDown(offsetAfterFirstRelease: 0.299, expectedReceiver: .b)
    }

    func testSecondDownAt300MillisecondsCanClassifyB() {
        assertSecondDown(offsetAfterFirstRelease: 0.300, expectedReceiver: .b)
    }

    func testSecondDownAt301MillisecondsStartsANewDirectGestureNotB() {
        let fixture = makeFixture()
        let firstGestureID = requiredGestureID(
            fixture.recognizer.handleDown(at: 50.0)
        )
        XCTAssertEqual(fixture.recognizer.handleUp(at: 50.050), firstGestureID)

        fixture.scheduler.advance(to: 50.351)
        XCTAssertEqual(fixture.events, [.noAction(gestureID: firstGestureID)])

        let nextGestureID = requiredGestureID(
            fixture.recognizer.handleDown(at: 50.351)
        )
        XCTAssertNotEqual(nextGestureID, firstGestureID)
        fixture.scheduler.advance(to: 50.701)

        XCTAssertEqual(
            fixture.events,
            [
                .noAction(gestureID: firstGestureID),
                .classified(gestureID: nextGestureID, receiver: .a),
            ]
        )
        XCTAssertFalse(
            fixture.events.contains(.classified(gestureID: firstGestureID, receiver: .b))
        )
    }

    func testSecondReleaseAt349MillisecondsProducesNoReceiver() {
        let fixture = makeFixture()
        let gestureID = requiredGestureID(fixture.recognizer.handleDown(at: 60.0))
        XCTAssertEqual(fixture.recognizer.handleUp(at: 60.050), gestureID)
        XCTAssertEqual(fixture.recognizer.handleDown(at: 60.150), gestureID)

        fixture.scheduler.advance(to: 60.499)
        XCTAssertEqual(fixture.recognizer.handleUp(at: 60.499), gestureID)

        XCTAssertEqual(fixture.events, [.noAction(gestureID: gestureID)])
        XCTAssertEqual(fixture.recognizer.stateForTesting, .idle)
    }

    func testSecondHoldAt350MillisecondsClassifiesBExactlyOnce() {
        let fixture = makeFixture()
        let gestureID = requiredGestureID(fixture.recognizer.handleDown(at: 70.0))
        XCTAssertEqual(fixture.recognizer.handleUp(at: 70.050), gestureID)
        XCTAssertEqual(fixture.recognizer.handleDown(at: 70.200), gestureID)

        fixture.scheduler.advance(to: 70.550)

        XCTAssertEqual(
            fixture.events,
            [.classified(gestureID: gestureID, receiver: .b)]
        )
        XCTAssertEqual(fixture.recognizer.stateForTesting, .activeB)
        XCTAssertEqual(fixture.recognizer.handleUp(at: 70.560), gestureID)
        XCTAssertEqual(fixture.events.count, 1)
    }

    func testCancelledStaleTimerCannotClassifyANewerGesture() {
        let fixture = makeFixture()
        _ = fixture.recognizer.handleDown(at: 80.0)
        fixture.recognizer.cancel()
        let newGestureID = requiredGestureID(
            fixture.recognizer.handleDown(at: 81.0)
        )

        fixture.scheduler.fireCancelledTask(at: 0)
        XCTAssertTrue(fixture.events.isEmpty)

        fixture.scheduler.advance(to: 81.350)

        XCTAssertEqual(
            fixture.events,
            [.classified(gestureID: newGestureID, receiver: .a)]
        )
    }

    func testCancelWhileAwaitingSecondPressClearsWithoutClassification() {
        let fixture = makeFixture()
        let gestureID = requiredGestureID(fixture.recognizer.handleDown(at: 90.0))
        XCTAssertEqual(fixture.recognizer.handleUp(at: 90.050), gestureID)

        fixture.recognizer.cancel()
        fixture.scheduler.advance(to: 91.0)

        XCTAssertEqual(fixture.events, [])
        XCTAssertEqual(fixture.recognizer.stateForTesting, .idle)
    }

    private func assertSecondDown(
        offsetAfterFirstRelease: TimeInterval,
        expectedReceiver: DualReceiverVoiceGestureRecognizer.Receiver
    ) {
        let fixture = makeFixture()
        let firstDown = 100.0
        let firstUp = firstDown + 0.050
        let gestureID = requiredGestureID(
            fixture.recognizer.handleDown(at: firstDown)
        )
        XCTAssertEqual(fixture.recognizer.handleUp(at: firstUp), gestureID)

        let secondDown = firstUp + offsetAfterFirstRelease
        fixture.scheduler.advance(to: secondDown)
        XCTAssertEqual(fixture.recognizer.handleDown(at: secondDown), gestureID)
        fixture.scheduler.advance(to: secondDown + 0.350)

        XCTAssertEqual(
            fixture.events,
            [.classified(gestureID: gestureID, receiver: expectedReceiver)]
        )
    }

    private func makeFixture() -> Fixture {
        let scheduler = FakeScheduler()
        let recorder = EventRecorder()
        let recognizer = DualReceiverVoiceGestureRecognizer(
            monotonicNow: { scheduler.now },
            schedule: { delay, work in
                scheduler.schedule(after: delay, work: work)
            }
        )
        recognizer.onEvent = { recorder.events.append($0) }
        return Fixture(
            recognizer: recognizer,
            scheduler: scheduler,
            recorder: recorder
        )
    }

    private func requiredGestureID(
        _ gestureID: UUID?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> UUID {
        guard let gestureID else {
            XCTFail("Expected a gesture ID", file: file, line: line)
            return UUID()
        }
        return gestureID
    }

    private struct Fixture {
        let recognizer: DualReceiverVoiceGestureRecognizer
        let scheduler: FakeScheduler
        let recorder: EventRecorder

        var events: [DualReceiverVoiceGestureRecognizer.Event] {
            recorder.events
        }
    }

    private final class EventRecorder {
        var events: [DualReceiverVoiceGestureRecognizer.Event] = []
    }

    private final class FakeScheduler {
        private final class Entry {
            let id = UUID()
            let deadline: TimeInterval
            let work: () -> Void
            var cancelled = false
            var fired = false

            init(deadline: TimeInterval, work: @escaping () -> Void) {
                self.deadline = deadline
                self.work = work
            }
        }

        private(set) var now: TimeInterval = 0
        private var entries: [Entry] = []

        func schedule(after delay: TimeInterval, work: @escaping () -> Void) -> () -> Void {
            let entry = Entry(deadline: now + delay, work: work)
            entries.append(entry)
            return { [weak entry] in entry?.cancelled = true }
        }

        func advance(to target: TimeInterval) {
            precondition(target >= now)
            while let next = entries
                .filter({ !$0.cancelled && !$0.fired && $0.deadline <= target })
                .min(by: { $0.deadline < $1.deadline }) {
                next.fired = true
                now = next.deadline
                next.work()
            }
            now = target
        }

        func fireCancelledTask(at index: Int) {
            let entry = entries[index]
            precondition(entry.cancelled && !entry.fired)
            entry.fired = true
            now = max(now, entry.deadline)
            entry.work()
        }
    }
}
