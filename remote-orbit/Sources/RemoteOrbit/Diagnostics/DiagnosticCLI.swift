import Foundation

enum DiagnosticCLIError: Error, Equatable {
    case usage(String)
}

enum DiagnosticCLI {
    typealias Writer = (String) -> Void

    static func runIfRequested(
        arguments: [String] = CommandLine.arguments,
        authority: (any DiagnosticAuthority)? = nil,
        journalURL: URL? = nil,
        output: Writer = { Swift.print($0) },
        errorOutput: Writer = { message in
            guard let data = (message + "\n").data(using: .utf8) else { return }
            FileHandle.standardError.write(data)
        }
    ) -> Int32? {
        guard arguments.count >= 2, arguments[1] == "diagnostics" else {
            return nil
        }
        return run(
            arguments: Array(arguments.dropFirst(2)),
            authority: authority ?? DiagnosticAuthorityService.shared,
            journalURL: journalURL ?? DiagnosticStorage.defaultJournalURL,
            output: output,
            errorOutput: errorOutput,
            exportHandler: nil
        )
    }

    static func run(
        arguments: [String],
        authority: any DiagnosticAuthority,
        journalURL: URL,
        output: Writer,
        errorOutput: Writer,
        exportHandler: ((DiagnosticExportOptions) throws -> URL)? = nil
    ) -> Int32 {
        let command = arguments.first ?? "help"
        let commandArguments = Array(arguments.dropFirst())

        do {
            switch command {
            case "help", "--help", "-h":
                guard commandArguments.isEmpty else {
                    throw DiagnosticCLIError.usage("help takes no arguments")
                }
                output(usage)
                return 0

            case "status":
                guard commandArguments.isEmpty else {
                    throw DiagnosticCLIError.usage("status takes no arguments")
                }
                output(try statusJSON(journalURL: journalURL))
                return 0

            case "export":
                let options = try parseExportOptions(commandArguments)
                let archive = if let exportHandler {
                    try exportHandler(options)
                } else {
                    try DiagnosticExporter(
                        authority: authority,
                        journalURL: journalURL
                    ).export(options: options)
                }
                output(archive.path)
                return 0

            case "query", "snapshot":
                if commandArguments == ["--help"] || commandArguments == ["-h"] {
                    output(usage)
                    return 0
                }
                let filter = try parseFilter(commandArguments)
                let data = try authority.snapshot(filter)
                guard let json = String(data: data, encoding: .utf8) else {
                    errorOutput("diagnostics: snapshot is not valid UTF-8")
                    return 65
                }
                output(json)
                return 0

            case "verify":
                guard commandArguments.isEmpty else {
                    throw DiagnosticCLIError.usage("verify takes no arguments")
                }
                let page = try authority.query(DiagnosticQueryFilter(limit: 1))
                output(try encodeJSONObject([
                    "ok": true,
                    "schema_version": page.schemaVersion,
                ]))
                return 0

            default:
                throw DiagnosticCLIError.usage("unknown diagnostics command: \(command)")
            }
        } catch DiagnosticCLIError.usage(let message) {
            errorOutput("diagnostics: \(message)")
            errorOutput("Run 'RemoteOrbit diagnostics help' for usage.")
            return 64
        } catch let error as DiagnosticQueryError {
            errorOutput("diagnostics: \(describe(error))")
            switch error {
            case .storageUnavailable:
                return 74
            case .invalidFilter, .invalidCursor, .unsupportedSchemaVersion, .corruptJournal:
                return 65
            }
        } catch let error as DiagnosticExportError {
            errorOutput("diagnostics: export failed: \(error)")
            return 74
        } catch {
            errorOutput("diagnostics: \(error)")
            return 1
        }
    }

    private static func parseFilter(_ arguments: [String]) throws -> DiagnosticQueryFilter {
        var eventTypes: Set<String> = []
        var subsystems: Set<String> = []
        var categories: Set<String> = []
        var severities: Set<DiagnosticSeverity> = []
        var processInstanceID: UUID?
        var sessionID: String?
        var incidentID: String?
        var correlationID: String?
        var cursor: String?
        var startWallTimestampUnixMilliseconds: Int64?
        var endWallTimestampUnixMilliseconds: Int64?
        var limit = 100

        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard index + 1 < arguments.count else {
                throw DiagnosticCLIError.usage("missing value for \(option)")
            }
            let value = arguments[index + 1]
            switch option {
            case "--event-type":
                eventTypes.insert(value)
            case "--subsystem":
                subsystems.insert(value)
            case "--category":
                categories.insert(value)
            case "--severity":
                guard let severity = DiagnosticSeverity(rawValue: value) else {
                    throw DiagnosticCLIError.usage("invalid severity: \(value)")
                }
                severities.insert(severity)
            case "--process-instance":
                guard let identifier = UUID(uuidString: value) else {
                    throw DiagnosticCLIError.usage("invalid process instance UUID")
                }
                processInstanceID = identifier
            case "--session":
                sessionID = value
            case "--incident":
                incidentID = value
            case "--correlation":
                correlationID = value
            case "--cursor":
                cursor = value
            case "--since-unix-ms":
                guard let parsed = Int64(value) else {
                    throw DiagnosticCLIError.usage("since timestamp must be an integer")
                }
                startWallTimestampUnixMilliseconds = parsed
            case "--until-unix-ms":
                guard let parsed = Int64(value) else {
                    throw DiagnosticCLIError.usage("until timestamp must be an integer")
                }
                endWallTimestampUnixMilliseconds = parsed
            case "--limit":
                guard let parsed = Int(value) else {
                    throw DiagnosticCLIError.usage("limit must be an integer")
                }
                limit = parsed
            default:
                throw DiagnosticCLIError.usage("unknown option: \(option)")
            }
            index += 2
        }

        return try DiagnosticQueryFilter(
            eventTypes: eventTypes,
            subsystems: subsystems,
            categories: categories,
            severities: severities,
            processInstanceID: processInstanceID,
            sessionID: sessionID,
            incidentID: incidentID,
            correlationID: correlationID,
            cursor: cursor,
            startWallTimestampUnixMilliseconds: startWallTimestampUnixMilliseconds,
            endWallTimestampUnixMilliseconds: endWallTimestampUnixMilliseconds,
            limit: limit
        )
    }

    private static func parseExportOptions(_ arguments: [String]) throws -> DiagnosticExportOptions {
        var outputDirectory: URL?
        var hostRole = "controller"
        var startWallTimestampUnixMilliseconds: Int64?
        var endWallTimestampUnixMilliseconds: Int64?

        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard index + 1 < arguments.count else {
                throw DiagnosticCLIError.usage("missing value for (option)")
            }
            let value = arguments[index + 1]
            switch option {
            case "--output":
                guard !value.isEmpty else { throw DiagnosticCLIError.usage("output must not be empty") }
                outputDirectory = URL(fileURLWithPath: value, isDirectory: true)
            case "--host-role":
                hostRole = value
            case "--since-unix-ms":
                guard let parsed = Int64(value) else {
                    throw DiagnosticCLIError.usage("since timestamp must be an integer")
                }
                startWallTimestampUnixMilliseconds = parsed
            case "--until-unix-ms":
                guard let parsed = Int64(value) else {
                    throw DiagnosticCLIError.usage("until timestamp must be an integer")
                }
                endWallTimestampUnixMilliseconds = parsed
            default:
                throw DiagnosticCLIError.usage("unknown export option: (option)")
            }
            index += 2
        }

        guard let outputDirectory else {
            throw DiagnosticCLIError.usage("export requires --output <directory>")
        }
        return DiagnosticExportOptions(
            outputDirectory: outputDirectory,
            hostRole: hostRole,
            startWallTimestampUnixMilliseconds: startWallTimestampUnixMilliseconds,
            endWallTimestampUnixMilliseconds: endWallTimestampUnixMilliseconds
        )
    }

    private static func statusJSON(journalURL: URL) throws -> String {
        let fileManager = FileManager.default
        let exists = fileManager.fileExists(atPath: journalURL.path)
        var size: UInt64 = 0
        if exists {
            let attributes = try fileManager.attributesOfItem(atPath: journalURL.path)
            size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        }

        return try encodeJSONObject([
            "backend": "diagnostic_authority_v1",
            "journal_exists": exists,
            "journal_path": journalURL.path,
            "journal_size_bytes": size,
            "mode": "read_only",
            "schema_version": DiagnosticEvent.currentSchemaVersion,
        ])
    }

    private static func encodeJSONObject(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else {
            throw DiagnosticQueryError.storageUnavailable
        }
        return string
    }

    private static func describe(_ error: DiagnosticQueryError) -> String {
        switch error {
        case .invalidFilter(let message):
            return "invalid filter: \(message)"
        case .invalidCursor:
            return "cursor does not exist in the journal"
        case .unsupportedSchemaVersion(let version):
            return "unsupported diagnostic schema version: \(version)"
        case .corruptJournal(let line):
            return "corrupt diagnostic journal at record \(line)"
        case .storageUnavailable:
            return "diagnostic storage unavailable"
        }
    }

    private static let usage = """
    RemoteOrbit diagnostics — read-only DiagnosticAuthority v1 consumer

    Usage:
      RemoteOrbit diagnostics status
      RemoteOrbit diagnostics export --output <directory> [options]
      RemoteOrbit diagnostics query [filters]
      RemoteOrbit diagnostics snapshot [filters]
      RemoteOrbit diagnostics verify
      RemoteOrbit diagnostics help

    Filters:
      --event-type <token>        repeatable
      --subsystem <token>         repeatable
      --category <token>          repeatable
      --severity <level>          debug|info|warning|error|critical; repeatable
      --process-instance <uuid>
      --session <id>
      --incident <id>
      --correlation <id>
      --cursor <event-id>
      --since-unix-ms <timestamp>
      --until-unix-ms <timestamp>
      --limit <1...500>

    Export options:
      --output <directory>        required; creates a bounded tar.gz evidence bundle
      --host-role <token>         controller (default) or receiver
      --since-unix-ms <timestamp>
      --until-unix-ms <timestamp>

    The CLI is read-only. It exposes the existing DiagnosticAuthority query/snapshot
    contract and has no restart, reset, repair, install, delete, clear, or settings
    mutation commands.
    """
}
