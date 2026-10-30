# Gate C Realtime-safe Audio Data Plane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans or superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace AudioPipe's dynamic/locking PCM playback queue with a fixed-capacity SPSC ring and realtime-safe render path without changing Gate A/B or ATVV semantics.

**Architecture:** Keep a 96,000-frame preallocated Float ring as structural transport capacity, with serialized producer-side writes and atomic producer/consumer publication. The CoreAudio callback reads directly into output buffers and publishes only bounded scalar diagnostics; non-realtime AudioPipe code consumes the bounded render observations and owns existing logging, continuity, and completion delivery.

**Tech Stack:** Swift 5.9, macOS CoreAudio, `AudioBufferList`, Darwin `OSAtomic` barriers, XCTest, existing 041 diagnostics.

**Spec:** `docs/superpowers/specs/2026-10-30-voice-pipeline-gate-c-design.md`

## Global Constraints

- Gate C only; do not begin Gate D jitter/startup reserve or Gate E boundary redesign.
- Preserve BLE/ATVV protocol, CoreBluetooth queue/READY, codec, gain/limiter, resampling, Gate A trigger/tail, grace, 350 ms drain, 600 ms safety timeout, driver, packaging, install, TCC, and Air runtime.
- Ring capacity is structural only: start empty, no prefill, no intentional startup threshold.
- Never overwrite unread PCM; ring-full writes reject the newest input and record exact overflow evidence.
- The CoreAudio callback must not allocate, mutate dynamic collections, acquire `stateLock`, perform I/O/formatting/logging, or dispatch/wait.

## Review Focus

- A ring becoming exactly full must remain distinguishable from empty and preserve FIFO order; owned by Task 1 ring tests.
- A callback larger than queued PCM must render the queued prefix and zero-fill only the suffix; owned by Task 2 render tests.
- A normal route stop must preserve queued tail while an explicit reset clears it before the next session; owned by Task 3 session/drain tests.
- Existing 041 render/continuity observations must remain available without doing their non-realtime work in the callback; owned by Task 3 diagnostic tests.
- Local microphone frames must retain existing routing and must not be attributed as remote overflow/queue depth; owned by Task 3 mixed-source tests.

### Task 1: Fixed-capacity PCM ring

**Files:**
- Create: `remote-orbit/Sources/RemoteOrbit/AudioPipeRealtime.swift`
- Create: `remote-orbit/Tests/RemoteOrbitTests/AudioPipeRealtimeTests.swift`

**Interfaces:**
- Produces `FixedCapacityPCMFrameRing(capacity:)`, `write(_:source:)`, `read(into:)`, `reset()`, and bounded read/write result structs.
- Uses preallocated Float storage, monotonic indices, atomic publication, and a producer-safe reset gate.

- [x] Write failing tests for empty read, FIFO write/read, partial read/write, exact-full, exact-empty, wraparound, repeated wrap cycles, and no overwrite of unread samples.
- [x] Run the focused ring tests and confirm the expected missing-type/member failures.
- [x] Implement the preallocated SPSC ring and deterministic newest-input rejection on full.
- [x] Add bounded consumer output-buffer read support with direct zero-fill for missing frames.
- [x] Run the focused ring tests and confirm all ring behaviors pass.

### Task 2: Integrate the ring and remove realtime hazards

**Files:**
- Modify: `remote-orbit/Sources/RemoteOrbit/AudioPipe.swift`
- Modify: `remote-orbit/Tests/RemoteOrbitTests/AudioPipeTests.swift`
- Modify: `remote-orbit/Tests/RemoteOrbitTests/AudioDataPlaneMeasurementBoundaryTests.swift`

**Interfaces:**
- Replaces `pendingOutput`/`pendingOutputIndex` queue ownership with the ring.
- Keeps `feed`, `setRemoteActive`, `waitForOutputDrain`, diagnostics snapshots, local microphone routing, and public drain semantics unchanged.

- [x] Add failing tests for underflow prefix/zero-fill, deterministic overflow/drop attribution, ring-backed queue depth, and a source-level render callback guard against array allocation, `stateLock`, dynamic mutation, and dispatch.
- [x] Run focused tests and confirm they fail for the old dynamic/locking implementation.
- [x] Integrate ring writes after existing gain/limiter/resampling, preserve remote/local attribution, and freeze compaction count at zero.
- [x] Replace render's temporary mono array and lock with direct ring-to-`AudioBufferList` consumption and atomic route state.
- [x] Run focused AudioPipe and measurement tests, then run the existing Gate A tail tests.

### Task 3: Preserve diagnostics, drain, and session boundaries

**Files:**
- Modify: `remote-orbit/Sources/RemoteOrbit/AudioPipe.swift`
- Modify: `remote-orbit/Sources/RemoteOrbit/AudioDataPlaneDiagnostics.swift`
- Modify: `remote-orbit/Tests/RemoteOrbitTests/AudioDataPlaneDiagnosticsTests.swift`
- Modify: `remote-orbit/Tests/RemoteOrbitTests/AudioDataPlaneMeasurementBoundaryTests.swift`
- Modify: `remote-orbit/Tests/RemoteOrbitTests/VoicePipelineSimplificationTests.swift`
- Modify: `remote-orbit/Tests/RemoteOrbitTests/VoiceBoundaryOrderingTests.swift`

**Interfaces:**
- Produces bounded atomic render counters and a fixed scalar observation mailbox consumed off the realtime callback.
- Preserves the existing `AudioPipeDiagnosticsSnapshot`, continuity ledger, output-drain completion, and Gate A ordering contracts.

- [x] Add failing tests for counter merge/reset, tail drain after route deactivation, explicit reset versus normal drain, stale PCM isolation, and bounded concurrent producer/consumer ordering.
- [x] Run the focused suites and confirm the missing bounded diagnostics/session behavior fails.
- [x] Move observation/log/continuity work off the callback while retaining exact underflow, tail, idle, queue-depth, overflow, and rendered/submitted evidence.
- [x] Implement event-driven off-path drain notification based on actual ring empty state.
- [x] Run all focused Gate C regression suites and confirm the complete matrix passes.

### Task 4: Final verification and governed delivery

**Files:**
- Modify: `CURRENT_STATUS.md`
- Modify: `CURRENT_TASK.md`
- No other files outside the bounded Gate C implementation/test/docs set.

- [x] Run full Swift tests, arm64 Release build, x86_64 Release build, protocol self-tests, and `git diff --check`.
- [x] Re-read the diff for Gate D/E, BLE/ATVV, Gate A/B, driver/runtime, and forbidden scope leakage.
- [ ] Update `CURRENT_STATUS.md` and `CURRENT_TASK.md` together with the Gate C receipt and stop state.
- [ ] Commit the bounded Gate C change as a direct child of the audited live head.
- [ ] Push only `codex/voice-pipeline-simplification-042`, verify exact remote SHA, and stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`.
