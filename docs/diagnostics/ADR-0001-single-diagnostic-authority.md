# ADR-0001: Single Diagnostic Authority and Event Schema v1

**Status:** Accepted for the additive C1/C2 skeleton and one proof producer

**Baseline:** `origin/main` at `7129ef72949eca956b1d0daddce707d5e417eeed`

**Scope:** Define the owner and contracts for new machine-readable diagnostic events. Historical producer migration remains separate work.

## Context from the source audit

The audited main revision has several useful but separate diagnostic paths:

| Producer or model | Event/data shape | Sink | Current consumer |
| --- | --- | --- | --- |
| App configuration, voice/filter, HID mapping readback, and BLE lifecycle | `category` and `event` strings with `[String: Any]` fields | `voice-diagnostic-current.jsonl` through `VoiceDiagnosticLogger` | `VoiceDiagnosticLoggerTests` parse records; operators inspect the file manually |
| General app, key, and HID messages | Free-form strings through the module's `print` wrapper | Optional `RemoteOrbit.log`, enabled by the Settings toggle and truncated at 5 MiB | Settings opens or clears the log directory; operators inspect text |
| Voice timing and audio delivery | In-process timeline dictionaries, audio counters/snapshots, and formatted text | `RemoteOrbit.log` | BLE teardown formats summaries; tests cover selected models; operators inspect text |
| ATVV keepalive and post-release timing | Typed guard/result enums, but text line builders and event-specific fields | `RemoteOrbit.log`; selected lifecycle events also go through `VoiceDiagnosticLogger` | Runtime guard controls keepalive writes; operators inspect emitted lines |
| Front-edge onset and underrun | Typed onset candidates and buckets, then formatted text | `RemoteOrbit.log`, gated by `REMOTE_ORBIT_P1A5_FRONT_EDGE` | Tests cover the detector/stat models; operators inspect text |
| Optional audio capture | PCM WAV and raw ATVV bytes | User-managed recordings directory | Settings can open or clear recordings |
| Installation state | Derived status values | Settings UI only | Human operator |

There is no repository CLI, Agent API, incident analyzer, or stable event query/export interface on this baseline. The Settings diagnostics page exposes file controls and installation state, not event filtering. The `VoiceDiagnosticLogger` is the nearest structured writer, but it owns only one voice-oriented JSONL format: its envelope has `seq`, `ts`, `uptime`, `category`, and `event`, with arbitrary flat fields. It truncates the current file at each run and does not define a schema version, severity, event ID, process-instance ID, stable source component, or query contract. `Log` is a text sink, not an event owner. **No single diagnostic truth owner currently exists.**

Production control and diagnostic observation are separate. Voice/HID/BLE coordinators, `ATVVKeepAliveGuard`, and `PostReleaseCaptureGraceController` make production decisions. The log records and audio snapshots do not feed a common recovery engine. This ADR does not transfer those decisions to the diagnostic layer.

## Clock and correlation findings

- `VoiceDiagnosticLogger` captures ISO-8601 wall time and `ProcessInfo.systemUptime` seconds without a clock-domain field.
- `P1A4MonotonicClock` converts `mach_continuous_time()` to nanoseconds. Its event lines call the value `monotonic_ns`, but do not retain raw ticks or the timebase ratio. `VoiceTimingLogger` also reports elapsed milliseconds from `systemUptime` in those lines.
- BLE stream elapsed values use `systemUptime`, while `AudioDeliveryTiming` derives summary durations from `Date.timeIntervalSinceReferenceDate`. HID callback/debounce timestamps use `systemUptime`. Audio-pipe submission/render timestamps use the P1-A4 converted nanoseconds.
- The latest main implementation does not read a `CGEvent` timestamp. The open PR #18 adds a separate HID boundary observer and must be handled as an explicit source-clock adapter if it later migrates.
- Structured JSON has a `gesture_id` in selected events and `pid`/binary path at run start. Other lines use `session_id` or `streamID`. There is no shared `incident_id`, `correlation_id`, `process_instance_id`, or source-component rule. `slot_id` and `navigation_id` have no current producer on this baseline.
- Build identity exists in separate places: the app log includes version/build/path; diagnostic packaging stamps `RemoteOrbitDiagnosticSourceHead`; the structured run-start record has PID and binary path but not the app/build/revision fields.

These are confirmed schema gaps, not evidence of a runtime root cause. Duration calculations from `Date` can be distorted by wall-clock changes; this audit does not alter them.

## Decision

`DiagnosticAuthority` is the sole owner of the public event envelope, schema version, canonical clock stamp, serialization, journal append order, and query/snapshot contract for new machine-readable observations. Producers submit typed `DiagnosticEventInput` values and do not choose a file format or path. Existing writers and events remain in place as legacy sources until separately migrated.

Schema v1 defines:

- `schema_version`, `event_id`, `event_type`, `subsystem`, `category`, and `severity`;
- an absolute wall timestamp in Unix milliseconds and a monotonic timestamp in nanoseconds with `clock_domain`, raw ticks, and timebase numerator/denominator;
- process-instance UUID, PID, binary path, app version, build version, optional source revision, and source component;
- optional session, incident, correlation, interaction, device, slot, and navigation IDs;
- an optional source-native timestamp whose unit/domain and any timebase conversion are explicit; and a bounded JSON payload with typed values.

The canonical monotonic domain is `mach_continuous_time`. Its nanosecond conversion retains the raw ticks and conversion ratio. Producers with a native timestamp keep it in `source_timestamp`; no consumer infers its clock or subtracts timestamps from different domains. Wall time is for absolute display/cross-process context, not duration calculations. Sequence numbers order events within a process instance; the JSONL append order is the journal order across process instances.

`emit` captures occurrence time before enqueueing, performs no file I/O or serialization on the producer, and returns without waiting. A bounded 256-event pending queue drops on saturation and exposes a dropped-event count. Journal errors are swallowed at the authority boundary and counted; there is no retry or recovery side effect. Reads may synchronously wait on the writer because they are an explicit query surface, not a producer path.

The append-only UTF-8 JSONL journal is `~/Library/Logs/RemoteOrbit/diagnostic-events-v1.jsonl`. A query filters by event type, subsystem, category, severity, process instance, session, incident, or correlation ID; results preserve journal append order and page with an opaque event-ID cursor. Limits are 1–500. Invalid filters/cursors fail closed. The JSON snapshot is UTF-8 with stable sorted keys. A reader rejects an unknown schema version or a malformed line with an explicit error and returns no partial page.

`slot_id` and `navigation_id` remain optional envelope fields for compatible future sources; this ADR does not create WebView/renderer diagnostics. Schema v1 is a closed event catalog: each event type fixes its subsystem, category, severity, source component, required payload keys, and payload value types. Adding an event or changing its payload requires an explicit catalog/schema update. Raw audio, file paths, and transcript contents are out of scope.

## Proof producer and file boundary

The one proof producer is `WavRecorder`'s existing opt-in capture lifecycle. It emits `audio.capture.recording_started` and `audio.capture.recording_closed` metadata with a recording correlation ID. It does not emit the WAV/raw path or bytes and does not change recording format, timing, enablement, or close behavior.

The implementation stays in new `Sources/RemoteOrbit/Diagnostics` types, `WavRecorder.swift`, focused tests, and this ADR. It does not change `main.swift`, `HIDMonitor.swift`, `BLEBridge.swift`, `VoiceOptionTrigger.swift`, any voice/HID state machine, or recovery logic.

## Alternatives considered

1. **Expand `VoiceDiagnosticLogger` into the global owner.** Rejected for now: it has a voice-specific name, unversioned dynamic fields, current-run truncation, and no read API. Converting it in place would also widen the C diff into an existing producer surface.
2. **Parse the global `print`/text log.** Rejected: free-form text has no stable payload or compatibility contract and cannot fail closed on event types.
3. **Migrate every historical producer before defining the contract.** Rejected: it creates unnecessary state-machine/file conflicts and is outside C's scope.
4. **Add an independent journal/query owner and migrate one opt-in producer.** Accepted: new code is additive, establishes a typed authority boundary, and demonstrates serialization, reading, and failure isolation without changing production control.

## Compatibility and migration order

Do not remove or rewrite `RemoteOrbit.log`, `voice-diagnostic-current.jsonl`, audio snapshots, P1-A4/P1-A5 models, or the WAV/raw recording format in this stage. Future migration order is: (1) narrow lifecycle/configuration events that are already low frequency; (2) audio summary snapshots with an explicit source clock; (3) HID boundary events after PR #18 stabilizes; (4) any additional observer/probe. Each producer gets a separate change and behavior-diff audit. No full migration is attempted here.

## Gate result and parallel work

Gate 0 verified live `origin/main` and cached `origin/main` both at `7129ef72949eca956b1d0daddce707d5e417eeed`. Main has no tracked `AGENTS.md`, `CURRENT_STATUS.md`, or `CURRENT_TASK.md`; PR #17 is a draft that adds those controls and a separate diagnostics document, so those draft files are not treated as main authority.

PR #18 is a draft on the same main base and changes `HIDMonitor.swift`, `main.swift`, and HID/boundary tests. A local Flight Recorder worktree also changes `BLEBridge.swift`, `VoiceOptionTrigger.swift`, `VoiceDiagnosticLogger.swift`, and `main.swift`. C avoids those files. The selected `WavRecorder.swift` proof is outside the A/B changed-file sets. No A/B branch is asked to wait or migrate.

**Construction threshold:** PASS for this additive schema, protocol/journal/query skeleton, ADR, and one WAV lifecycle proof producer only. Historical migration, complete CLI, UI, recovery changes, and producer files already owned by A/B remain excluded.
