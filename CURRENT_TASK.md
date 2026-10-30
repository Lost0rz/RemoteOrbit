# RemoteOrbit Current Task

## RO-VOICE-PIPELINE-SIMPLIFICATION-042 — Adopted Physical Grace Intent Corrective

Status: `READY_FOR_LOCAL_CORRECTIVE`

Repository: `Lost0rz/RemoteOrbit`
Active branch: `codex/voice-pipeline-simplification-042`
Accepted corrective source before this incident: `7dfd2e0c9ab71d3fa437be9b4c5cfac1282d9b1c`
Incident record: `docs/incidents/2026-10-30-042-adopted-physical-grace-intent-race.md`
Frozen 041 observability baseline: `ac3132986197bfee4440bb8f388e3d2e5f478f03`

## Objective

Fix one evidence-confirmed lifecycle race left after the first Physical-HTT admission corrective.

An adopted physical stream can finish healthy AUDIO_STOP/tail retirement after physical release while its BLE post-release grace still retains stale `voiceInputRequested=true`. A rapid next physical AUDIO_START then becomes `session_origin=UNKNOWN`, is treated as session-owned streaming, and poisons the matching HID admission with `voice_session_busy` even though BLE continues decoding real PCM.

This is a bounded corrective inside Task 042. It is not Gate F and does not authorize broader redesign.

## Evidence-supported root cause

The fresh runtime window establishes:

- the preceding adopted physical session rendered audio successfully and returned coordinator state to idle;
- physical release had started the existing post-release grace;
- healthy AUDIO_STOP/tail retirement completed before that grace expired;
- the next physical AUDIO_START occurred while stale BLE `voiceInputRequested=true` remained;
- `micOpenRequested=false && voiceInputRequested=true` maps to `ATVVSessionOrigin.UNKNOWN`;
- current ownership mapping treats UNKNOWN as `voiceSession`;
- `notifyStreaming(true)` therefore made the coordinator busy before matching HID DOWN;
- matching HID was rejected `voice_session_busy`;
- BLE still decoded credible non-zero PCM, while AudioPipe remained unrouted with zero render callbacks.

Existing evidence is sufficient. Do not add a probe.

## Authorized corrective

Implement the smallest lifecycle correction for an **adopted physical stream only**.

After all of the following are true:

1. the live stream was originally `PHYSICAL_HTT` and was adopted into the direct session;
2. no host `MIC_OPEN` was issued for that stream;
3. physical release occurred and the post-release grace is currently waiting for that session;
4. healthy `AUDIO_STOP` tail/drain has completed;

then:

- cancel/retire only that obsolete post-release grace;
- retire the old BLE voice intent (`voiceInputRequested`) for that adopted physical session;
- keep the Gate B READY transport reusable;
- do not send host `MIC_CLOSE`, because no host MIC_OPEN was issued;
- do not alter coordinator tail/ring-empty/output-drain/trigger-UP ordering.

Prefer the lifecycle point where healthy AUDIO_STOP drain completion already owns stream retirement. Keep the mutation session/stream-specific and stale-callback-safe.

### Important negative case

If AUDIO_STOP completes **before physical release**, do not retire the voice intent merely because the stream was physical. The later physical release still owns the session close transition.

### Do not solve this by broad UNKNOWN reclassification

`UNKNOWN` is a state observation, not proof that every such stream belongs to pre-HID physical transport. Do not globally map UNKNOWN to `preHIDPhysical`.

## Required deterministic tests

Add focused coverage for at least:

1. `ADOPTED_PHYSICAL_RELEASE_AND_AUDIO_STOP_RETIRES_STALE_INTENT`;
2. `ADOPTED_PHYSICAL_RETIREMENT_PRESERVES_READY`;
3. `RAPID_NEXT_PHYSICAL_STREAM_DURING_FORMER_GRACE_IS_ADMISSIBLE`;
4. `HOST_MIC_OPEN_GRACE_UNCHANGED`;
5. `AUDIO_STOP_BEFORE_PHYSICAL_RELEASE_DOES_NOT_RETIRE_INTENT`;
6. `STALE_GRACE_CALLBACK_CANNOT_MUTATE_NEXT_SESSION`;
7. `REPEATED_RAPID_ADOPTED_PHYSICAL_SESSIONS_REMAIN_ADMISSIBLE`.

Run relevant BLEBridge, VoicePipelineSimplification, VoiceBoundaryOrdering, VoiceTriggerRuntime, PostReleaseCaptureGrace, AudioPipe/realtime/reserve, ATVV, and diagnostic regressions, plus full Swift tests, arm64/x86_64 Release builds, protocol self-tests, and `git diff --check`.

## Explicitly not authorized

Do NOT broadly remap UNKNOWN; disable long-lived READY; disconnect per session; change strict READY, ATVV protocol/codec, Gate C ring, Gate D 45 ms, gain/resampling, driver/TCC/install/runtime policy; package/install; merge/tag/release; create Gate F; or add broad probes.

If the minimal fix requires changing preserved architecture, STOP and report the dependency.

## Final diff requirements

Explicitly report:

- UNKNOWN_GLOBAL_RECLASSIFICATION: YES/NO — expected NO
- LONG_LIVED_READY_CHANGED: YES/NO — expected NO
- STRICT_READY_CHANGED: YES/NO — expected NO
- HOST_MIC_OPEN_GRACE_CHANGED: YES/NO — expected NO
- MIC_CLOSE_PROTOCOL_CHANGED: YES/NO — expected NO
- GATE_C_RING_CHANGED: YES/NO — expected NO
- GATE_D_45MS_CHANGED: YES/NO — expected NO
- DRIVER_RUNTIME_CHANGED: YES/NO — expected NO
- GATE_F_CREATED: YES/NO — expected NO

## Delivery / stop state

After implementation, update `CURRENT_STATUS.md` and `CURRENT_TASK.md` together with actual evidence, commit/push only the existing 042 branch, verify local/remote equality, and stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`. Do not package/install, merge, tag, release, or start another gate.
