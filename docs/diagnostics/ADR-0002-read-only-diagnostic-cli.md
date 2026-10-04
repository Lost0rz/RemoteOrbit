# ADR-0002: Read-only Diagnostic CLI adapter

**Status:** Proposed implementation for independent audit

## Decision

RemoteOrbit has one machine-readable diagnostic backend: `DiagnosticAuthority`.
The v1 schema, canonical clock provenance, journal append order, journal reader,
filters, pagination, and snapshot encoding remain owned by that Authority.

The CLI is a consumer adapter, not a second diagnostic implementation. It is exposed
through the existing RemoteOrbit executable as a `diagnostics` subcommand and exits
before duplicate-instance handling, AppKit startup, HID/BLE/audio initialization, or
normal application runtime.

The canonical v1 journal location is defined once by `DiagnosticStorage` and is used
by both the Authority service and CLI storage metadata.

## Commands

```text
RemoteOrbit diagnostics status
RemoteOrbit diagnostics query [filters]
RemoteOrbit diagnostics snapshot [filters]
RemoteOrbit diagnostics verify
RemoteOrbit diagnostics help
```

`query` and `snapshot` both call the existing Authority `snapshot` API. The CLI
does not parse JSONL records itself. `verify` calls the existing query path, which
parses the complete journal and therefore fails closed on unsupported schema versions,
malformed records, invalid filters/cursors, or storage errors.

The CLI supports only filters already defined by `DiagnosticQueryFilter`: event type,
subsystem, category, severity, process instance, session, incident, correlation,
cursor, and limit.

## Read-only boundary

There are intentionally no CLI commands for restart, reset, repair, installation,
process termination, settings changes, permission changes, driver/CoreAudio changes,
or log deletion/truncation/rotation. Adding a control command would require a separate
architecture/task decision and must not be smuggled into this diagnostic surface.

Legacy `RemoteOrbit.log` and `voice-diagnostic-current.jsonl` remain historical
compatibility/evidence sources. They are not merged into the Authority v1 stream by
the CLI and are not competing schema authorities.

## Invocation

From a SwiftPM checkout:

```bash
swift run RemoteOrbit diagnostics status
swift run RemoteOrbit diagnostics verify
swift run RemoteOrbit diagnostics query --incident <incident-id> --limit 100
```

From an installed app bundle, invoke its executable directly:

```bash
/Applications/RemoteOrbit.app/Contents/MacOS/RemoteOrbit diagnostics status
```

CLI execution is deliberately separate from launching the menu-bar application.
