# CURRENT_STATUS

Last updated: 2026-10-31
State: `RO-VOICE-PIPELINE-SIMPLIFICATION-042 — SOURCE_AUDIT_STOP / CORRECTIVE_REQUIRED`
Repository: `Lost0rz/RemoteOrbit`
Active branch: `codex/voice-pipeline-simplification-042`

## Current authority

- Audited source corrective: `3d7b55cc557e52e994ff5c5a6b4c2217189f2751`.
- Control handoff before this audit: `b81117cf1cd06688c0e4cc08397c42b78de81f48`.
- Independent Web `CODE_DIFF` audit result: `STOP`.
- Human RC003 runtime acceptance remains `FAIL`; no new package/install/runtime retest is authorized.
- Evidence/design authorities remain:
  - `docs/incidents/2026-10-30-042-host-mic-open-rapid-repress.md`
  - `docs/incidents/2026-10-31-042-rc003-runtime-owner-race.md`

## Audit result

Corrective A (production `noOptionEdge` pending-owner timing) is source-level acceptable:

- pending hardware begin now carries both B and serialized-behind A identities;
- no-old-UP-owner arming is explicit rather than treated as failure;
- B mapped DOWN is captured/suppressed while pending;
- promotion waits for both A completion and B DOWN capture;
- early B UP cancellation and the old held-UP/replay-ACK path remain represented by deterministic tests.

Corrective B still has one blocking callback-ordering defect.

### Blocking finding — released HOST_MIC_OPEN active-drain supersession can clear B candidate

The BLE supersession predicate itself is narrow and appropriate, but the host-grace retirement path calls `notifyStreaming(false)` before B is installed and before `notifyPhysicalTransportSuperseded()` is enqueued.

All three callbacks are dispatched asynchronously to the main queue. By the time the old `streaming=false` callback runs, BLE may already have installed B as a live `.preHIDPhysical` candidate. `VoicePressCoordinator.setRemoteStreaming(false)` then observes the direct A session and can enter `finishDirectTransportStop()`. At that moment `preserveCandidateForDirectTransportStop` is still false because the later physical-supersession callback has not run yet. The existing teardown therefore calls `AudioPipe.endRemoteCandidate()`, which clears `pendingRemotePrebuffer` and deactivates the candidate.

The subsequent `handlePhysicalTransportSupersession()` callback sets preservation too late.

This violates the required invariant that B candidate/prebuffer survive A terminal retirement.

The new BLE tests verify transport state, READY, stale drain/grace protection and no duplicate MIC_CLOSE, but they do not exercise the real `BLEBridge -> main-queue onStreamingChanged(false) -> VoicePressCoordinator -> AudioPipe` ordering. Therefore the reported 609/609 test pass does not close this blocker.

## Required next corrective

Stay in Task 042. Do not redesign the transport model.

The smallest corrective must ensure that released-HOST active-drain supersession cannot execute an old-A `streaming=false` teardown path that clears B before the coordinator knows the replacement candidate must be preserved.

Acceptable shape: use a single supersession terminal notification/order for this path, or otherwise establish preservation before any old-A terminal callback can invoke candidate teardown. Do not add timers, Doubao cooldown, new probes, AudioPipe redesign, parallel decoders, or global drain/debounce changes.

Add one deterministic cross-component regression that uses the real asynchronous callback ordering and proves:

`released HOST A + active drain -> physical B reason03/new stream -> B candidate/prebuffer installed -> A terminal retirement -> B candidate/prebuffer still present -> B later adoption/promotion succeeds`.

## Preserved boundaries

- 350 ms normal no-replacement tail unchanged.
- Generic 180 ms debounce unchanged.
- No Doubao post-processing delay/re-arm workaround.
- READY / strict READY, Gate C ring, Gate D 45 ms reserve, ATVV codec/framing unchanged.
- Driver/CoreAudio/TCC unchanged.
- No package/install/hardware runtime retest before the next independent Web source audit.
- No merge/tag/release/Gate F.

## Next

Implement only the callback-ordering/candidate-preservation corrective on the existing Task 042 branch, verify deterministically, push, and stop again at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`.