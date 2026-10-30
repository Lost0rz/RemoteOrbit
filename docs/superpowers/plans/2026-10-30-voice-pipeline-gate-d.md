# Voice Pipeline Gate D Small Measured Jitter Reserve Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add and evaluate one fixed startup playout reserve around the Gate C PCM ring, then deliver the bounded Gate D change on the existing branch.

**Architecture:** Keep `FixedCapacityPCMFrameRing` as the only PCM authority. Add a small atomic `AudioPipePlayoutReserve` seam for candidate conversion, one-shot state, tail bypass, and start evidence; make `AudioPipe` render silence before the threshold and reuse the existing ring read after start or during tail. Extend the existing diagnostics snapshot/counter mapping rather than adding a second trace.

**Tech Stack:** Swift, XCTest, CoreAudio `AudioBufferList`, existing Darwin atomic helpers, existing RemoteOrbit diagnostic snapshots and protocol self-tests.

**Spec:** `docs/superpowers/specs/2026-10-30-voice-pipeline-gate-d-design.md`

## Global Constraints

- Output rate remains 48,000 Hz; candidate frames are exactly 0, 2,160, 3,600, and 4,800.
- Ring capacity remains 96,000 frames and newest-drop overflow remains unchanged.
- CoreAudio render adds no ordinary lock, allocation, dynamic collection, formatting, I/O, dispatch, wait, adaptive jitter, or rebuffering.
- Reserve state resets only at truthful new-session/reset boundaries and never re-arms after start.
- Tail bypass consumes all queued PCM and output drain still requires inactive route plus actual ring empty.
- BLE/ATVV, Gate A/B/C semantics, codec, gain, limiter, resampling, driver, runtime, install, TCC, Air, and Gate E remain unchanged.

## Review Focus

- Reserve silence must not increment active underruns or first-real-PCM markers — pinned by `RESERVE_WAIT_NOT_UNDERRUN` and `FIRST_RENDER_MARKERS`.
- Tail release before threshold must not strand PCM or deadlock drain — pinned by `SHORT_UTTERANCE_TAIL_BYPASS` and `OUTPUT_DRAIN_AFTER_BYPASS`.
- A later queue dip must not re-arm reserve — pinned by `NO_REARM` and `AFTER_START_UNDERRUN`.
- Candidate choice must be evidence-backed and bounded — pinned by `CANDIDATE_COMPARISON` and `SUSTAINED_DEFICIT_CONTROL`.
- Existing ring/session ownership must survive the seam — pinned by `SESSION_RESET`, `OVERFLOW`, and the Gate C/regression suites.

### Task 1: Add the pure reserve state and candidate experiment seam

**Files:**
- Create: `remote-orbit/Sources/RemoteOrbit/AudioPipePlayoutReserve.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/AudioPipePlayoutReserveTests.swift`

**Interfaces:**
- `AudioPipePlayoutReserveCandidate` exposes `0/45/75/100 ms` and exact frame conversion at 48 kHz.
- `AudioPipePlayoutReserve` exposes reset, one-shot threshold/tail decisions, and bounded snapshot evidence.
- `AudioPipeReserveSimulation` returns comparable candidate metrics and sustained-deficit metrics.

- [ ] **Step 1: Write failing candidate/state tests** for exact frame thresholds, zero-ms immediate start, threshold-only start, no re-arm, tail bypass, session reset, and candidate comparison/sustained deficit.
- [ ] **Step 2: Run the focused reserve tests** and confirm the new types/behaviors fail before implementation.
- [ ] **Step 3: Implement the bounded reserve seam** with scalar atomics only on the render-facing decision path; keep simulation pure and deterministic with no product runtime dependency.
- [ ] **Step 4: Run the focused reserve tests** and confirm all state and comparison assertions pass.

### Task 2: Integrate reserve waiting and truthful render accounting

**Files:**
- Modify: `remote-orbit/Sources/RemoteOrbit/AudioPipe.swift`
- Modify: `remote-orbit/Sources/RemoteOrbit/AudioPipeRealtime.swift`
- Modify: `remote-orbit/Sources/RemoteOrbit/AudioDataPlaneDiagnostics.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/AudioPipeRealtimeTests.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/AudioPipeTests.swift`

**Interfaces:**
- `AudioPipeRenderState.reserveWait` is intentional silence: no active underrun, starvation, front-edge, rendered PCM, or first-render marker.
- `AudioPipePCMReadResult` remains truthful with zero consumed remote frames during reserve wait.
- `AudioPipeDiagnosticsSnapshot` carries reserve candidate, frames, start depth, wait duration, start reason, and selected default.

- [ ] **Step 1: Add failing integration tests** for reserve silence, exact threshold consumption, no re-arm after underflow, tail bypass/drain, reset, and marker/diagnostic truth.
- [ ] **Step 2: Run the focused AudioPipe tests** and confirm they fail for the current always-consume render path/accounting.
- [ ] **Step 3: Integrate the reserve before `outputRing.read`**, add bounded direct silence, add `.reserveWait` accounting, and merge reserve evidence into the existing diagnostics snapshot without changing the ring.
- [ ] **Step 4: Run focused realtime/AudioPipe/diagnostic suites** and confirm reserve behavior plus Gate C behavior pass.

### Task 3: Record experiment evidence and update control records

**Files:**
- Modify: `remote-orbit/Sources/RemoteOrbit/BLEBridge.swift`
- Modify: `remote-orbit/Sources/RemoteOrbit/DiagnosticHardening.swift` only if required by existing snapshot serialization
- Modify: `CURRENT_STATUS.md`
- Modify: `CURRENT_TASK.md`

- [ ] **Step 1: Add/extend the existing summary evidence** so configured reserve and start evidence are available without a new diagnostic authority; run the deterministic comparison and capture its exact metrics.
- [ ] **Step 2: Run the required focused regression suites** from the Gate D card.
- [ ] **Step 3: Run full Swift tests, arm64/x86_64 Release builds, protocol self-tests, and `git diff --check`.
- [ ] **Step 4: Perform a final diff audit** proving ring capacity, BLE/ATVV, Gate A/B/C, Gate E, driver/runtime/install/TCC are unchanged.
- [ ] **Step 5: Update `CURRENT_STATUS.md` and `CURRENT_TASK.md` together** to record the actual candidate evidence, selected default or unresolved selection, verification receipts, and `WAITING_FOR_INDEPENDENT_WEB_AUDIT` stop state.
- [ ] **Step 6: Commit the authorized Gate D changes as a direct child of the audited control HEAD, push only the existing branch, and verify exact local/remote equality.

## Verification Commands

- Focused: `swift test --package-path remote-orbit --filter AudioPipePlayoutReserveTests`
- Regression: the Gate D card's named AudioPipe, diagnostics, Voice, BLE, post-release, ATVV, and 041 suites.
- Full: `swift test --package-path remote-orbit`
- Builds: arm64 and x86_64 Release commands already used by Gate C.
- Protocol: `remote-orbit/run-self-tests.sh`
- Diff: `git diff --check`
