# CURRENT_STATUS

Last updated: 2026-10-30
State: `RO-VOICE-PIPELINE-SIMPLIFICATION-042 — HOST_MIC_OPEN_RAPID_REPRESS_DESIGN_RESOLVED / READY_FOR_LOCAL_CORRECTIVE`
Repository: `Lost0rz/RemoteOrbit`

## Current authority

- Active branch: `codex/voice-pipeline-simplification-042`.
- Accepted corrective source before the remaining host edge: `b1736f2feedd7ed13e4520ecdfaa0c6bf6e9b332`.
- Installed candidate: `0.2.14 (43)`.
- Human steady-state high-frequency retest: PASS.
- Final evidence review: STOP for merge/release because two HOST_MIC_OPEN rapid-repress admission failures remain.
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

## Next

Implement only the bounded corrective defined in `CURRENT_TASK.md`, push the existing 042 branch, and stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`. Do not package/install, merge, tag, or release before the independent source audit.
