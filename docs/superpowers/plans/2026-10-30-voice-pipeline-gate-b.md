# Voice Pipeline Gate B Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or the already selected inline execution method) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep a healthy ATVV connection READY across normal voice sessions while moving CoreBluetooth ingestion and BLE state ownership to one dedicated serial queue.

**Architecture:** Queue-own the existing `BLEBridge` rather than introducing a second transport object. CoreBluetooth delegate callbacks, ATVV parsing/decoding, transport state, timers, and drain/recovery work remain serialized on `bleQueue`; only bounded UI/voice callbacks hop to main. Normal `MIC_CLOSE` retires the per-session stream and preserves READY; fatal/reset/shutdown paths still clear transport state.

**Tech Stack:** Swift 5.9, SwiftPM, XCTest, CoreBluetooth, Foundation `DispatchQueue`/`DispatchSourceTimer`, existing ATVV and AudioPipe contracts.

**Spec:** `docs/superpowers/specs/2026-10-30-voice-pipeline-gate-b-design.md`

## Global Constraints

- Preserve ATVV v0.4/v1.0 command, framing, codec, ADPCM, sample-rate, AUDIO_SYNC, and keepalive semantics.
- Preserve Gate A `IDLE → OPENING → STREAMING → DRAINING → IDLE`, tail order, 350 ms AUDIO_STOP drain, and admission barrier.
- Preserve 041 diagnostics/privacy and existing AudioPipe `feed`/render/data-plane contracts.
- Normal session close must leave a healthy prepared transport READY and must not repeat setup on the next MIC_OPEN.
- Genuine disconnect, Bluetooth failure/reset, service/characteristic/notification/capability failure, and explicit shutdown must clear stale transport state and retain bounded recovery.
- Do not change AudioPipe architecture, jitter policy, codec/protocol semantics, gain/resampler/limiter, driver, packaging, installation, TCC, Air runtime, or Gates C/D/E.
- Update `CURRENT_STATUS.md` and `CURRENT_TASK.md` together only at the authorized completion transition, then push only `codex/voice-pipeline-simplification-042`.

## Review Focus

- A healthy normal release must not cancel the peripheral or clear discovered ATVV facts — test the state transition and reuse decision in `BLEVoiceTransportState`/`BLEBridge` seams.
- A second session must request MIC_OPEN without a new setup pass — test READY reuse and per-session intent reset/re-arming.
- A late AUDIO_START must remain rejected until the prior AUDIO_STOP drain barrier retires — retain and extend existing admission tests.
- Audio notification decode/feed must not wait for main — test queue identity and main callback marshalling, and inspect callback order in the final diff.
- Fatal transport failure must clear READY before reconnect — test reset/failure state helpers and inspect reconnect guards.

### Task 1: Lock the transport/session contract with failing tests

**Files:**
- Modify: `remote-orbit/Tests/RemoteOrbitTests/BLEBridgeTests.swift`
- Modify: `remote-orbit/Tests/RemoteOrbitTests/PostReleaseCaptureGraceTests.swift` only if the queue-injection contract needs direct coverage

**Interfaces:**
- Consumes: existing `BLEVoiceTransportState`, `BLEBridge` test seams, and `PostReleaseCaptureGraceController`.
- Produces: executable assertions for connection lifecycle, READY reuse, per-session close, dedicated queue identity, and main callback ownership.

- [ ] **Step 1: Write failing tests** for:
  - `DISCONNECTED → CONNECTING → READY`, followed by per-session voice intent close that keeps READY;
  - a second session from READY re-arms MIC_OPEN without making setup eligible again;
  - fatal reset clears READY and stale characteristics/capability facts;
  - the bridge exposes a non-main dedicated serial queue identity;
  - bridge callbacks delivered from BLE ownership are observed on main while the BLE queue remains free to continue;
  - post-release grace can be scheduled on an injected queue without changing its one-shot generation semantics.
- [ ] **Step 2: Run only the new focused tests and confirm RED** for the missing lifecycle/queue behavior, correcting test errors until the failure is caused by the absent Gate B contract.

Run: `swift test --package-path remote-orbit --filter BLEBridgeTests`

Expected: existing tests pass or fail only at the newly added Gate B assertions; the new assertions fail because normal close still clears transport and CoreBluetooth is still initialized on `.main`.

- [ ] **Step 3: Commit the red tests** only if the repository task workflow requires an intermediate commit; otherwise keep the red test changes as the first implementation worktree delta for the next task.

### Task 2: Establish one BLE queue and explicit state ownership

**Files:**
- Modify: `remote-orbit/Sources/RemoteOrbit/BLEBridge.swift`
- Modify: `remote-orbit/Sources/RemoteOrbit/PostReleaseCaptureGrace.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/BLEBridgeTests.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/PostReleaseCaptureGraceTests.swift`

**Interfaces:**
- Consumes: Task 1's state/queue assertions and the existing `BLEBridge` public callbacks.
- Produces: `BLEBridge` initialized with one labeled serial `bleQueue`, queue-owned CoreBluetooth/ATVV state, queue-owned timeout/keepalive/drain scheduling, and explicit main callback helpers.

- [ ] **Step 1: Add the smallest transport lifecycle helpers** to `BLEVoiceTransportState`: explicit `DISCONNECTED`, `CONNECTING`, and `READY` facts plus transitions that keep `voiceInputRequested`/`micOpenRequested` session-scoped. Preserve compatibility fields only where existing diagnostics/tests require them.
- [ ] **Step 2: Implement `bleQueue` and pass it to `CBCentralManager`**, with a queue-specific identity seam for tests. Convert bridge public entry points and test seams to enqueue or synchronously inspect through that queue so no public main caller writes BLE state directly.
- [ ] **Step 3: Move all BLE-owned delayed work** (scan/connect/handshake/reconnect, AUDIO_STOP drain, grace expiry, and keepalive) to the same serial queue. Use a queue-owned dispatch timer for keepalive because a main-run-loop `Timer` cannot own a dedicated queue.
- [ ] **Step 4: Add explicit main callback helpers** for streaming, connection, first audio, level, and admission notifications. In decoded-frame handling, feed `AudioPipe` before scheduling the main callback; do not add a wait or a main dependency to parsing/decoding.
- [ ] **Step 5: Run the focused BLE and grace tests** and make them GREEN. Fix production code, not assertions, if they fail.

Run: `swift test --package-path remote-orbit --filter BLEBridgeTests` and `swift test --package-path remote-orbit --filter PostReleaseCaptureGraceTests`

Expected: PASS, including the new queue/lifecycle assertions and all pre-existing drain/admission tests.

### Task 3: Preserve READY across normal voice-session close

**Files:**
- Modify: `remote-orbit/Sources/RemoteOrbit/BLEBridge.swift`
- Modify: `remote-orbit/Tests/RemoteOrbitTests/BLEBridgeTests.swift`

**Interfaces:**
- Consumes: queue-owned bridge from Task 2 and existing ATVV MIC_OPEN/MIC_CLOSE command methods.
- Produces: normal release that closes only the voice stream, retains prepared peripheral/characteristics/capabilities, and allows the next session to request MIC_OPEN without setup repetition.

- [ ] **Step 1: Write/extend failing lifecycle tests** that model first READY session, MIC_OPEN intent, normal close after the existing grace/drain boundary, a second MIC_OPEN intent from READY, and exactly one setup eligibility before the first READY.
- [ ] **Step 2: Run the lifecycle tests and confirm RED** because current `scheduleTransportStopAfterVoiceClose` calls `stop()` and clears READY.
- [ ] **Step 3: Replace only the normal voice-close path** with per-session `MIC_CLOSE`/stream retirement that leaves READY. Keep `stop()` for explicit shutdown and keep `clearTransportState` for genuine failure/reset paths.
- [ ] **Step 4: Ensure remote AUDIO_STOP, physical release grace, and 350 ms drain remain ordered** and that `onStreamingChanged(false)`/admission callbacks still occur in the same causal order as Gate A expects.
- [ ] **Step 5: Run the focused lifecycle and tail suites** and confirm GREEN.

Run: `swift test --package-path remote-orbit --filter BLEBridgeTests` and `swift test --package-path remote-orbit --filter VoicePipelineSimplificationTests`

Expected: PASS; no disconnect occurs in normal close seams, and stale AUDIO_START remains rejected during the active drain barrier.

### Task 4: Failure recovery and diagnostic truthfulness

**Files:**
- Modify: `remote-orbit/Sources/RemoteOrbit/BLEBridge.swift`
- Modify: `remote-orbit/Tests/RemoteOrbitTests/BLEBridgeTests.swift`
- Modify: `remote-orbit/Tests/RemoteOrbitTests/VoiceBoundaryDiagnosticsTests.swift` only if queue/transport labels require semantic assertions

**Interfaces:**
- Consumes: queue-owned lifecycle and READY-preserving close from Tasks 2–3.
- Produces: diagnostics that distinguish transport READY/CONNECTING/DISCONNECTED from voice stream state, and failure paths that clear stale state before bounded reconnect.

- [ ] **Step 1: Add failing tests** for genuine reset/disconnect/setup failure state clearing, bounded reconnect eligibility, and diagnostic transport-vs-stream labels.
- [ ] **Step 2: Run the focused diagnostics/failure tests and confirm RED** if the old `prepared/started/streaming` projection still conflates connection and stream.
- [ ] **Step 3: Update only BLE transport diagnostic projection and failure transitions**; do not add a new diagnostic authority, ring, or privacy-sensitive payload.
- [ ] **Step 4: Run BLE, ATVV telemetry, VoiceBoundaryDiagnostics, and diagnostic hardening focused suites** and confirm GREEN.

Run: `swift test --package-path remote-orbit --filter BLEBridgeTests`, `swift test --package-path remote-orbit --filter ATVVKeepAliveTelemetryTests`, `swift test --package-path remote-orbit --filter VoiceBoundaryDiagnosticsTests`, and `swift test --package-path remote-orbit --filter DiagnosticHardeningTests`

Expected: PASS with READY reuse and fatal state clear represented truthfully.

### Task 5: Full Gate B verification and controlled handoff

**Files:**
- Modify: `CURRENT_STATUS.md`
- Modify: `CURRENT_TASK.md`
- Modify: authorized Gate B implementation/test files only

**Interfaces:**
- Consumes: all green focused tests and final diff from Tasks 1–4.
- Produces: one direct-child completion/control transition commit, pushed only to the authorized branch, stopping at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`.

- [ ] **Step 1: Run focused contract suites**: BLEBridge, ATVV protocol/keepalive, VoicePipelineSimplification, VoiceBoundaryOrdering, VoiceTriggerRuntime, AudioPipe, and 041 diagnostic/continuity/export suites.
- [ ] **Step 2: Run full Swift tests** with `swift test --package-path remote-orbit` and record the exact result.
- [ ] **Step 3: Run release builds** for arm64 and x86_64 using the established repository commands; do not package/install.
- [ ] **Step 4: Run protocol self-tests** with `./remote-orbit/run-self-tests.sh` and `git diff --check`.
- [ ] **Step 5: Inspect the final diff** and prove no AudioPipe architecture, jitter policy, codec/protocol semantics, Gate A semantics, driver, packaging, install, runtime, or Gate C/D/E changes entered the branch.
- [ ] **Step 6: Revalidate branch/worktree/remote identity and current controls**, then update `CURRENT_STATUS.md` and `CURRENT_TASK.md` together to the Gate B stop state in one direct-child commit.
- [ ] **Step 7: Push only `codex/voice-pipeline-simplification-042`**, verify the remote ref contains the exact completion commit, and stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`.

Expected: all executed receipts are reported factually; any unsupported hardware/Air/natural-use acceptance remains `UNKNOWN`/owner-owned, and Gate C is not started.

## Plan self-review

- Spec coverage: queue ownership, READY reuse, per-session MIC_OPEN/MIC_CLOSE, main isolation, drain barrier, genuine failure recovery, diagnostic separation, protocol/audio preservation, focused/full builds, diff inspection, and controlled handoff are covered by Tasks 1–5.
- Step scan: each step has one test, implementation, verification, or control-plane action; no Gate C work is embedded.
- Type consistency: `bleQueue`, lifecycle helpers, callback helpers, and queue-injected grace are introduced in Task 2 and consumed by Tasks 3–5.
- Review focus coverage: each of the five review risks has an owning test/inspection step.
- Proportion: the plan keeps the existing `BLEBridge` and test surfaces and avoids a new transport object or AudioPipe rewrite.
