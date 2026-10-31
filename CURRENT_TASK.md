# RemoteOrbit Current Task

## RO-DIAGNOSTICS-LEGACY-RETIREMENT-045 — audit and design

Status: `AUDIT_AND_DESIGN_ACTIVE`
TASK_CLASS: `SOURCE_AUDIT / RETIREMENT_DESIGN`
Repository: `Lost0rz/RemoteOrbit`
Control base: `main@4b0131902a64a7cc92dcc3c9be001b185a8834ce`
User authorization: explicit forward-development reauthorization after Task 043 merge; human runtime acceptance remains deferred.

## Objective

Produce a repository-grounded retirement and diagnostics-gating plan that reduces normal-mode overhead and removes obsolete Persistent / Dual-Receiver production authority without regressing the current LONG-only voice path.

## Authorized in this phase

- read repository source, tests, workflows, docs, and configuration;
- classify callers and ownership dependencies;
- inspect current CI and test coverage;
- update control/design documentation needed to freeze the implementation boundary;
- produce one bounded execution handoff for local Codex.

## Not authorized yet

- product source mutation;
- deleting/renaming production source or tests;
- changing runtime behavior;
- installing/replacing `/Applications/RemoteOrbit.app`;
- installing/reloading `RemoteOrbitAudio.driver`;
- CoreAudio/TCC/default-device mutation;
- release/tag;
- merge of a Task 045 implementation PR.

## Audit questions

### A. Diagnostics gating

Determine which work still occurs when ordinary logging and audio recording are disabled. At minimum inspect:

- `Log.swift` / ordinary text logging;
- `VoiceDiagnosticLogger.swift` startup and hot-path event work;
- `DiagnosticAuthority.swift` journal writes / queueing / serialization;
- runtime-health and heartbeat scheduling;
- long-term observability persistence / probes;
- WAV/RAW recording gates;
- any safety watchdogs that must remain independent of diagnostics.

Classify every relevant path as `GATE`, `KEEP-ALWAYS`, `KEEP-IN-MEMORY`, or `REMOVE`.

Desired design target: with ordinary diagnostics OFF and recording OFF, persistent diagnostic disk I/O, diagnostic JSON serialization, diagnostic writer enqueue, and diagnostic-only recurring timers should be zero or explicitly justified. Cheap bounded in-memory correctness/accounting state may remain when materially useful.

### B. Persistent / Dual retirement

Inventory production and test authority for obsolete Persistent and Dual-Receiver semantics. At minimum inspect:

- Settings UI and labels;
- AppStorage keys, defaults, and migration;
- `main.swift` Persistent session state/events/callers;
- AppController Dual Receiver state/callers;
- `DualReceiverMappedTriggerState.swift`;
- `DualReceiverVoiceGestureRecognizer.swift`;
- `DualReceiverVoiceMode.swift`;
- tests that still assert Persistent/Dual as supported behavior.

For each item classify `DELETE`, `MIGRATION-ONLY`, `KEEP/RENAME`, or `HISTORICAL-DOC`.

Do not delete mechanisms required by current LONG-only correctness merely because their historical name is Persistent/Dual.

## Required regression boundary for the later implementation

The implementation plan must retain machine coverage for:

- repeated SHORT no-op;
- SHORT x 1/2/3/4 -> LONG;
- normal LONG/release/drain;
- LONG -> release -> LONG / rapid repress;
- late mapped Option DOWN/UP/flags suppression;
- synthetic fallback where mapping is unavailable;
- pre-HID physical candidate and BLE ready reuse;
- transport loss / reconnect paths already covered by current voice tests;
- diagnostics OFF produces no persistent diagnostic work claimed by the new contract;
- diagnostics ON remains functional;
- recording OFF produces no WAV/RAW files;
- full Swift tests, Release build, and Universal2 packaging smoke on `remoteorbit-macmini`.

## Completion gate for this phase

Stop at `READY_FOR_IMPLEMENTATION_HANDOFF` only after the audit provides:

1. exact source/file inventory;
2. caller/dependency classification;
3. explicit keep/delete/gate decisions;
4. bounded implementation waves;
5. test/CI acceptance matrix;
6. no unresolved item whose classification could delete a current correctness mechanism.

Do not implement Task 045 product changes in this audit phase.
