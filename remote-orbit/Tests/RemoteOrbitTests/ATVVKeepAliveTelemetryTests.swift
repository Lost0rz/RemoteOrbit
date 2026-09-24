import XCTest
@testable import RemoteOrbit

final class ATVVKeepAliveTelemetryTests: XCTestCase {
    func testV10KeepAliveBytesRetainTheActiveStreamID() throws {
        let protocolHandler = ATVVProtocol()
        try protocolHandler.acceptCapabilities(
            ATVVCapabilities(
                version: .v10,
                codecs: ATVVCodec.adpcm16k.rawValue,
                interactionModel: 0,
                frameSize: 120
            )
        )

        XCTAssertEqual(
            try protocolHandler.keepAliveCommand(streamID: 0xA5),
            Data([0x0E, 0xA5])
        )
    }

    func testKeepAliveGuardTelemetryNamesEveryRejectedState() {
        XCTAssertEqual(
            ATVVKeepAliveGuard.rejectionReasons(
                isStreaming: false,
                codecPresent: false,
                peripheralPresent: false,
                commandCharacteristicPresent: false
            ),
            [
                .notStreaming,
                .codecMissing,
                .peripheralMissing,
                .commandCharacteristicMissing
            ]
        )
    }

    func testKeepAliveTimerLifecycleTelemetryIncludesSessionAndElapsedTime() {
        let started = ATVVKeepAliveTelemetry.timerLine(
            event: "KEEPALIVE_TIMER_STARTED",
            sessionID: "session-1",
            elapsedMilliseconds: 0,
            timestampNanoseconds: 100
        )
        let fired = ATVVKeepAliveTelemetry.timerLine(
            event: "KEEPALIVE_TIMER_FIRED",
            sessionID: "session-1",
            elapsedMilliseconds: 4_001.25,
            timestampNanoseconds: 4_001_250_000
        )
        let stopped = ATVVKeepAliveTelemetry.timerLine(
            event: "KEEPALIVE_TIMER_STOPPED",
            sessionID: "session-1",
            elapsedMilliseconds: 60_051.7,
            timestampNanoseconds: 60_051_700_000
        )

        XCTAssertEqual(
            started,
            "[AUDIO-PATH] KEEPALIVE_TIMER_STARTED session_id=session-1 timestamp_monotonic_ns=100 elapsed_ms_from_AUDIO_START=0.0"
        )
        XCTAssertEqual(
            fired,
            "[AUDIO-PATH] KEEPALIVE_TIMER_FIRED session_id=session-1 timestamp_monotonic_ns=4001250000 elapsed_ms_from_AUDIO_START=4001.2"
        )
        XCTAssertEqual(
            stopped,
            "[AUDIO-PATH] KEEPALIVE_TIMER_STOPPED session_id=session-1 timestamp_monotonic_ns=60051700000 elapsed_ms_from_AUDIO_START=60051.7"
        )
    }

    func testKeepAliveAttemptTelemetryPreservesCommandAndWriteMetadata() {
        let line = ATVVKeepAliveTelemetry.attemptLine(
            sessionID: "session-1",
            elapsedMilliseconds: 8_002.0,
            sequence: 2,
            protocolVersion: "1.0",
            streamID: 0xA5,
            command: Data([0x0E, 0xA5]),
            peripheralPresent: true,
            commandCharacteristicPresent: true,
            writeType: .withoutResponse,
            canSendWriteWithoutResponse: true,
            result: .writeAttempted,
            guardReasons: []
        )

        XCTAssertTrue(line.contains("session_id=session-1"))
        XCTAssertTrue(line.contains("elapsed_ms_from_AUDIO_START=8002.0"))
        XCTAssertTrue(line.contains("keepalive_sequence=2"))
        XCTAssertTrue(line.contains("protocol_version=1.0"))
        XCTAssertTrue(line.contains("stream_id=165"))
        XCTAssertTrue(line.contains("command_hex=0e a5"))
        XCTAssertTrue(line.contains("write_type=WITHOUT_RESPONSE"))
        XCTAssertTrue(line.contains("can_send_write_without_response=YES"))
        XCTAssertTrue(line.contains("result=WRITE_ATTEMPTED"))
    }

    func testAudioStopTelemetryRetainsRawReasonAndKeepAliveDelta() {
        let line = ATVVKeepAliveTelemetry.audioStopLine(
            sessionID: "session-1",
            elapsedMilliseconds: 60_051.7,
            reason: 0x02,
            voiceKeyStillHeld: true,
            lastKeepAliveElapsedMilliseconds: 56_004.2,
            millisecondsSinceLastKeepAlive: 4_047.5
        )

        XCTAssertTrue(line.contains("reason_hex=0x02"))
        XCTAssertTrue(line.contains("voice_key_still_held=YES"))
        XCTAssertTrue(line.contains("last_keepalive_elapsed_ms=56004.2"))
        XCTAssertTrue(line.contains("milliseconds_since_last_keepalive=4047.5"))
    }

    func testSessionOriginUsesOnlyObservedHostMicOpenState() {
        XCTAssertEqual(
            ATVVKeepAliveTelemetry.sessionOrigin(
                micOpenRequested: true,
                voiceInputRequested: true
            ),
            .hostMicOpen
        )
        XCTAssertEqual(
            ATVVKeepAliveTelemetry.sessionOrigin(
                micOpenRequested: false,
                voiceInputRequested: true
            ),
            .unknown
        )
        XCTAssertEqual(
            ATVVKeepAliveTelemetry.sessionOrigin(
                micOpenRequested: false,
                voiceInputRequested: false
            ),
            .physicalHTT
        )
    }
}
