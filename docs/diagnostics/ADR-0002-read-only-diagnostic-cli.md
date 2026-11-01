# ADR-0002: Read-only Diagnostic CLI Adapter

**Status:** Accepted / implemented

## Decision

RemoteOrbit exposes diagnostic CLI commands as a read-only adapter over `DiagnosticAuthority`. The CLI is not a second diagnostic backend and does not own a separate parser/schema/storage model.

The implementation route is `remote-orbit/Sources/RemoteOrbit/Diagnostics/DiagnosticCLI.swift` and its focused tests are `DiagnosticCLITests.swift`.

## Supported boundary

Representative commands:

```text
RemoteOrbit diagnostics status
RemoteOrbit diagnostics query [filters]
RemoteOrbit diagnostics snapshot [filters]
RemoteOrbit diagnostics verify
RemoteOrbit diagnostics export [options]
RemoteOrbit diagnostics help
```

Query/snapshot/verify/export must reuse the authority-owned storage/query contracts. CLI execution exits before normal menu-bar application startup and must not initialize normal HID/BLE/audio runtime merely to read diagnostics.

## Read-only rule

The diagnostic CLI must not gain commands that silently perform product/runtime mutation, including:

- restart/repair/reset;
- installation or driver replacement;
- CoreAudio restart;
- TCC/permission mutation;
- default audio-device changes;
- product setting changes;
- log/journal deletion or truncation as part of a read operation.

A future control command requires a separately governed architecture/task decision. It must not be added as an incidental extension of the read-only diagnostic surface.

## Compatibility

Legacy `RemoteOrbit.log` or other historical evidence files may be included only through explicitly bounded/exported compatibility paths. They do not become schema peers of `DiagnosticAuthority`.

## Verification routes

- `DiagnosticCLITests.swift`
- `DiagnosticExportTests.swift`

Historical proposal/audit wording is preserved in Git history; the current source and tests establish that this ADR is implemented rather than merely proposed.