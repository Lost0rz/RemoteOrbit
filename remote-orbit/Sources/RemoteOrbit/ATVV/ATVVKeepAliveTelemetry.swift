import Foundation

enum ATVVKeepAliveWriteType: String {
    case withoutResponse = "WITHOUT_RESPONSE"
    case withResponse = "WITH_RESPONSE"
    case notAttempted = "NOT_ATTEMPTED"
}

enum ATVVKeepAliveAttemptResult: String {
    case writeAttempted = "WRITE_ATTEMPTED"
    case guardRejected = "GUARD_REJECTED"
    case commandBuildFailed = "COMMAND_BUILD_FAILED"
}

enum ATVVKeepAliveGuardReason: String, Equatable {
    case notStreaming = "isStreaming=false"
    case codecMissing = "codec=nil"
    case peripheralMissing = "peripheral=nil"
    case commandCharacteristicMissing = "commandChar=nil"
}

enum ATVVSessionOrigin: String, Equatable {
    case hostMicOpen = "HOST_MIC_OPEN"
    case physicalHTT = "PHYSICAL_HTT"
    case unknown = "UNKNOWN"
}

enum ATVVKeepAliveGuard {
    static func rejectionReasons(
        isStreaming: Bool,
        codecPresent: Bool,
        peripheralPresent: Bool,
        commandCharacteristicPresent: Bool
    ) -> [ATVVKeepAliveGuardReason] {
        var reasons: [ATVVKeepAliveGuardReason] = []
        if !isStreaming { reasons.append(.notStreaming) }
        if !codecPresent { reasons.append(.codecMissing) }
        if !peripheralPresent { reasons.append(.peripheralMissing) }
        if !commandCharacteristicPresent { reasons.append(.commandCharacteristicMissing) }
        return reasons
    }
}

enum ATVVKeepAliveTelemetry {
    static func timerLine(
        event: String,
        sessionID: String,
        elapsedMilliseconds: Double,
        timestampNanoseconds: UInt64
    ) -> String {
        "[AUDIO-PATH] \(event) session_id=\(sessionID) "
            + "timestamp_monotonic_ns=\(timestampNanoseconds) "
            + String(format: "elapsed_ms_from_AUDIO_START=%.1f", elapsedMilliseconds)
    }

    static func attemptLine(
        sessionID: String,
        elapsedMilliseconds: Double,
        sequence: Int,
        protocolVersion: String,
        streamID: UInt8,
        command: Data?,
        peripheralPresent: Bool,
        commandCharacteristicPresent: Bool,
        writeType: ATVVKeepAliveWriteType,
        canSendWriteWithoutResponse: Bool?,
        result: ATVVKeepAliveAttemptResult,
        guardReasons: [ATVVKeepAliveGuardReason]
    ) -> String {
        let commandHex = command.map {
            $0.map { String(format: "%02x", $0) }.joined(separator: " ")
        } ?? "NA"
        let reasons = guardReasons.map(\.rawValue).joined(separator: ",")
        let canSend = canSendWriteWithoutResponse.map { $0 ? "YES" : "NO" } ?? "UNAVAILABLE"
        return "[AUDIO-PATH] ATVV_KEEPALIVE "
            + "session_id=\(sessionID) "
            + String(format: "elapsed_ms_from_AUDIO_START=%.1f ", elapsedMilliseconds)
            + "keepalive_sequence=\(sequence) "
            + "protocol_version=\(protocolVersion) "
            + "stream_id=\(streamID) "
            + "command_hex=\(commandHex) "
            + "command_characteristic_present=\(commandCharacteristicPresent ? "YES" : "NO") "
            + "peripheral_present=\(peripheralPresent ? "YES" : "NO") "
            + "write_type=\(writeType.rawValue) "
            + "can_send_write_without_response=\(canSend) "
            + "result=\(result.rawValue) "
            + "guard_reasons=\(reasons.isEmpty ? "none" : reasons)"
    }

    static func audioStopLine(
        sessionID: String,
        elapsedMilliseconds: Double,
        reason: UInt8,
        voiceKeyStillHeld: Bool,
        lastKeepAliveElapsedMilliseconds: Double?,
        millisecondsSinceLastKeepAlive: Double?
    ) -> String {
        "[AUDIO-PATH] ATVV_AUDIO_STOP session_id=\(sessionID) "
            + String(format: "elapsed_ms_from_AUDIO_START=%.1f ", elapsedMilliseconds)
            + "reason_hex=0x\(String(format: "%02x", reason)) "
            + "voice_key_still_held=\(voiceKeyStillHeld ? "YES" : "NO") "
            + "last_keepalive_elapsed_ms=\(formatElapsed(lastKeepAliveElapsedMilliseconds)) "
            + "milliseconds_since_last_keepalive=\(formatElapsed(millisecondsSinceLastKeepAlive))"
    }

    static func sessionOrigin(
        micOpenRequested: Bool,
        voiceInputRequested: Bool
    ) -> ATVVSessionOrigin {
        if micOpenRequested { return .hostMicOpen }
        if voiceInputRequested { return .unknown }
        return .physicalHTT
    }

    private static func formatElapsed(_ value: Double?) -> String {
        value.map { String(format: "%.1f", $0) } ?? "n/a"
    }
}
