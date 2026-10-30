# RemoteOrbit Current Task

## RO-VOICE-PIPELINE-SIMPLIFICATION-042 — HOST_MIC_OPEN Rapid Re-press Corrective

Status: `READY_FOR_LOCAL_CORRECTIVE`

Repository: `Lost0rz/RemoteOrbit`
Active branch: `codex/voice-pipeline-simplification-042`
Accepted corrective source before this remaining edge: `b1736f2feedd7ed13e4520ecdfaa0c6bf6e9b332`
Evidence/design record: `docs/incidents/2026-10-30-042-host-mic-open-rapid-repress.md`
Frozen 041 observability baseline: `ac3132986197bfee4440bb8f388e3d2e5f478f03`

## Objective

Fix the final evidence-confirmed rapid re-press edge without changing the accepted steady-state PHYSICAL_HTT path.

Two observed failures (`09B0`, `BAFD`) occur when a new explicit physical `AUDIO_START reason=0x03` arrives before the prior released HOST_MIC_OPEN request/grace has retired. Current state then makes the new physical stream look host/session-owned and the matching HID press is rejected `voice_session_busy`.

## Required corrective model

### A. BLE host-grace supersession

Track enough session-specific host-MIC_OPEN ownership to distinguish a released host request from the incoming physical stream.

When all are true:

1. incoming `AUDIO_START reason == 0x03`;
2. a previous HOST_MIC_OPEN owner is still represented by a matching waiting post-release grace;
3. that owner has observed physical release;
4. no old AUDIO_STOP drain barrier is active;

then, before assigning incoming stream identity:

- cancel the matching old grace / invalidate its delayed callback;
- retire only that old host voice intent locally (`voiceInputRequested`, `micOpenRequested`);
- do not send MIC_CLOSE for the superseded host request;
- publish the truthful terminal streaming=false boundary for the old coordinator owner when it still needs transport-stop retirement;
- retain READY;
- process the incoming reason=0x03 stream as `preHIDPhysical` candidate ownership.

The rule is explicit physical-start supersession, not a global UNKNOWN remap.

### B. Direct-session re-press serialization

A new direct HID DOWN may arrive while the previous direct session is still completing output drain/trigger release after supersession.

For exactly this terminal-overlap case:

- retain at most one pending direct re-press instead of returning `voice_session_busy`;
- require the previous direct session to have physical UP already observed / be in terminal retirement;
- require a live pre-HID physical candidate for the new press;
- capture the new session ID, `VoiceInputProfile`, and hardware/synthetic trigger mode;
- do not emit the new trigger DOWN or activate the new route while the old session still owns output drain/trigger UP;
- when `completeDirectVoiceSession` finishes the old session, activate the retained new press on the next main-queue turn and adopt the candidate;
- if HID UP for the pending press arrives before activation, cancel that pending press cleanly with no trigger leak and no stale adoption.

Do not permit two simultaneous direct sessions.

## MIC_CLOSE rule

For the superseded host request, **do not send MIC_CLOSE after the new physical reason=0x03 stream has arrived**. ATVV v1.0 MIC_CLOSE is stream-ID-bearing, while `streamID` becomes the incoming physical stream ID; a delayed close can terminate the new stream.

Normal non-superseded HOST_MIC_OPEN behavior remains unchanged:

- if no superseding physical start occurs, existing post-release grace remains;
- grace expiry still retires the host request and sends exactly one MIC_CLOSE where appropriate;
- the existing no-AUDIO-START terminal `notifyStreaming(false)` path remains.

## Required deterministic tests

At minimum cover:

1. `HOST_AUDIO_STOP_DRAINED_THEN_REASON03_BEFORE_HID_SUPERSEDES_HOST_GRACE` — reproduce `09B0`: no busy reject, no old MIC_CLOSE, incoming ownership preHIDPhysical, matching HID admitted/adopted.
2. `HOST_NO_TERMINAL_STREAM_THEN_REASON03_DURING_RELEASE_GRACE_DEFERS_DIRECT_REPRESS` — reproduce `BAFD`: old direct session terminally retires, new HID is retained while old output drain completes, then admitted/adopted.
3. `SUPERSEDED_HOST_GRACE_CALLBACK_CANNOT_CLOSE_NEW_PHYSICAL_STREAM`.
4. `SUPERSEDED_HOST_REQUEST_RETAINS_READY`.
5. `NORMAL_HOST_NO_AUDIO_START_GRACE_STILL_SENDS_ONE_MIC_CLOSE_AND_TERMINAL_STOP`.
6. `NORMAL_HOST_AUDIO_START_REASON_NOT_03_IS_NOT_SUPERSEDED`.
7. `REASON03_WITHOUT_RELEASED_HOST_GRACE_DOES_NOT_APPLY_HOST_SUPERSESSION_RULE`.
8. `PENDING_DIRECT_REPRESS_RELEASE_BEFORE_ACTIVATION_CLEARS_WITHOUT_TRIGGER_LEAK`.
9. `ONLY_ONE_PENDING_DIRECT_REPRESS_ALLOWED`.
10. `PREVIOUS_DIRECT_OUTPUT_DRAIN_AND_TRIGGER_UP_COMPLETE_BEFORE_NEW_TRIGGER_DOWN`.
11. Existing adopted-PHYSICAL rapid-cycle tests remain green.

Run relevant BLEBridge, VoicePipelineSimplification/direct-session, VoiceBoundaryOrdering, VoiceTriggerRuntime, PostReleaseCaptureGrace, AudioPipe/realtime/reserve and ATVV protocol tests, full Swift tests, arm64/x86_64 Release builds, protocol self-tests, and `git diff --check`.

## Explicitly not authorized

Do NOT:

- globally remap UNKNOWN;
- treat every reason=0x03 as supersession without the matching released host grace;
- send old MIC_CLOSE after installing the new physical stream ID;
- overlap two direct session trigger owners;
- remove/shorten host grace globally;
- disconnect per session;
- change long-lived READY or strict READY;
- change ATVV codec/framing;
- change Gate C ring;
- change Gate D 45 ms reserve;
- change driver/TCC/install/runtime;
- add broad probes;
- package/install;
- merge/tag/release;
- create Gate F.

If the smallest implementation cannot preserve these boundaries, STOP and report the dependency instead of broadening scope.

## Required return

Return actual evidence including:

- `CARD_ID`, `TASK_ID`, `MODE`, `CAPABILITY`, `TARGET`, `OUTCOME`;
- governance route / skills / topology / subagents;
- start/final/local/remote identity;
- changed paths;
- HOST_MIC_OPEN owner/supersession model;
- reason=0x03 predicate;
- old grace cancellation result;
- old host intent retirement result;
- old MIC_CLOSE suppression result;
- READY preservation result;
- incoming preHID ownership result;
- direct re-press deferred/admitted result;
- output-drain-before-new-trigger ordering result;
- pending-new-UP-before-activation result;
- normal host no-AUDIO-start regression result;
- non-0x03 regression result;
- adopted-PHYSICAL regression result;
- global UNKNOWN remap flag;
- Gate C/D / driver / TCC / Gate F mutation flags;
- focused/full tests/builds/protocol selftests/diff check;
- control alignment / unresolved / next safe action.

After successful implementation, update `CURRENT_STATUS.md` and `CURRENT_TASK.md` together, push only the existing 042 branch, verify local/remote equality, and stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`. No package/install or runtime retest before independent Web source audit.
