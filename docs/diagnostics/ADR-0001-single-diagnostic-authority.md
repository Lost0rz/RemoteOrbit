# ADR-0001: Single Diagnostic Authority

**Status:** Accepted / current

## Decision

`DiagnosticAuthority` is the sole owner of RemoteOrbit's machine-readable diagnostic event envelope, schema version, canonical clock provenance, journal append order, query/snapshot contract and bounded asynchronous write boundary.

Current implementation is under `remote-orbit/Sources/RemoteOrbit/Diagnostics/`, with the principal routes:

- `DiagnosticAuthority.swift`
- `DiagnosticEvent.swift`
- `JSONLinesDiagnosticJournal.swift`
- `DiagnosticExport.swift`

Producers submit typed diagnostic input. They do not create competing public schemas or choose independent machine-readable storage contracts.

## Event contract

Schema v1 owns:

- stable event identity/type, subsystem/category/severity and source component;
- wall-clock and monotonic timing with explicit clock provenance;
- process/runtime identity and optional source revision;
- optional session, incident, correlation, interaction and device identifiers;
- bounded typed payload values.

The canonical monotonic domain is based on `mach_continuous_time`; duration/correlation logic must not subtract timestamps from incompatible clock domains.

Producer-side emission is asynchronous and best-effort. Diagnostic queue saturation or journal failure may lose diagnostic evidence, but the diagnostic layer must not block a realtime producer or become a production recovery owner.

## Storage and query boundary

The authority owns the versioned JSONL journal and the reader/query path. Readers fail closed on unsupported schema versions or malformed records rather than silently mixing incompatible evidence.

The diagnostic authority is an **observation** system. Voice/HID/BLE/audio production state machines remain the owners of production decisions. A diagnostic anomaly can preserve evidence; it does not establish root cause or authorize repair.

## Privacy / payload boundary

Raw transcripts and unrestricted user content are not part of the public event schema. Raw audio remains an independently controlled opt-in recording surface. Diagnostic exports must remain bounded and explicit.

## Compatibility

Legacy human-readable logs may still exist as compatibility/evidence surfaces, but they are not competing diagnostic schema authorities. New machine-readable diagnostic work must route through `DiagnosticAuthority` unless a later governed architecture change explicitly supersedes this ADR.

## Verification routes

- `DiagnosticAuthorityTests.swift`
- `DiagnosticExportTests.swift`
- `DiagnosticHardeningTests.swift`
- `AudioDataPlaneDiagnosticsTests.swift`

Historical construction/audit details for this ADR remain available in Git history; branch/PR/task references from that period are intentionally not part of this durable decision.