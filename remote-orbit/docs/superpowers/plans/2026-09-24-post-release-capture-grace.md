# P1-A9 Automatic Post-Release Capture Grace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the ATVV capture session alive for a bounded 1000 ms after physical release, then perform the existing MIC_CLOSE, AUDIO_STOP drain, AudioPipe drain, and Option-Up sequence without allowing stale callbacks to close a newer session.

**Architecture:** Add a small owner-backed grace controller that owns its DispatchWorkItem and generation/session guard. BLEBridge starts it on physical release, keeps the existing voice intent and keepalive alive, sends MIC_CLOSE only from the controller's current expiration callback, and cancels it on re-press, remote AUDIO_STOP, disconnect, transport stop, or app shutdown. Add diagnostic lines for grace start/cancel/expire and a PHYSICAL_UP timing marker; leave existing tail drain, AudioPipe drain, HardwareOptionGate, keepalive interval, and firmware timeout untouched.

**Tech Stack:** Swift 5.9, XCTest, CoreBluetooth, Foundation DispatchWorkItem.

**Spec:** User-provided P1-A9 — Automatic Post-Release Capture Grace pasted specification.

## Global Constraints

- `POST_RELEASE_CAPTURE_GRACE` is exactly `1000ms` in this first implementation.
- The grace is between physical release and the real remote-session MIC_CLOSE, not an Option-Up delay.
- Existing `tailDrainDelay`, `audioStopDrainDelay`, output-drain barrier, HardwareOptionGate, keepalive interval/bytes/stream ID, driver, FloatTabs, Doubao, and ~60s firmware behavior remain unchanged.
- The worktree must remain on `913ab96bf5ab44e97a293d6e86a7259a9b4060a5` as the implementation baseline, with PR #12 Draft and unmerged.
- No sensitive speech/text is recorded by the new telemetry.

## Review Focus

- A release must not transmit MIC_CLOSE synchronously; test the controller remains waiting until explicit expiration.
- A stale expiration token must not close a newer or continuing session; test generation and session guards.
- Remote AUDIO_STOP, disconnect, transport stop, and app shutdown must cancel the pending grace without sending a second MIC_CLOSE.
- Keepalive must remain owned by the existing streaming/AUDIO_STOP lifecycle; no grace code may stop it at physical release.
- Option-Up must remain downstream of the existing output-drain completion, and short-press behavior must remain unchanged.

---

### Task 1: Add the owned post-release grace state machine

**Files:**
- Create: `Sources/RemoteOrbit/PostReleaseCaptureGrace.swift`
- Test: `Tests/RemoteOrbitTests/PostReleaseCaptureGraceTests.swift`

**Interfaces:**
- `PostReleaseCaptureGraceController(duration: TimeInterval = 1.0)` owns a cancellable `DispatchWorkItem`.
- `start(sessionID:) -> UInt64` returns a generation token and schedules expiration.
- `cancel(sessionID:) -> Bool` cancels only the active matching session, if any.
- `expireForTesting(sessionID:generation:) -> Bool` exercises the same guarded expiration path without sleeping.
- `onExpire` receives `(sessionID: String, generation: UInt64)` only for the current active token.

- [x] **Step 1: Write failing tests** for start/waiting, explicit expiration, cancellation, stale generation, and one-second configuration.
- [x] **Step 2: Run the focused test target and confirm the expected missing-type failures.**
- [x] **Step 3: Implement the controller with an owned work item, session ID, generation guard, and test-only expiration hook.**
- [x] **Step 4: Run focused tests and confirm all controller cases pass.**

### Task 2: Add release-grace telemetry and BLEBridge integration

**Files:**
- Modify: `Sources/RemoteOrbit/ATVV/ATVVKeepAliveTelemetry.swift`
- Modify: `Tests/RemoteOrbitTests/ATVVKeepAliveTelemetryTests.swift`
- Modify: `Sources/RemoteOrbit/BLEBridge.swift`
- Modify: `Tests/RemoteOrbitTests/BLEBridgeTests.swift`

**Interfaces:**
- `ATVVKeepAliveTelemetry.postReleaseGraceLine(...)` emits `POST_RELEASE_GRACE_STARTED`, `POST_RELEASE_GRACE_CANCELLED`, or `POST_RELEASE_GRACE_EXPIRED` with `session_id`, `configured_grace_ms`, `elapsed_ms_from_AUDIO_START`, and `reason`.
- BLEBridge owns one `PostReleaseCaptureGraceController`, starts it from `stopVoiceInput()` before any MIC_CLOSE, and sends MIC_CLOSE only from the guarded expiration callback.
- `AUDIO_STOP`, accepted incompatible audio start, transport cancellation, disconnect/stop, and app shutdown cancel the controller; remote AUDIO_STOP follows the existing drain path and never sends a stale MIC_CLOSE.

- [x] **Step 1: Add failing telemetry and transport-state tests.**
- [x] **Step 2: Run the focused tests and confirm they fail for the missing telemetry/state behavior.**
- [x] **Step 3: Add telemetry formatting and wire BLEBridge start/cancel/expire paths without changing the existing drain constants or keepalive timer.**
- [x] **Step 4: Run focused tests and confirm telemetry/state behavior passes.**

### Task 3: Preserve gesture timing, re-press, and Option-Up boundaries

**Files:**
- Modify: `Sources/RemoteOrbit/main.swift`
- Modify: `Sources/RemoteOrbit/VoiceOptionTrigger.swift` only if timing formatting requires it
- Test: `Tests/RemoteOrbitTests/VoicePressCoordinatorTests.swift`

- [x] **Step 1: Add a failing PHYSICAL_UP ordering assertion and regression assertions for re-press, Option-Up-after-drain, short press, and existing tail timing.**
- [x] **Step 2: Run the focused tests and observe the expected failures.**
- [x] **Step 3: Mark PHYSICAL_UP at the existing physical release seam and leave HardwareOptionGate/Option-Up/output drain ownership unchanged.**
- [x] **Step 4: Run the focused gesture tests and confirm all ordering/regression cases pass.**

### Task 4: Full verification, exact installation, and hardware validation

**Files:**
- Modify: none beyond Tasks 1–3.

- [ ] **Step 1: Run `swift test`.**
- [ ] **Step 2: Run `./run-self-tests.sh`.**
- [x] **Step 3: Run `git diff --check`.**
- [ ] **Step 4: Build/package/install the exact diagnostic build from the final clean HEAD and run `verify-audio-p0-diagnostic-build.sh`.**
- [ ] **Step 5: Perform exactly three 30–45 second immediate-release hardware runs, correlating PHYSICAL_UP → grace start → approximately 1000 ms → MIC_CLOSE_TX → AUDIO_STOP → app drain → Option-Up.**
- [ ] **Step 6: Report C1–C3, test results, stale MIC_CLOSE, stuck Option, rapid re-press result, remaining downstream visibility boundary, and stop without merging PR #12.**
