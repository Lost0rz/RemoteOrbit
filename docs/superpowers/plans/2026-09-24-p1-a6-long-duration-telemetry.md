# RemoteOrbit P1-A6 Long-Duration Telemetry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add observation-only, one-second long-utterance telemetry to RemoteOrbit so P1 can distinguish rate drift, app queue backlog, render underrun/overflow, and the unobservable HAL/driver boundary without changing audio timing or buffering behavior.

**Architecture:** Keep the existing BLE and AudioPipe data path unchanged. Extend the existing diagnostic counters with session-cumulative submitted/rendered remote-frame accounting and expose a value-type snapshot formatter; BLE emits a one-second session snapshot that combines its cumulative notification/decode counters with the AudioPipe snapshot. Extend the existing per-session VoiceTimingLogger timeline with queue-empty, audio-stop, and Option-up events, while explicitly reporting that driver-consume counters are unavailable because the driver is downloaded from pinned BlackHole source and exposes no app-readable FIFO telemetry.

**Tech Stack:** Swift 5.9, SwiftPM, XCTest, CoreBluetooth, CoreAudio, existing `AudioDataPlaneDiagnostics`, `AudioPipe`, `BLEBridge`, and `VoiceTimingLogger`.

**Spec:** User-provided P1-A6 request in the attached pasted text: `LONG_DURATION_TAIL_LOSS: REPRODUCED BY USER`.

## Global Constraints

- Preserve exact baseline `main@bb9fd2979979e2be0e81faba63686101d4c1a4a2`.
- Do not modify Adaptive Playout, queue size, drain duration, stop delay, silence padding, Option timing policy, or BLE dispatch behavior.
- Report app render-callback timestamps as `APP_RENDER_CALLBACK`; do not label them as receiver-heard timestamps.
- Keep `DOWNSTREAM_DRAIN_VISIBILITY` explicitly `UNAVAILABLE`; do not alter the driver architecture to fabricate HAL/driver counters.
- Emit fixed-interval session snapshots at one second while a remote stream is active; retain cumulative totals and window deltas needed for 10/30/60/90-second analysis.

## Review Focus

- A long stream with exact 16 kHz to 48 kHz resampling must show no artificial cumulative decoded/rendered drift; test exact output-frame equivalence.
- A queue that grows must expose both pending remote frames and total app queue depth without conflating them; test mixed/local queue attribution.
- Overflow and underrun counters must remain cumulative in session snapshots and must not be reset by the one-second log window; test snapshot reset boundaries.
- A stream that stops before the app queue drains must record audio-stop, drain-begin, queue-empty, drain-end, and pipeline-closed as distinct events; test event mapping/order independently of log wording.
- No app-level snapshot may claim HAL/driver consumption; test the fixed downstream visibility value and document the limitation.

### Task 1: Extend AudioPipe session accounting

**Files:**
- Modify: `remote-orbit/Sources/RemoteOrbit/AudioDataPlaneDiagnostics.swift`
- Modify: `remote-orbit/Sources/RemoteOrbit/AudioPipe.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/AudioDataPlaneDiagnosticsTests.swift`

**Interfaces:**
- Produces `AudioPipeDiagnosticsSnapshot.pendingRemoteFrames`, `.audioQueueDepthFrames`, `.submittedRemoteFrames`, and `.renderedRemoteFrames` plus existing cumulative underrun/overflow fields.
- `AudioPipe.beginRemoteAudioDiagnostics()` resets session counters; `takeAudioDiagnosticsSnapshot(resettingWindow: true)` resets only window counters while cumulative fields remain available through the non-resetting snapshot.

- [ ] **Step 1: Write failing tests** for submitted/rendered accounting, queue-depth separation, and cumulative-vs-window reset behavior using hand-derived frame counts.
- [ ] **Step 2: Run the focused diagnostics tests and verify they fail because the new snapshot fields/accounting are absent.
- [ ] **Step 3: Add minimal counters and snapshot fields; increment submitted remote frames in `schedule`, rendered remote frames in `render`, and preserve current queue/overflow semantics.
- [ ] **Step 4: Run the focused diagnostics tests and verify they pass.
- [ ] **Step 5: Run the full SwiftPM suite and record the result in the execution ledger.

### Task 2: Add one-second BLE session snapshots

**Files:**
- Modify: `remote-orbit/Sources/RemoteOrbit/AudioDataPlaneDiagnostics.swift`
- Modify: `remote-orbit/Sources/RemoteOrbit/BLEBridge.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/AudioDataPlaneDiagnosticsTests.swift`

**Interfaces:**
- Produces `AudioSessionTelemetrySnapshot` with `sessionID`, `elapsedMilliseconds`, cumulative BLE notification/byte/decode counts, submitted/rendered output frames, pending/app queue frames, active underrun totals, dropped/overflow totals, decoded-minus-rendered output-frame delta, and `downstreamDrainVisibility == .unavailable`.
- The BLE stream starts a one-second timer at `AUDIO_START`, emits a machine-readable `[AUDIO-PATH] LONG_DURATION_SNAPSHOT` line, and closes the timer before the final summary. It does not alter PCM or queue timing.

- [ ] **Step 1: Write failing value-type tests** for exact 16 kHz→48 kHz output-frame equivalence, cumulative snapshot fields, delta calculation, and unavailable downstream visibility.
- [ ] **Step 2: Run the focused tests and verify they fail for missing snapshot types/behavior.
- [ ] **Step 3: Implement the value type and formatter, then combine BLE cumulative counters with the AudioPipe cumulative snapshot at a one-second interval; keep the existing 5-second health-window behavior only where needed for compatibility.
- [ ] **Step 4: Run the focused tests and verify they pass.
- [ ] **Step 5: Run the full SwiftPM suite and record the result.

### Task 3: Complete per-session tail timing markers

**Files:**
- Modify: `remote-orbit/Sources/RemoteOrbit/VoiceOptionTrigger.swift`
- Modify: `remote-orbit/Sources/RemoteOrbit/AudioPipe.swift`
- Modify: `remote-orbit/Sources/RemoteOrbit/BLEBridge.swift`
- Modify: `remote-orbit/Sources/RemoteOrbit/main.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/AudioDataPlaneDiagnosticsTests.swift`

**Interfaces:**
- Extends the existing `VoiceTimingLogger` timeline with `T5_audio_stop_received`, `T6_queue_empty`, `T7_audio_drain_end`, `T8_audio_pipeline_closed`, `T9_option_up_requested`, and `T10_option_up_emitted` while retaining the existing human-readable markers.
- `queue_empty` is recorded only when the app-side output queue is empty at the drain barrier; render timestamps remain app callback evidence.

- [ ] **Step 1: Write failing tests** for the event-name mapping and output-frame/app-queue boundary classification.
- [ ] **Step 2: Run the focused tests and verify they fail because the new mappings/classification are absent.
- [ ] **Step 3: Add observation-only markers at existing state transitions and Option event emission points; do not change callback ordering or delays.
- [ ] **Step 4: Run the focused tests and verify they pass.
- [ ] **Step 5: Run the full SwiftPM suite and record the result.

### Task 4: Final verification and evidence report

**Files:**
- Modify: none beyond Tasks 1-3.
- Verify: `remote-orbit/Sources/RemoteOrbit/**`, `remote-orbit-audio-driver/**`, worktree status, and full test output.

- [ ] **Step 1:** Inspect the diff for prohibited playback/queue/timing behavior changes.
- [ ] **Step 2:** Run `swift test` in the isolated worktree.
- [ ] **Step 3:** Run a static audit proving the driver tree contains only the pinned-source build scripts and that no driver FIFO telemetry is exposed to the app.
- [ ] **Step 4:** Report exact files, commands, test counts, visibility boundary, and remaining hardware risk; leave the original dirty checkout untouched.
