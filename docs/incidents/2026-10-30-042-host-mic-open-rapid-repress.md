# RO-VOICE-PIPELINE-SIMPLIFICATION-042 — HOST_MIC_OPEN Rapid Re-press Evidence and Design

Date: 2026-10-30
Task: `RO-VOICE-PIPELINE-SIMPLIFICATION-042`
Installed candidate: `0.2.14 (43)`
Accepted corrective source before this edge: `b1736f2feedd7ed13e4520ecdfaa0c6bf6e9b332`
Final export: `RemoteOrbit-diagnostics-20261030-135113.tar.gz`

## Archive integrity

`SHA256SUMS` verified successfully. Diagnostic journal reports zero dropped diagnostic events and zero write failures.

## Validated steady state

From 13:45:57 UTC through 13:47:53 UTC, 34 consecutive physical sessions are admitted and complete without `voice_session_busy`.

The final 20 completed sessions, 13:46:42–13:47:53 UTC, are 20/20 admitted, PHYSICAL_HTT, adopted, decoded with non-zero samples and zero rejects/zero-sample decodes, rendered with non-zero AudioPipe callbacks/filled frames, and retired through `adopted_physical_audio_stop` while READY is retained. No transport reset/loss/disconnect, MIC_OPEN error, or AUDIO_STOP timeout occurs in that 20-session window.

This validates the adopted-PHYSICAL stale-intent corrective in steady-state reuse.

## Hidden rapid-repress failures

### Sequence A — `09B0`

Host session `C8AAD51D-E665-44A5-AC4D-2C9D201A6154` starts via HOST_MIC_OPEN and renders normally. AUDIO_STOP arrives, physical release starts the 1,000 ms grace, the 350 ms audio drain finishes, and the direct coordinator closes its route. The BLE host request nevertheless remains represented by the still-waiting grace / `micOpenRequested` state.

A new physical `AUDIO_START reason=0x03`, stream 76, then arrives before that grace expires. It is classified `session_origin=HOST_MIC_OPEN`, publishes session-owned streaming while the coordinator is idle/routed=false, and matching HID `09B0` is rejected `voice_session_busy`. Stream 76 decodes 25,440 samples with zero decode rejects but has `render_callback_count=0` and `render_filled_frames=0` because no new route is acquired.

### Sequence B — `BAFD`

Session `8A416474-28E0-4090-BE07-D28206153EA5` is admitted through the host path and physically releases, starting host post-release grace. Before that old direct lifecycle is fully retired, a new physical `AUDIO_START reason=0x03`, stream 78, arrives and is again classified HOST_MIC_OPEN. Matching HID `BAFD` is rejected `voice_session_busy`.

The old grace later expires and sends MIC_CLOSE while stream 78 is active; stream 78 subsequently stops. This demonstrates that the remaining edge is both an admission-ownership problem and a delayed-close stream-identity hazard.

## Protocol constraint

ATVV 1.0 MIC_OPEN has no stream ID, while MIC_CLOSE is encoded with the supplied stream ID (`[0x0D, streamID]`). Once a new physical stream has arrived and mutable bridge `streamID` points at it, sending the old session's delayed MIC_CLOSE can terminate the new stream.

Therefore a superseded old host request must not send MIC_CLOSE after the new physical reason=0x03 stream has been accepted as the supersession boundary.

## Considered options

### Option 1 — retire host request only after healthy old AUDIO_STOP drain

This removes the stale host state in Sequence A, where the old host stream already drained, but does not solve Sequence B / no-terminal-host-stream timing where a new physical start arrives while host grace is still waiting. Rejected as incomplete.

### Option 2 — BLE-only reason=0x03 host-grace supersession

On reason=0x03 during matching released host grace, cancel grace, clear host intent locally without MIC_CLOSE, emit terminal old streaming=false, and classify incoming as preHIDPhysical. This solves ownership at BLE but can still race the matching new HID against the old direct session's output-drain/trigger-release completion. Rejected as insufficient alone.

### Option 3 — selected: host-grace supersession + serialized direct re-press

BLE performs session-specific supersession before installing the incoming stream identity: cancel matching grace, locally retire old host intent, suppress old MIC_CLOSE, terminally retire old transport ownership, retain READY, and classify the incoming reason=0x03 stream as preHIDPhysical.

If the matching HID DOWN arrives while the previous direct session still owns terminal output drain/trigger release, VoicePressCoordinator retains exactly one pending direct re-press instead of rejecting it. The new press captures its session/profile/trigger mode but emits no trigger or route until the old session completes. It then activates on a fresh lifecycle and adopts the buffered physical candidate. A pending re-press released before activation is canceled with no trigger leak.

Selected because it handles both observed sequences while preserving strict serialization of trigger/session ownership.

## Preserved behavior

- No global UNKNOWN remap.
- reason != 0x03 does not invoke this supersession rule.
- reason=0x03 without a matching released HOST_MIC_OPEN grace does not invoke host supersession.
- Normal non-superseded HOST_MIC_OPEN no-AUDIO-START grace still sends its existing exactly-once MIC_CLOSE and terminal streaming=false.
- Existing adopted-PHYSICAL retirement behavior remains unchanged.
- Long-lived READY, strict READY, Gate C ring, Gate D 45 ms reserve, ATVV codec/framing, driver/TCC, and tail/output-drain ordering remain unchanged.
- No Gate F.

## Required implementation evidence

Deterministically reproduce both `09B0` and `BAFD` shapes; prove old grace cancellation, no superseded MIC_CLOSE, incoming preHID ownership, deferred direct re-press activation after old output drain, clean early release of a pending re-press, normal host grace regression, non-0x03 behavior, and existing adopted-PHYSICAL rapid-cycle behavior.

`TASK_RECONCILIATION_REQUIRED: YES` — the prior design-only task must transition to the bounded corrective described above.
