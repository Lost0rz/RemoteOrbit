# CURRENT_STATUS

Last updated: 2026-10-30
State: `RO-VOICE-PIPELINE-SIMPLIFICATION-042 — ADMISSION ATOMIC PROMOTION CORRECTIVE IMPLEMENTED / WAITING_FOR_INDEPENDENT_WEB_AUDIT`
Repository: `Lost0rz/RemoteOrbit`

## Current authority

- Active branch: `codex/voice-pipeline-simplification-042`.
- Accepted corrective source before the remaining host edge: `b1736f2feedd7ed13e4520ecdfaa0c6bf6e9b332`.
- Audited source before promoted-B ownership correction: `d54bfd56a3f098766ed1013116928e1f77822277`.
- Installed candidate: `0.2.14 (43)`.
- Human steady-state high-frequency retest: PASS.
- Source implementation now includes the bounded promoted-B owner correction; merge/release remains stopped pending independent Web source audit and human corrective runtime acceptance.
- The admission-atomic promotion correction is now implemented and locally validated; merge/release remains stopped pending independent Web source audit and human corrective runtime acceptance.
- Evidence/design record: `docs/incidents/2026-10-30-042-host-mic-open-rapid-repress.md`.
- Frozen 041 observability baseline: `ac3132986197bfee4440bb8f388e3d2e5f478f03`.
- `AGENTS.md` remains durable repository authority.
- `CURRENT_TASK.md` is the sole active execution authorization.

## Resolved design

The remaining failure needs two coordinated but bounded lifecycle changes.

### 1. HOST_MIC_OPEN grace supersession at BLE ownership boundary

When an explicit physical `AUDIO_START reason=0x03` arrives while:

- a matching old HOST_MIC_OPEN request is still owned by a post-release grace;
- that old direct gesture has already physically released;
- no previous AUDIO_STOP drain barrier is active;

then the new physical stream is evidence that the remote has superseded the released host-open request.

Before installing the incoming stream ID/ownership:

- cancel only the matching old grace, invalidating its generation;
- locally finish/clear only the old host voice request (`voiceInputRequested` / `micOpenRequested`);
- do **not** send MIC_CLOSE for the superseded old request;
- emit the existing terminal streaming=false boundary for the old coordinator owner when needed;
- retain ATVV READY;
- classify the incoming reason=0x03 stream as `preHIDPhysical` candidate state.

Do not globally reclassify UNKNOWN. Do not apply this rule to reason values other than 0x03.

Why no MIC_CLOSE: ATVV 1.0 MIC_CLOSE contains a stream ID. Once a new physical stream has arrived, sending the old delayed close through mutable current `streamID` can terminate the new stream. The explicit new physical start is therefore the supersession boundary; the old host request retires locally.

### 2. One-slot direct re-press deferral at coordinator boundary

BLE supersession can truthfully terminate the old direct transport, but its existing output-drain/trigger-release ordering may still be completing when the matching new HID DOWN arrives.

If the previous direct session has already observed physical UP and is in terminal drain/close ownership, and a new pre-HID physical candidate is present, retain exactly one new direct HID press instead of rejecting it `voice_session_busy`.

The pending direct re-press must capture the new session ID, profile/trigger and hardware/synthetic trigger mode. It must not emit the new trigger DOWN or activate a route until the previous direct session has completed its existing output drain and trigger-UP lifecycle. On previous-session completion, activate the pending press on a fresh lifecycle and adopt the still-buffered pre-HID candidate. If the new physical key is released before activation, cancel the pending press without trigger leakage.

This is a serialization mechanism, not overlapping session ownership.

## Preserved behavior

- Existing adopted-PHYSICAL retirement corrective remains unchanged.
- Normal HOST_MIC_OPEN with no superseding physical start retains the existing post-release grace and exactly-once MIC_CLOSE/no-AUDIO-START terminal behavior.
- HID-first new sessions that legitimately own the host request are not globally converted to physical ownership.
- Existing AUDIO_STOP drain barrier remains authoritative.
- Long-lived READY and strict READY remain unchanged.
- Gate C ring and Gate D 45 ms reserve remain unchanged.
- ATVV codec/framing remains unchanged.
- Driver/TCC/package/install behavior remains unchanged.
- No global UNKNOWN remap.
- No Gate F.

## Observed corrective implementation evidence

### Hardware-mapped rapid re-press edge

- Stage A was `FINDING_CONFIRMED` at audited control HEAD `9cae6c60f2f0fafaa2e27b49dd5a0fdcb646c93e`; fetch/reconcile found local and remote equal and the worktree clean before mutation.
- Production `AppController.beginVoicePress()` passes `usesHardwareOption=isVoiceHIDMappingEnabled()`. The existing direct pending branch returned before hardware gate ownership, and `beginOptionDeferral(newSession)` would abort the old held-UP owner. No existing deterministic test covered hardware=true direct rapid re-press with output drain outstanding.
- Implemented the smallest serialized ownership corrective: an `OLD_HELD_UP_OWNER` remains responsible for old UP replay/acknowledgement while one `NEW_PENDING_DOWN_OWNER` captures only the new mapped DOWN. Old replay acknowledgement is processed before pending capture; B promotion occurs only after old UP pass acknowledgement and on a fresh main-queue turn.
- Pending B cancellation retains a narrow tombstone until expected mapped UP components are consumed. A second pending DOWN cannot replace the first owner. Synthetic re-press does not enter this hardware owner path.
- New deterministic hardware cases: 5; focused requested suites: `238/238`; full Swift tests: `595/595`.
- Final source/test paths for this edge are limited to `remote-orbit/Sources/RemoteOrbit/main.swift` and `remote-orbit/Tests/RemoteOrbitTests/VoicePipelineSimplificationTests.swift`. `BLEBridge.swift` did not change for this edge.
- Final arm64 and x86_64 Release builds passed with the established commands below; protocol self-test script exited `0`; `git diff --check` exited `0`. Builds retain only the repository's existing macOS deprecation warnings.

- Audited control HEAD before mutation: `3d0ae437bb43efaca529a7278de519141a65d31d`; fetch/reconcile found no concurrent remote movement.
- Implemented only the bounded HOST_MIC_OPEN grace supersession and direct-session one-slot re-press serialization authorized by `CURRENT_TASK.md`.
- Host supersession is gated by reason `0x03`, a matching released HOST_MIC_OPEN grace, physical release observed, no active AUDIO_STOP drain barrier, and matching grace ownership. The old voice intent is retired locally, the old delayed callback is canceled, no superseded MIC_CLOSE is sent, READY is retained, and the incoming stream becomes `preHIDPhysical`.
- Direct re-press captures session ID, profile, and hardware/synthetic trigger mode in one pending slot. It emits no new trigger DOWN until old output drain and trigger UP complete; pending HID UP cancels without trigger leakage. A live pre-HID candidate is preserved through old coordinator completion.
- Deterministic corrective tests: 9/9 new cases passed; affected focused suites: 217/217 passed; full Swift tests: 590/590 passed.
- Release builds passed with existing macOS deprecation warnings:
  `swift build -c release --scratch-path /private/tmp/remoteorbit-042-arm64-release --triple arm64-apple-macos14.0`
  and
  `swift build -c release --scratch-path /private/tmp/remoteorbit-042-x86-release --triple x86_64-apple-macos14.0`.
- Protocol self-tests: 3/3 passed. `git diff --check`: passed.
- Changed paths are limited to `remote-orbit/Sources/RemoteOrbit/BLEBridge.swift`, `remote-orbit/Sources/RemoteOrbit/PostReleaseCaptureGrace.swift`, `remote-orbit/Sources/RemoteOrbit/main.swift`, `remote-orbit/Tests/RemoteOrbitTests/BLEBridgeTests.swift`, and `remote-orbit/Tests/RemoteOrbitTests/VoicePipelineSimplificationTests.swift`.
- No package/install/runtime retest was performed. Installed candidate remains historical `0.2.14 (43)`; human corrective runtime acceptance is pending.
- Long-lived READY, strict READY, ATVV protocol/codec, Gate C ring, Gate D 45 ms reserve, driver, TCC, and Gate F state were not changed.

### Boundary flags for the hardware corrective

- `GLOBAL_UNKNOWN_RECLASSIFICATION=NO`.
- `HOST_GRACE_SUPERSESSION_CHANGED=NO`; `SUPERSEDED_MIC_CLOSE_MODEL_CHANGED=NO`; `READY_MODEL_CHANGED=NO`; `PREHID_MODEL_CHANGED=NO`.
- `GATE_C_RING_CHANGED=NO`; `GATE_D_45MS_CHANGED=NO`; `DRIVER_RUNTIME_CHANGED=NO`; `TCC_RESET=NO`; `PACKAGE_INSTALL=NOT_RUN`; `MERGE_TAG_RELEASE=NO`; `GATE_F_CREATED=NO`.

### Promoted-B hardware-owner continuation

- Stage A finding was confirmed against `d54bfd56a3f098766ed1013116928e1f77822277`: promotion replayed B's captured DOWN but did not establish `optionGate`/`heldHardwareOptionSessionID` ownership, so B's mapped UP was observed as `pass` and no B replayed UP was produced.
- The smallest correction re-enters the existing `HardwareOptionGate` for the captured B DOWN, resolves it as `.hardwareReplay`, records B as the held hardware UP/output-drain owner, then posts the captured DOWN. The existing physical-UP arm, mapped-UP capture, output-drain replay, and event-tap acknowledgement lifecycle remains authoritative.
- Deterministic full promoted-B lifecycle: RED observed `pass` for B mapped UP and no pending B replayed UP; GREEN passed `testPromotedHardwareRepressOwnsMappedUpThroughOutputDrain`.
- Focused requested suites: `239/239`; full Swift tests: `596/596`.
- arm64 and x86_64 Release builds passed with the established commands below; protocol self-tests passed `3/3`; `git diff --check` passed. Build output contains only existing macOS deprecation warnings.
- Changed product paths for this continuation are limited to `remote-orbit/Sources/RemoteOrbit/main.swift` and `remote-orbit/Tests/RemoteOrbitTests/VoicePipelineSimplificationTests.swift`; no BLE, package, driver, TCC, or runtime files changed.
- No package/install/runtime retest was performed. Human corrective runtime acceptance remains pending.

### Admission-atomic promoted-B continuation

- Stage A finding was confirmed against audited source/control HEAD `251536d1d46e73680140b10b2f8d6cb9d21b3e7f`: `startDirectVoicePress()` invoked promoted-B ownership/replay before its final admission guard, so a newly blocked BLE admission could reject after B DOWN replay and strand B hardware ownership.
- Implemented the smallest existing-model correction: all coordinator admission guards now resolve before `onHardwareOptionGatePendingRepressPromote`. If admission is blocked, the pending hardware repress is canceled with a bounded tombstone before any B DOWN replay. If promotion ownership itself is unavailable, the same bounded cancellation path is used. Normal physical-UP-before-activation cancellation now carries its explicit reason through the same callback.
- Required ordering is now `admission confirmed → promote/replay B DOWN → start B session`; no admission rejection follows B promotion/replay.
- RED observed for `testAdmissionBlockedPromotedHardwareRepressDoesNotReplayOrLeakOwnership`: 3 assertion failures against the pre-fix source (unexpected B replay, held B owner, and active hardware gate). GREEN passed `1/1`; it proves no B DOWN replay, no held-UP owner, no active hardware gate, bounded pending tombstone consumption, no coordinator ownership leak, and idle state. Existing `testPromotedHardwareRepressOwnsMappedUpThroughOutputDrain` passed `1/1`.
- Focused requested suites passed `240/240`, including VoicePipelineSimplification, VoicePressCoordinator, VoiceKeyFilter, VoiceBoundaryOrdering, VoiceTriggerRuntime, PostReleaseCaptureGrace, BLEBridge, AudioPipe, AudioPipeRealtime, AudioPipePlayoutReserve, and ATVVKeepAliveTelemetry.
- Full Swift tests passed `597/597` with 0 failures.
- arm64 and x86_64 Release builds passed with:
  `swift build -c release --scratch-path /private/tmp/remoteorbit-042-arm64-release --triple arm64-apple-macos14.0`
  and
  `swift build -c release --scratch-path /private/tmp/remoteorbit-042-x86-release --triple x86_64-apple-macos14.0`.
- Protocol self-tests passed `3/3` with exit `0`; `git diff --check` passed. Release output contained only existing macOS deprecation warnings.
- Product source/test changes for this continuation are limited to `remote-orbit/Sources/RemoteOrbit/main.swift` and `remote-orbit/Tests/RemoteOrbitTests/VoicePipelineSimplificationTests.swift`; control files are updated in the same transition commit. No BLE semantic, packaging, driver, TCC, or runtime files changed.
- No package, install, runtime retest, merge, tag, release, or Gate F action was performed. Human corrective runtime acceptance remains pending.

### Admission-atomic boundary flags

- `ADMISSION_BEFORE_PROMOTION=YES`; `BLOCKED_PROMOTION_B_DOWN_REPLAY=NO`; `BLOCKED_PROMOTION_OWNER_LEAK=NO`.
- `GLOBAL_UNKNOWN_RECLASSIFICATION=NO`; `LONG_LIVED_READY_CHANGED=NO`; `STRICT_READY_CHANGED=NO`; `MIC_OPEN_PROTOCOL_CHANGED=NO`.
- `GATE_C_RING_CHANGED=NO`; `GATE_D_45MS_CHANGED=NO`; `DRIVER_RUNTIME_CHANGED=NO`; `TCC_RESET=NO`; `PACKAGE_INSTALL=NOT_RUN`; `MERGE_TAG_RELEASE=NO`; `GATE_F_CREATED=NO`.

## Next

Await the independent Web source audit at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`. Do not package/install, perform human runtime retest, merge, tag, release, or create Gate F before that audit.
