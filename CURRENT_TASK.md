# RemoteOrbit Current Task

## RO-VOICE-PIPELINE-SIMPLIFICATION-042 — Physical-HTT Admission Corrective

Status: `READY_FOR_LOCAL_CORRECTIVE`

Repository: `Lost0rz/RemoteOrbit`
Active branch: `codex/voice-pipeline-simplification-042`

Frozen evidence baseline: `ac3132986197bfee4440bb8f388e3d2e5f478f03`
Accepted source candidate before runtime failure: `2d09b6d77f9f75aa46bb4a13838cd22d5589f524`
Incident record: `docs/incidents/2026-10-30-042-no-waveform-physical-htt-admission-race.md`

## Objective

Fix one confirmed runtime ordering defect:

A Gate B long-lived READY transport can receive `AUDIO_START reason=0x03 / PHYSICAL_HTT` before the matching HID voice-key down. Current code publishes that transport-level stream as coordinator-owned `remoteStreaming=true`, causing the same physical HID press to fail `voice_session_busy`; the remote route never activates even though BLE audio and decoded PCM are present.

This is a bounded corrective inside Task 042. It is not Gate F and is not authorization for broader redesign.

## Evidence-supported root cause

The failed runtime bundle proves:

- Doubao trigger/profile path is alive;
- ATVV READY is alive;
- later physical presses produce pre-HID `PHYSICAL_HTT` `AUDIO_START`;
- BLE notifications and ADPCM decode can succeed;
- WAV capture contains decoded PCM;
- the matching HID press is repeatedly rejected as `voice_session_busy`;
- `AudioPipe` remains non-routed / reserve waiting / no active render fill while CoreAudio idle callbacks continue.

Current source explains the contradiction:

- `BLEBridge.handleControl(.audioStart)` calls `AudioPipe.beginRemoteCandidate()`, sets internal `isStreaming=true`, then calls `notifyStreaming(true)` even when the stream is only pre-HID physical transport state;
- main forwards every `onStreamingChanged(true)` to `voicePress.setRemoteStreaming(true)`;
- `VoicePressCoordinator.hasReleaseOrTailOwnershipForReconfiguration` includes `remoteStreaming`;
- direct-session admission therefore rejects the matching HID press.

No additional probe is authorized or required before correction.

## Authorized corrective

Implement the smallest design that separates:

1. transport-level/pre-HID ATVV streaming used for bounded pre-roll; and
2. session-owned streaming used by `VoicePressCoordinator` admission/retirement ownership.

Required semantics:

### A. Pre-HID physical stream must not poison admission

When `AUDIO_START` is observed before HID admission and the stream is not yet owned by a current direct voice session:

- BLE internal stream state may become active;
- decode/recording/diagnostics may proceed;
- `AudioPipe.beginRemoteCandidate()` may retain the existing bounded pre-roll;
- but this fact alone must NOT make `VoicePressCoordinator.hasReleaseOrTailOwnershipForReconfiguration` true for the matching press.

The matching HID down must remain admissible unless there is genuine prior-session release/tail ownership or the existing AUDIO_STOP drain barrier is active.

### B. Adopt an already-active physical stream

If the HID press is admitted while BLE is already streaming from the same physical press:

- establish the normal direct-session/profile/trigger ownership;
- activate the remote route (`AudioPipe.remoteActive=true`) through the existing coordinator path;
- preserve and promote the bounded pre-HID PCM candidate into the active route;
- bind/associate the live transport stream with the current session as needed for truthful diagnostics/retirement;
- do NOT issue a duplicate host `MIC_OPEN` merely because `voiceInputRequested` became true after physical streaming had already started.

The implementation may expose a bounded BLE query/adoption seam or equivalent session-owned streaming state. Do not create a second audio pipeline or a parallel session authority.

### C. Preserve normal host-MIC_OPEN path

When no physical stream is already active, existing direct admission must continue to:

- request voice input;
- require strict READY;
- send exactly one host `MIC_OPEN`;
- receive AUDIO_START;
- enter normal session-owned streaming.

### D. Retirement remains Gate A-E compatible

After a stream is adopted/owned:

- `AUDIO_STOP` / transport loss still retire the session;
- physical UP still enters normal retirement;
- route-off preserves queued tail;
- Gate D reserve tail-bypass remains intact;
- actual ring-empty/output-drain remains the trigger-UP boundary;
- duplicate/stale callbacks cannot release the next session;
- no duplicate trigger UP.

If an unowned physical stream stops before HID admission, it must clear its transport/pre-roll state without leaving coordinator ownership or a permanent busy condition.

## Explicitly not authorized

Do NOT:

- disable Gate B long-lived READY transport;
- disconnect after every session as a workaround;
- change strict READY;
- change ATVV packet/codec/framing/capability semantics;
- change the 45 ms Gate D reserve;
- change the Gate C 96,000-frame ring or overflow policy;
- change gain/limiter/resampling;
- restore SHORT/LONG/Persistent semantics;
- change driver/install/TCC/Air policy;
- merge/tag/release/package/install in this corrective;
- create Gate F;
- add broad new probes or diagnostic authorities.

## Required tests

Add deterministic coverage for at least:

1. `PHYSICAL_AUDIO_START_BEFORE_HID_IS_ADMISSIBLE`
   - transport reports physical/pre-HID streaming;
   - matching HID direct press is accepted, not `voice_session_busy`.

2. `PRE_HID_AUDIO_IS_CANDIDATE_NOT_SESSION_OWNERSHIP`
   - pre-HID stream does not set coordinator release/tail ownership by itself.

3. `ADOPT_PHYSICAL_STREAM_WITHOUT_DUPLICATE_MIC_OPEN`
   - HID admission during already-active physical stream activates route/session ownership;
   - no host `MIC_OPEN` is transmitted for adoption.

4. `PREBUFFER_PROMOTED_ON_ADOPTION`
   - decoded PCM received before HID admission is retained within existing bounded candidate semantics and becomes renderable after route activation.

5. `HOST_MIC_OPEN_PATH_UNCHANGED`
   - absent pre-existing physical stream, strict READY path still sends one MIC_OPEN and streams normally.

6. `UNOWNED_PHYSICAL_STREAM_STOP_CLEARS_BUSY_STATE`
   - physical stream that ends before HID admission cannot strand `remoteStreaming`/ownership.

7. `ADOPTED_STREAM_RETIREMENT`
   - physical UP/AUDIO_STOP → route inactive → tail/ring drain → exactly-once trigger UP.

8. `RAPID_NEXT_SESSION_AFTER_ADOPTED_STREAM`
   - next press is admitted after prior drain and stale callbacks cannot affect it.

Run relevant regressions:

- VoicePipelineSimplificationTests;
- VoiceBoundaryOrderingTests;
- VoiceTriggerRuntimeTests;
- BLEBridgeTests including strict READY/reuse;
- PostReleaseCaptureGraceTests;
- AudioPipe / AudioPipeRealtime / playout reserve tests;
- ATVV tests;
- 041 DiagnosticHardening/continuity/export tests.

Also run full Swift tests, arm64/x86_64 Release builds, protocol self-tests, and `git diff --check`.

## Final diff constraints

Explicitly report:

- LONG_LIVED_READY_CHANGED: YES/NO — expected NO
- STRICT_READY_CHANGED: YES/NO — expected NO
- MIC_OPEN_PROTOCOL_CHANGED: YES/NO — expected NO protocol change; only eligibility/adoption semantics may change
- GATE_C_RING_CHANGED: YES/NO — expected NO
- GATE_D_45MS_CHANGED: YES/NO — expected NO
- DRIVER_RUNTIME_CHANGED: YES/NO — expected NO
- GATE_F_CREATED: YES/NO — expected NO

## Delivery / stop state

After implementation:

1. update `CURRENT_STATUS.md` and `CURRENT_TASK.md` together;
2. push only `codex/voice-pipeline-simplification-042`;
3. verify local/remote exact equality;
4. stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`;
5. do not package/install the corrective candidate yet;
6. do not merge/tag/release.

Return actual evidence only. Do not predeclare PASS.
