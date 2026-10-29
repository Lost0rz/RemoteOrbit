# RemoteOrbit Long-Term Observability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add bounded always-on voice-session summaries, anomaly-frozen temporal traces, bounded diagnostic retention, and explicit export without changing RemoteOrbit product behavior.

**Architecture:** Extend the existing `DiagnosticAuthority` event catalog with compact `voice.session.summary` and anomaly-only `voice.session.trace` events. Keep a reusable front-edge/recent trace in `AudioPipe` under its existing state lock, detach it before off-path snapshotting, and use a lock-protected lifecycle/accounting builder for BLE/decode/control facts. Replace the single-file journal's cache with bounded segment rotation and streaming page scans; expose export as a read-only CLI collection command.

**Tech Stack:** Swift 5.9, XCTest, Foundation `FileHandle`/`Process`, existing `DiagnosticAuthority`, macOS `log show`, tar/gzip.

**Spec:** `docs/superpowers/specs/2026-10-29-long-term-observability-design.md`

## Global Constraints

- Preserve `DiagnosticAuthority`'s non-blocking, best-effort producer contract.
- Keep normal sessions to one compact machine-readable summary; emit trace chunks only for anomaly-marked sessions.
- Use a fixed-capacity/reused front-edge plus rolling recent trace; report dropped/overwritten observations.
- No disk I/O, string formatting, allocation, or new shared diagnostic lock in CoreAudio render or CoreBluetooth audio callbacks.
- Do not change ATVV, BLE, codec, sample-rate, AudioPipe policy, HID, gesture, Option/Control, driver, receiver, install, PR, tag, release, or Air runtime behavior.
- Retain at most five journal segments of at most 2 MiB by default; query one bounded segment at a time.
- Do not collect raw dictated text or perform continuous Accessibility polling; record receiver evidence as unavailable when it cannot be exported.

## Review Focus

- A long session must not grow trace arrays or journal query memory without bound — test fixed capacity, rotation, and page scanning.
- A tail drain must not be reported as strict active speech underrun — test separate active/tail counters and anomaly classification.
- A render callback must not call the authority or format strings — inspect the callback and add a source-level boundary test/check.
- A crash or partial journal append must fail closed without fabricating a record — test newline framing/corrupt-segment behavior.
- An export must never include settings backups or raw text and must state missing receiver evidence — test archive listing and manifest errors.

### Task 1: Versioned authority payloads and bounded journal

**Files:**
- Modify: `remote-orbit/Sources/RemoteOrbit/Diagnostics/DiagnosticAuthority.swift`
- Modify: `remote-orbit/Sources/RemoteOrbit/Diagnostics/DiagnosticEvent.swift`
- Modify: `remote-orbit/Sources/RemoteOrbit/Diagnostics/JSONLinesDiagnosticJournal.swift`
- Modify: `remote-orbit/Sources/RemoteOrbit/Diagnostics/DiagnosticCLI.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/DiagnosticAuthorityTests.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/DiagnosticCLITests.swift`

**Interfaces:**
- `DiagnosticQueryFilter` gains optional wall-clock window bounds and `matches(_:)` applies them.
- `JSONLinesDiagnosticJournal.RetentionPolicy(maxSegmentBytes:maxSegmentCount:)` centralizes the default 2 MiB / 5-segment policy.
- The journal exposes bounded segment URLs for the exporter without exposing its writer internals.
- The catalog accepts object/array payload values for the new summary/trace event definitions while keeping the envelope schema at v1.

- [ ] **Step 1: Write failing tests** for time-window filters, summary/trace catalog payload acceptance, segment rotation, retention, cursor pagination across segments, journal-failure/drop metrics, and a partial trailing line.
- [ ] **Step 2: Run the focused tests and verify they fail for the missing contract** with `swift test --filter DiagnosticAuthorityTests` and `swift test --filter DiagnosticCLITests`.
- [ ] **Step 3: Implement the catalog/filter and rotating journal** while preserving append-at-newline, asynchronous authority emission, schema rejection, and existing status/query command behavior.
- [ ] **Step 4: Re-run focused tests and verify green**, including old v1 event tests.
- [ ] **Step 5: Commit** `diagnostics: bound journal retention and query windows`.

### Task 2: Fixed-capacity trace, session accounting, anomaly policy, and lag aggregation

**Files:**
- Create: `remote-orbit/Sources/RemoteOrbit/Diagnostics/LongTermObservability.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/LongTermObservabilityTests.swift`

**Interfaces:**
- `LongTermObservationKind` identifies `bleArrival`, `decodeComplete`, `pcmSubmitted`, `render`, `queueStarvation`, and `lifecycle` without render-side strings.
- `LongTermObservationPoint` is a fixed numeric record: monotonic timestamp, kind, requested/fill/unfilled frames, queue depth, byte/sample count, and active/tail semantic marker.
- `FixedCapacityObservationTrace(frontCapacity:recentCapacity:)` supports `reset()`, allocation-free `append(_:)`, `snapshot()`, and `droppedObservationCount`.
- `LongTermObservabilityThresholds` owns all anomaly thresholds and `classify(summary:trace:)` returns flags only, never a causal verdict.
- `MainQueueLagAccumulator` owns count/max/p95/histogram aggregation; `MainQueueResponsivenessProbe` samples the main queue at a bounded interval and returns the accumulator summary.
- `LongTermVoiceSessionSummary` owns the stable observation schema and conversion to `DiagnosticJSONValue`.

- [ ] **Step 1: Write failing tests** for front-edge retention, rolling recent wrap, drop/overwrite counts, monotonic ordering, summary expected/delivered/deficit accounting, active-vs-tail counters, every anomaly threshold, and p95/histogram lag aggregation.
- [ ] **Step 2: Run the focused test file and verify expected failures** with `swift test --filter LongTermObservabilityTests`.
- [ ] **Step 3: Implement the fixed buffers and pure accounting types** with no Foundation I/O and no unbounded collections in the trace path.
- [ ] **Step 4: Re-run the focused tests and verify green**; confirm the trace's `append` path contains no authority call, string interpolation, or journal access.
- [ ] **Step 5: Commit** `diagnostics: add bounded long-term observation accounting`.

### Task 3: Always-on lifecycle and BLE/decode summary integration

**Files:**
- Modify: `remote-orbit/Sources/RemoteOrbit/VoiceOptionTrigger.swift`
- Modify: `remote-orbit/Sources/RemoteOrbit/BLEBridge.swift`
- Modify: `remote-orbit/Sources/RemoteOrbit/main.swift`
- Modify: `remote-orbit/Sources/RemoteOrbit/Diagnostics/DiagnosticAuthority.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/LongTermObservabilityTests.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/AudioDataPlaneDiagnosticsTests.swift`

**Interfaces:**
- `VoiceTimingLogger` forwards `begin`, `mark`, and `markForSession` to `LongTermObservabilityService` while retaining existing P1-A4/P1-A5 behavior.
- `VoiceTimingLogger` gains observation-only methods for control policy, transport start, notification, decode, and final AudioPipe accounting.
- `LongTermObservabilityService` owns one active builder, emits one compact summary at `VoiceTimingLogger.end`, and preserves session/capture identity when AUDIO_START precedes HID.
- Summary fields include physical down, hold/classification, trigger/policy, MIC_OPEN/AUDIO_START/AUDIO_FIRST, release, MIC_CLOSE/AUDIO_STOP, drain/output completion, ATVV protocol/mode/codec/rate, notification and gap metrics, decode/supply metrics, playout metrics, runtime identity, schema version, and diagnostic drop/write counters.

- [ ] **Step 1: Write failing tests** that begin/end a synthetic voice session and assert all lifecycle/transport/decode/supply/playout/runtime fields and capture/session correlation, including missing receiver-side facts represented as unavailable.
- [ ] **Step 2: Run the focused tests and verify the summary is absent/incomplete** with `swift test --filter LongTermObservabilityTests`.
- [ ] **Step 3: Implement the forwarding and summary emission** at existing observation boundaries only; do not gate, delay, or alter the product state machine.
- [ ] **Step 4: Re-run focused tests and existing voice/audio contract tests** and verify the new summary is emitted for default environment as well as opt-in continuity mode.
- [ ] **Step 5: Commit** `diagnostics: persist always-on voice session summaries`.

### Task 4: AudioPipe fixed trace and host-scheduling probe integration

**Files:**
- Modify: `remote-orbit/Sources/RemoteOrbit/AudioPipe.swift`
- Modify: `remote-orbit/Sources/RemoteOrbit/BLEBridge.swift`
- Modify: `remote-orbit/Sources/RemoteOrbit/VoiceOptionTrigger.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/AudioDataPlaneDiagnosticsTests.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/LongTermObservabilityTests.swift`

**Interfaces:**
- `AudioPipe` owns two preallocated `FixedCapacityObservationTrace` instances, swaps/detaches them under its existing `stateLock`, and snapshots the detached trace after unlocking.
- `schedule` records PCM submission and queue depth in the active trace; `render` records request/fill/starvation, active/tail state, and queue transitions without new locks, disk, strings, or authority calls.
- `AudioPipeDiagnosticsSnapshot` carries the already-owned active/tail/queue/overflow counters needed by the summary.
- The lifecycle starts/stops `MainQueueResponsivenessProbe`; no sample is logged individually.

- [ ] **Step 1: Write failing tests** for trace observation from schedule/render, swap/detach behavior, active strict underrun versus tail empty, queue starvation/drop accounting, and main-queue probe start/stop summaries.
- [ ] **Step 2: Run the focused tests and verify failures** with `swift test --filter AudioDataPlaneDiagnosticsTests` and `swift test --filter LongTermObservabilityTests`.
- [ ] **Step 3: Implement the AudioPipe observer path** using only the existing `stateLock` and preallocated buffers; keep 038-B opt-in ledger behavior intact.
- [ ] **Step 4: Re-run focused tests plus the source-level observer-effect checks** and verify no render-side journal/authority/formatting/new-lock path exists.
- [ ] **Step 5: Commit** `diagnostics: capture bounded audio timing trace`.

### Task 5: Anomaly-only trace persistence

**Files:**
- Modify: `remote-orbit/Sources/RemoteOrbit/Diagnostics/DiagnosticEvent.swift`
- Modify: `remote-orbit/Sources/RemoteOrbit/Diagnostics/LongTermObservability.swift`
- Modify: `remote-orbit/Sources/RemoteOrbit/VoiceOptionTrigger.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/LongTermObservabilityTests.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/DiagnosticAuthorityTests.swift`

**Interfaces:**
- `LongTermObservabilityService` emits `voice.session.summary` for every session and chunked `voice.session.trace` only when anomaly flags are non-empty.
- Trace chunks are bounded arrays of numeric observation objects with capture/session identity, chunk index/count, schema version, and dropped-observation count.
- Summary includes `anomaly_flags`, `trace_persisted`, and `receiver_evidence_status` without claiming root cause.

- [ ] **Step 1: Write failing tests** proving normal sessions emit summary-only, anomalous sessions emit summary plus trace chunks, trace chunk limits are bounded, and drops/authority saturation remain visible.
- [ ] **Step 2: Run the focused tests and verify the expected persistence failures**.
- [ ] **Step 3: Implement off-path anomaly classification and chunk emission** through `DiagnosticAuthority.emit`; no hot callback persists anything.
- [ ] **Step 4: Re-run focused tests and verify green**.
- [ ] **Step 5: Commit** `diagnostics: freeze anomaly traces off the hot path`.

### Task 6: Explicit manual diagnostic export

**Files:**
- Create: `remote-orbit/Sources/RemoteOrbit/Diagnostics/DiagnosticExport.swift`
- Modify: `remote-orbit/Sources/RemoteOrbit/Diagnostics/DiagnosticCLI.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/DiagnosticExportTests.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/DiagnosticCLITests.swift`

**Interfaces:**
- `DiagnosticExportOptions` carries output directory, host role, and optional Unix-millisecond window.
- `ReceiverEvidenceProvider` returns bounded unified-log bytes or a typed unavailable error; the production provider invokes `/usr/bin/log show` with a receiver-timing predicate and no text-harvesting predicate.
- `DiagnosticExporter.export(options:)` returns `RemoteOrbit-diagnostics-<timestamp>.tar.gz` and writes `manifest.json`, `runtime/runtime-context.json`, `sessions/diagnostic-events.json`, `journal/*`, `logs/*` when present, `receiver/unified-log-window.jsonl` or `receiver/evidence-unavailable.json`, and `SHA256SUMS`.
- `DiagnosticCLI` adds `diagnostics export --output <dir> [--host-role <role>] [--since-unix-ms <ms>] [--until-unix-ms <ms>]`; it remains explicit/read-only with respect to product state.

- [ ] **Step 1: Write failing tests** for manifest identity/window/schema, archive inclusion/exclusion, SHA256SUMS, selected rotated segments, unavailable receiver evidence, and CLI argument validation.
- [ ] **Step 2: Run the focused export/CLI tests and verify failures**.
- [ ] **Step 3: Implement staging, bounded collection, receiver export, manifest, hashes, and tarball creation** with dependency injection for file manager, clock, authority, and receiver provider.
- [ ] **Step 4: Re-run focused tests and inspect the archive listing** to verify settings backups/raw text are excluded.
- [ ] **Step 5: Commit** `diagnostics: add explicit bounded evidence export`.

### Task 7: Documentation and integrated verification

**Files:**
- Create: `docs/diagnostics/ADR-0003-long-term-observability.md`
- Modify: `README.md`
- Modify: `SETUP_NOTES.md`
- Modify: `docs/superpowers/specs/2026-10-29-long-term-observability-design.md` only if implementation evidence changes a design call
- Test/inspection: all changed Swift sources and focused test files

- [ ] **Step 1: Write documentation tests/checks** that assert the supported export command, retention values, L1/L2 distinction, unavailable receiver behavior, correlation fields, and explicit no-root-cause boundary are present.
- [ ] **Step 2: Run focused tests and verify documentation checks initially fail where new text is absent**.
- [ ] **Step 3: Document what is always on, anomaly-only, retained, queryable, exportable, and not established by the probes; include the exact Air workflow and upstream A/B/HCI/PacketLogger questions.
- [ ] **Step 4: Run the proportionate full Swift suite, self-tests, release build, and `git diff --check`; inspect changed paths for frozen product behavior and render/BLE observer-effect violations.
- [ ] **Step 5: Commit** `docs: document long-term observability workflow`.

## Integrated verification commands

Run from `remote-orbit/` after focused red-green cycles:

```bash
swift test --filter LongTermObservabilityTests
swift test --filter DiagnosticAuthorityTests
swift test --filter DiagnosticExportTests
swift test
../remote-orbit/run-self-tests.sh
git diff --check
```

For source changes, run the repository's established release build/self-check path; do not install or modify `/Applications/RemoteOrbit.app`.

## Self-review coverage

- Every task maps to a requested task-card requirement: accounting/trace/anomaly/lag, retention/query, export/receiver evidence, documentation, and observer-effect gates.
- The only persistent authority is `DiagnosticAuthority`; no second log/query system is introduced.
- The trace is fixed-capacity and detached before snapshot; the journal is fixed-segment and scanned page-wise.
- Product behavior changes have no implementation task and are explicitly prohibited.
- Remaining uncertainty is preserved: anomaly flags decide evidence retention only and do not infer BLE, decode, AudioPipe, or receiver root cause.
