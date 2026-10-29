import Darwin
import Foundation

enum DiagnosticSeverity: String, Codable, CaseIterable, Sendable {
    case debug
    case info
    case warning
    case error
    case critical
}

enum DiagnosticSchemaError: Error, Equatable {
    case unsupportedVersion(Int)
    case invalidInput(String)
}

/// A source-native timestamp is preserved separately from the Authority's
/// canonical timestamp. Consumers must not compare it without its domain and
/// unit; a conversion ratio is included when the source uses a timebase.
struct DiagnosticRawTimestamp: Codable, Equatable, Sendable {
    let value: UInt64
    let unit: String
    let clockDomain: String
    let timebaseNumerator: UInt32?
    let timebaseDenominator: UInt32?

    enum CodingKeys: String, CodingKey {
        case value
        case unit
        case clockDomain = "clock_domain"
        case timebaseNumerator = "timebase_numerator"
        case timebaseDenominator = "timebase_denominator"
    }

    init(
        value: UInt64,
        unit: String,
        clockDomain: String,
        timebaseNumerator: UInt32? = nil,
        timebaseDenominator: UInt32? = nil
    ) {
        self.value = value
        self.unit = unit
        self.clockDomain = clockDomain
        self.timebaseNumerator = timebaseNumerator
        self.timebaseDenominator = timebaseDenominator
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let value = try values.decode(UInt64.self, forKey: .value)
        let unit = try values.decode(String.self, forKey: .unit)
        let clockDomain = try values.decode(String.self, forKey: .clockDomain)
        let numerator = try values.decodeIfPresent(UInt32.self, forKey: .timebaseNumerator)
        let denominator = try values.decodeIfPresent(UInt32.self, forKey: .timebaseDenominator)
        guard DiagnosticContractValidation.isToken(unit),
              DiagnosticContractValidation.isToken(clockDomain),
              (numerator == nil) == (denominator == nil),
              numerator != 0,
              denominator != 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .clockDomain,
                in: values,
                debugDescription: "Invalid source timestamp provenance"
            )
        }
        self.value = value
        self.unit = unit
        self.clockDomain = clockDomain
        self.timebaseNumerator = numerator
        self.timebaseDenominator = denominator
    }
}

struct DiagnosticMonotonicTimestamp: Codable, Equatable, Sendable {
    let valueNanoseconds: UInt64
    let clockDomain: String
    let rawTicks: UInt64
    let timebaseNumerator: UInt32
    let timebaseDenominator: UInt32

    enum CodingKeys: String, CodingKey {
        case valueNanoseconds = "value_nanoseconds"
        case clockDomain = "clock_domain"
        case rawTicks = "raw_ticks"
        case timebaseNumerator = "timebase_numerator"
        case timebaseDenominator = "timebase_denominator"
    }

    init(
        valueNanoseconds: UInt64,
        clockDomain: String,
        rawTicks: UInt64,
        timebaseNumerator: UInt32,
        timebaseDenominator: UInt32
    ) {
        self.valueNanoseconds = valueNanoseconds
        self.clockDomain = clockDomain
        self.rawTicks = rawTicks
        self.timebaseNumerator = timebaseNumerator
        self.timebaseDenominator = timebaseDenominator
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let nanoseconds = try values.decode(UInt64.self, forKey: .valueNanoseconds)
        let clockDomain = try values.decode(String.self, forKey: .clockDomain)
        let rawTicks = try values.decode(UInt64.self, forKey: .rawTicks)
        let numerator = try values.decode(UInt32.self, forKey: .timebaseNumerator)
        let denominator = try values.decode(UInt32.self, forKey: .timebaseDenominator)
        guard clockDomain == "mach_continuous_time",
              numerator > 0,
              denominator > 0,
              Self.convert(rawTicks: rawTicks, numerator: numerator, denominator: denominator)
                == nanoseconds else {
            throw DecodingError.dataCorruptedError(
                forKey: .clockDomain,
                in: values,
                debugDescription: "Invalid canonical monotonic timestamp provenance"
            )
        }
        self.valueNanoseconds = nanoseconds
        self.clockDomain = clockDomain
        self.rawTicks = rawTicks
        self.timebaseNumerator = numerator
        self.timebaseDenominator = denominator
    }

    private static func convert(rawTicks: UInt64, numerator: UInt32, denominator: UInt32) -> UInt64 {
        let product = rawTicks.multipliedFullWidth(by: UInt64(numerator))
        let divisor = UInt64(denominator)
        guard product.high < divisor else { return UInt64.max }
        return divisor.dividingFullWidth((high: product.high, low: product.low)).quotient
    }
}

struct DiagnosticClockStamp: Codable, Equatable, Sendable {
    /// Unix milliseconds are absolute wall time for display and cross-process
    /// correlation. Duration calculations use only the declared monotonic clock.
    let wallTimestampUnixMilliseconds: Int64
    let monotonic: DiagnosticMonotonicTimestamp

    enum CodingKeys: String, CodingKey {
        case wallTimestampUnixMilliseconds = "wall_timestamp_unix_ms"
        case monotonic
    }
}

protocol DiagnosticClock: Sendable {
    func capture() -> DiagnosticClockStamp
}

struct SystemDiagnosticClock: DiagnosticClock {
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    func capture() -> DiagnosticClockStamp {
        let rawTicks = mach_continuous_time()
        let numerator = max(Self.timebase.numer, 1)
        let denominator = max(Self.timebase.denom, 1)
        let product = rawTicks.multipliedFullWidth(by: UInt64(numerator))
        let divisor = UInt64(denominator)
        let nanoseconds = product.high >= divisor
            ? UInt64.max
            : divisor.dividingFullWidth((high: product.high, low: product.low)).quotient

        return DiagnosticClockStamp(
            wallTimestampUnixMilliseconds: Int64(
                (Date().timeIntervalSince1970 * 1_000).rounded(.down)
            ),
            monotonic: DiagnosticMonotonicTimestamp(
                valueNanoseconds: nanoseconds,
                clockDomain: "mach_continuous_time",
                rawTicks: rawTicks,
                timebaseNumerator: numerator,
                timebaseDenominator: denominator
            )
        )
    }
}

enum DiagnosticJSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case integer(Int64)
    case unsignedInteger(UInt64)
    case double(Double)
    case string(String)
    case array([DiagnosticJSONValue])
    case object([String: DiagnosticJSONValue])

    private struct DynamicKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }
    }

    init(from decoder: Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: DynamicKey.self) {
            var result: [String: DiagnosticJSONValue] = [:]
            for key in keyed.allKeys {
                result[key.stringValue] = try keyed.decode(
                    DiagnosticJSONValue.self,
                    forKey: key
                )
            }
            self = .object(result)
            return
        }

        if var unkeyed = try? decoder.unkeyedContainer() {
            var result: [DiagnosticJSONValue] = []
            while !unkeyed.isAtEnd {
                result.append(try unkeyed.decode(DiagnosticJSONValue.self))
            }
            self = .array(result)
            return
        }

        let value = try decoder.singleValueContainer()
        if value.decodeNil() {
            self = .null
        } else if let decoded = try? value.decode(Bool.self) {
            self = .bool(decoded)
        } else if let decoded = try? value.decode(Int64.self) {
            self = .integer(decoded)
        } else if let decoded = try? value.decode(UInt64.self) {
            self = .unsignedInteger(decoded)
        } else if let decoded = try? value.decode(Double.self) {
            self = .double(decoded)
        } else if let decoded = try? value.decode(String.self) {
            self = .string(decoded)
        } else {
            throw DecodingError.dataCorruptedError(
                in: value,
                debugDescription: "Unsupported diagnostic JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .null:
            var value = encoder.singleValueContainer()
            try value.encodeNil()
        case .bool(let item):
            var value = encoder.singleValueContainer()
            try value.encode(item)
        case .integer(let item):
            var value = encoder.singleValueContainer()
            try value.encode(item)
        case .unsignedInteger(let item):
            var value = encoder.singleValueContainer()
            try value.encode(item)
        case .double(let item):
            var value = encoder.singleValueContainer()
            try value.encode(item)
        case .string(let item):
            var value = encoder.singleValueContainer()
            try value.encode(item)
        case .array(let items):
            var values = encoder.unkeyedContainer()
            for item in items {
                try values.encode(item)
            }
        case .object(let items):
            var values = encoder.container(keyedBy: DynamicKey.self)
            for (key, item) in items {
                guard let codingKey = DynamicKey(stringValue: key) else {
                    throw DiagnosticSchemaError.invalidInput("invalid payload key")
                }
                try values.encode(item, forKey: codingKey)
            }
        }
    }
}

struct DiagnosticRuntimeContext: Equatable, Sendable {
    let processInstanceID: UUID
    let processID: Int32
    let binaryPath: String
    let appVersion: String
    let buildVersion: String
    let sourceRevision: String?

    static func current(bundle: Bundle = .main) -> DiagnosticRuntimeContext {
        let revision = bundle.object(
            forInfoDictionaryKey: "RemoteOrbitDiagnosticSourceHead"
        ) as? String

        return DiagnosticRuntimeContext(
            processInstanceID: UUID(),
            processID: ProcessInfo.processInfo.processIdentifier,
            binaryPath: CommandLine.arguments.first ?? "unknown",
            appVersion: bundle.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "unknown",
            buildVersion: bundle.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String ?? "unknown",
            sourceRevision: revision.flatMap {
                $0.isEmpty || $0 == "UNSTAMPED" ? nil : $0
            }
        )
    }
}

struct DiagnosticEventInput: Equatable, Sendable {
    let eventType: String
    let subsystem: String
    let category: String
    let severity: DiagnosticSeverity
    let sourceComponent: String
    let sessionID: String?
    let incidentID: String?
    let correlationID: String?
    let interactionID: String?
    let deviceID: String?
    let slotID: String?
    let navigationID: String?
    let sourceTimestamp: DiagnosticRawTimestamp?
    let payload: [String: DiagnosticJSONValue]

    init(
        eventType: String,
        subsystem: String,
        category: String,
        severity: DiagnosticSeverity,
        sourceComponent: String,
        sessionID: String? = nil,
        incidentID: String? = nil,
        correlationID: String? = nil,
        interactionID: String? = nil,
        deviceID: String? = nil,
        slotID: String? = nil,
        navigationID: String? = nil,
        sourceTimestamp: DiagnosticRawTimestamp? = nil,
        payload: [String: DiagnosticJSONValue] = [:]
    ) throws {
        guard DiagnosticContractValidation.isToken(eventType),
              DiagnosticContractValidation.isToken(subsystem),
              DiagnosticContractValidation.isToken(category),
              DiagnosticContractValidation.isToken(sourceComponent) else {
            throw DiagnosticSchemaError.invalidInput("invalid event identity")
        }
        for identifier in [sessionID, incidentID, correlationID, interactionID, deviceID, slotID, navigationID] {
            guard DiagnosticContractValidation.isOpaqueIdentifier(identifier) else {
                throw DiagnosticSchemaError.invalidInput("invalid correlation identifier")
            }
        }
        guard DiagnosticEventCatalog.accepts(
            eventType: eventType,
            subsystem: subsystem,
            category: category,
            severity: severity,
            sourceComponent: sourceComponent,
            payload: payload
        ) else {
            throw DiagnosticSchemaError.invalidInput("event does not match its registered payload schema")
        }
        if let sourceTimestamp {
            guard DiagnosticContractValidation.isToken(sourceTimestamp.unit),
                  DiagnosticContractValidation.isToken(sourceTimestamp.clockDomain),
                  (sourceTimestamp.timebaseNumerator == nil)
                    == (sourceTimestamp.timebaseDenominator == nil),
                  sourceTimestamp.timebaseNumerator != 0,
                  sourceTimestamp.timebaseDenominator != 0 else {
                throw DiagnosticSchemaError.invalidInput("invalid source timestamp")
            }
        }

        self.eventType = eventType
        self.subsystem = subsystem
        self.category = category
        self.severity = severity
        self.sourceComponent = sourceComponent
        self.sessionID = sessionID
        self.incidentID = incidentID
        self.correlationID = correlationID
        self.interactionID = interactionID
        self.deviceID = deviceID
        self.slotID = slotID
        self.navigationID = navigationID
        self.sourceTimestamp = sourceTimestamp
        self.payload = payload
    }
}

fileprivate enum DiagnosticContractValidation {
    static func isToken(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard !bytes.isEmpty, bytes.count <= 128,
              bytes[0] >= 97, bytes[0] <= 122 else { return false }
        return bytes.allSatisfy { byte in
            (byte >= 97 && byte <= 122)
                || (byte >= 48 && byte <= 57)
                || byte == 45 || byte == 46 || byte == 95
        }
    }

    static func isOpaqueIdentifier(_ value: String?) -> Bool {
        guard let value else { return true }
        return !value.isEmpty && value.utf8.count <= 256
    }

    static func isValidPayload(_ payload: [String: DiagnosticJSONValue]) -> Bool {
        guard payload.count <= 128 else { return false }
        return payload.allSatisfy { key, value in
            !key.isEmpty && key.utf8.count <= 128 && isValid(value, depth: 0)
        }
    }

    private static func isValid(_ value: DiagnosticJSONValue, depth: Int) -> Bool {
        guard depth <= 8 else { return false }
        switch value {
        case .null, .bool, .integer, .unsignedInteger:
            return true
        case .double(let number):
            return number.isFinite
        case .string(let string):
            return string.utf8.count <= 4_096
        case .array(let values):
            return values.count <= 128 && values.allSatisfy { isValid($0, depth: depth + 1) }
        case .object(let values):
            return values.count <= 128 && values.allSatisfy {
                !$0.key.isEmpty && $0.key.utf8.count <= 128
                    && isValid($0.value, depth: depth + 1)
            }
        }
    }
}

private enum DiagnosticPayloadValueKind {
    case unsignedInteger
    case number
    case string
}

private struct DiagnosticEventDefinition {
    let subsystem: String
    let category: String
    let severity: DiagnosticSeverity
    let sourceComponent: String
    let payloadFields: [String: DiagnosticPayloadValueKind]

    func accepts(_ payload: [String: DiagnosticJSONValue]) -> Bool {
        guard Set(payload.keys) == Set(payloadFields.keys),
              DiagnosticContractValidation.isValidPayload(payload) else { return false }
        return payload.allSatisfy { key, value in
            guard let expected = payloadFields[key] else { return false }
            switch (expected, value) {
            case (.unsignedInteger, .unsignedInteger):
                return true
            case (.unsignedInteger, .integer(let number)):
                return number >= 0
            case (.number, .integer), (.number, .unsignedInteger), (.number, .double):
                return true
            case (.string, .string):
                return true
            default:
                return false
            }
        }
    }
}

enum DiagnosticEventCatalog {
    private static let definitions: [String: DiagnosticEventDefinition] = [
        "audio.capture.recording_started": DiagnosticEventDefinition(
            subsystem: "audio.capture",
            category: "lifecycle",
            severity: .info,
            sourceComponent: "wav_recorder",
            payloadFields: [
                "sample_rate": .unsignedInteger,
                "channels": .unsignedInteger,
                "bits_per_sample": .unsignedInteger,
            ]
        ),
        "audio.capture.recording_closed": DiagnosticEventDefinition(
            subsystem: "audio.capture",
            category: "lifecycle",
            severity: .info,
            sourceComponent: "wav_recorder",
            payloadFields: [
                "sample_count": .unsignedInteger,
                "recorded_duration_ms": .number,
            ]
        ),
        "audio.capture.recording_create_failed": DiagnosticEventDefinition(
            subsystem: "audio.capture",
            category: "failure",
            severity: .error,
            sourceComponent: "wav_recorder",
            payloadFields: [
                "operation": .string,
                "failure_category": .string,
                "reason": .string,
            ]
        ),
        "audio.capture.recording_write_failed": DiagnosticEventDefinition(
            subsystem: "audio.capture",
            category: "failure",
            severity: .error,
            sourceComponent: "wav_recorder",
            payloadFields: [
                "operation": .string,
                "failure_category": .string,
                "reason": .string,
            ]
        ),
        "audio.capture.recording_close_failed": DiagnosticEventDefinition(
            subsystem: "audio.capture",
            category: "failure",
            severity: .error,
            sourceComponent: "wav_recorder",
            payloadFields: [
                "operation": .string,
                "failure_category": .string,
                "reason": .string,
            ]
        ),
        "application.frontmost.transition": DiagnosticEventDefinition(
            subsystem: "application.frontmost",
            category: "transition",
            severity: .info,
            sourceComponent: "frontmost_application_observer",
            payloadFields: [
                "previous_bundle_identifier": .string,
                "previous_process_id": .unsignedInteger,
                "current_bundle_identifier": .string,
                "current_process_id": .unsignedInteger,
            ]
        ),
    ]

    static func accepts(
        eventType: String,
        subsystem: String,
        category: String,
        severity: DiagnosticSeverity,
        sourceComponent: String,
        payload: [String: DiagnosticJSONValue]
    ) -> Bool {
        guard let definition = definitions[eventType],
              definition.subsystem == subsystem,
              definition.category == category,
              definition.severity == severity,
              definition.sourceComponent == sourceComponent else { return false }
        return definition.accepts(payload)
    }
}

struct DiagnosticEvent: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let eventID: UUID
    let eventType: String
    let subsystem: String
    let category: String
    let severity: DiagnosticSeverity
    let timestamp: DiagnosticClockStamp
    let processInstanceID: UUID
    let processID: Int32
    let binaryPath: String
    let appVersion: String
    let buildVersion: String
    let sourceRevision: String?
    let sourceComponent: String
    let sequenceNumber: UInt64
    let sessionID: String?
    let incidentID: String?
    let correlationID: String?
    let interactionID: String?
    let deviceID: String?
    let slotID: String?
    let navigationID: String?
    let sourceTimestamp: DiagnosticRawTimestamp?
    let payload: [String: DiagnosticJSONValue]

    init(
        input: DiagnosticEventInput,
        context: DiagnosticRuntimeContext,
        timestamp: DiagnosticClockStamp,
        sequenceNumber: UInt64
    ) {
        schemaVersion = Self.currentSchemaVersion
        eventID = UUID()
        eventType = input.eventType
        subsystem = input.subsystem
        category = input.category
        severity = input.severity
        self.timestamp = timestamp
        processInstanceID = context.processInstanceID
        processID = context.processID
        binaryPath = context.binaryPath
        appVersion = context.appVersion
        buildVersion = context.buildVersion
        sourceRevision = context.sourceRevision
        sourceComponent = input.sourceComponent
        self.sequenceNumber = sequenceNumber
        sessionID = input.sessionID
        incidentID = input.incidentID
        correlationID = input.correlationID
        interactionID = input.interactionID
        deviceID = input.deviceID
        slotID = input.slotID
        navigationID = input.navigationID
        sourceTimestamp = input.sourceTimestamp
        payload = input.payload.mapValues(Self.canonicalize)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case eventID = "event_id"
        case eventType = "event_type"
        case subsystem
        case category
        case severity
        case timestamp
        case processInstanceID = "process_instance_id"
        case processID = "process_id"
        case binaryPath = "binary_path"
        case appVersion = "app_version"
        case buildVersion = "build_version"
        case sourceRevision = "source_revision"
        case sourceComponent = "source_component"
        case sequenceNumber = "sequence_number"
        case sessionID = "session_id"
        case incidentID = "incident_id"
        case correlationID = "correlation_id"
        case interactionID = "interaction_id"
        case deviceID = "device_id"
        case slotID = "slot_id"
        case navigationID = "navigation_id"
        case sourceTimestamp = "source_timestamp"
        case payload
    }

    private static func canonicalize(_ value: DiagnosticJSONValue) -> DiagnosticJSONValue {
        switch value {
        case .unsignedInteger(let number) where number <= UInt64(Int64.max):
            return .integer(Int64(number))
        case .array(let values):
            return .array(values.map(canonicalize))
        case .object(let values):
            return .object(values.mapValues(canonicalize))
        default:
            return value
        }
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion else {
            throw DiagnosticSchemaError.unsupportedVersion(version)
        }
        schemaVersion = version
        eventID = try values.decode(UUID.self, forKey: .eventID)
        eventType = try values.decode(String.self, forKey: .eventType)
        subsystem = try values.decode(String.self, forKey: .subsystem)
        category = try values.decode(String.self, forKey: .category)
        severity = try values.decode(DiagnosticSeverity.self, forKey: .severity)
        timestamp = try values.decode(DiagnosticClockStamp.self, forKey: .timestamp)
        processInstanceID = try values.decode(UUID.self, forKey: .processInstanceID)
        processID = try values.decode(Int32.self, forKey: .processID)
        binaryPath = try values.decode(String.self, forKey: .binaryPath)
        appVersion = try values.decode(String.self, forKey: .appVersion)
        buildVersion = try values.decode(String.self, forKey: .buildVersion)
        sourceRevision = try values.decodeIfPresent(String.self, forKey: .sourceRevision)
        sourceComponent = try values.decode(String.self, forKey: .sourceComponent)
        sequenceNumber = try values.decode(UInt64.self, forKey: .sequenceNumber)
        sessionID = try values.decodeIfPresent(String.self, forKey: .sessionID)
        incidentID = try values.decodeIfPresent(String.self, forKey: .incidentID)
        correlationID = try values.decodeIfPresent(String.self, forKey: .correlationID)
        interactionID = try values.decodeIfPresent(String.self, forKey: .interactionID)
        deviceID = try values.decodeIfPresent(String.self, forKey: .deviceID)
        slotID = try values.decodeIfPresent(String.self, forKey: .slotID)
        navigationID = try values.decodeIfPresent(String.self, forKey: .navigationID)
        sourceTimestamp = try values.decodeIfPresent(
            DiagnosticRawTimestamp.self,
            forKey: .sourceTimestamp
        )
        payload = try values.decode([String: DiagnosticJSONValue].self, forKey: .payload)

        _ = try DiagnosticEventInput(
            eventType: eventType,
            subsystem: subsystem,
            category: category,
            severity: severity,
            sourceComponent: sourceComponent,
            sessionID: sessionID,
            incidentID: incidentID,
            correlationID: correlationID,
            interactionID: interactionID,
            deviceID: deviceID,
            slotID: slotID,
            navigationID: navigationID,
            sourceTimestamp: sourceTimestamp,
            payload: payload
        )
    }
}
