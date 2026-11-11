# ADR-0003: Long-term Voice Observability

**Status:** Accepted / current

Date: 2026-10-29  
Current policy reconciled: 2026-11-01

## Decision

RemoteOrbit uses `DiagnosticAuthority` for durable machine-readable evidence. Long-term voice observability is intentionally bounded and gated so that diagnostic work does not become a hidden always-on performance cost or a production state-machine owner.

When the effective diagnostics gate is enabled, the system can preserve two evidence levels:

- **L1** — one compact `voice.session.summary` for a session, carrying stable correlation fields such as `session_id` and `capture_id`, lifecycle/timing/counter summaries and diagnostic drop/write state.
- **L2** — bounded high-resolution incident evidence retained/emitted only when the centralized anomaly policy classifies a session as worth preserving.

Here L1/L2 refer only to RemoteOrbit's diagnostic evidence levels, not engineering execution-deviation categories.

L2 rings/chunks are fixed-capacity and producer work must remain bounded. Diagnostic queue/journal failure is evidence loss, not permission to block BLE/CoreAudio/gesture production paths.

## Runtime gate — Task 045A

Task 045A changed the effective runtime policy to:

```text
AppStorage.loggingEnabled || REMOTE_ORBIT_DIAGNOSTICS == "1"
```

The result is sampled into process-local `DiagnosticsRuntimeGate` state. When disabled, structured diagnostic producers, timers/probes, bounded trace lifecycle and persistent diagnostic-journal work are stopped or skipped where the current implementation permits. Recording remains independently controlled.

The **L1 always-on policy is superseded**. The environment override is an explicit operator diagnostic control; it is not a product acceptance mechanism.

Diagnostics-off must not disable correctness mechanisms such as ownership, release/drain, suppression, watchdog or transport behavior.

## Retention

The durable journal policy uses bounded rotation: **2 MiB** per JSONL segment and **5 segments** retained. Query/export must remain bounded and must expose truncation/availability honestly rather than silently returning a partial result as complete evidence.

## Export

The supported manual read-only workflow is:

```text
RemoteOrbit diagnostics export --output <directory> --host-role TEST_HOST \
  --since-unix-ms <start> --until-unix-ms <end>
```

An export may include the bounded authority event set, retained journal segments, allowlisted diagnostic logs, runtime provenance and receiver-side timing evidence when available. If receiver evidence cannot be obtained, the archive records that explicitly as `evidence-unavailable.json` rather than fabricating a receiver observation.

Export does not install, repair, reset, change settings, upload data automatically, alter TCC/default devices, or change the running voice state machine.

## Evidence boundary

The observability system can establish local recorded facts such as:

- gesture/transport/audio lifecycle ordering;
- bounded notification/decode/supply/playout counters;
- active-versus-tail accounting;
- bounded queue/starvation/main-queue-lag observations;
- runtime/source provenance;
- diagnostic drops/write failures;
- whether optional receiver evidence was available for the requested window.

It does **not** establish receiver transcript text, unobserved InputMethodKit state, BLE radio/firmware causality, or a product root cause. An anomaly classifier only decides which evidence deserves retention; anomaly evidence **does not establish root cause**.

## Retired semantics boundary

Long-term observability follows the current LONG-only remote-voice product contract. Historical Persistent-session, dual-receiver, Receiver B, local-microphone voice-button and generic SHORT business semantics are not revived by old diagnostic field names or old incident/release evidence.

## Implementation routes

- `Diagnostics/LongTermObservability.swift`
- `Diagnostics/DiagnosticAuthority.swift`
- `Diagnostics/DiagnosticExport.swift`
- `DiagnosticsRuntimeGate.swift`
- `AudioDataPlaneDiagnostics.swift`
- related bounded producer hooks in the current BLE/audio/voice runtime.

## Verification routes

- `LongTermObservabilityTests.swift`
- `LongTermObservabilityDocumentationTests.swift`
- `DiagnosticsRuntimeGateTests.swift`
- `DiagnosticExportTests.swift`
- `AudioDataPlaneDiagnosticsTests.swift`

Historical task-specific corrective/design documents are retained in Git history rather than duplicated as active planning authority.