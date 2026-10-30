# RemoteOrbit Current Task

## RO-VOICE-PIPELINE-SIMPLIFICATION-042 — Rapid Re-press Transport-Epoch Corrective

Status: `CORRECTIVE_REQUIRED`

Repository: `Lost0rz/RemoteOrbit`
Active branch: `codex/voice-pipeline-simplification-042`
Evidence/design authority: `docs/incidents/2026-10-30-042-host-mic-open-rapid-repress.md`
Prior source-audit PASS target: `6fb609ea9fdda31cbe7dbd87b78c64839e47a065`
Runtime-preparation head before this corrective: `e19d57719019bcf415e9853d5a2ad0ac2e453773`

## Source-audit STOP reconciliation (2026-10-31)

Independent Web `CODE_DIFF` audit reviewed source state
`f1b0f700fe618d744afdb0a3350b33cc87880d53` and returned `STOP`.

When B `AUDIO_START` supersedes A's physical `AUDIO_STOP` drain, the current
source retires A's BLE ingress barrier but does not publish A's terminal
transport-stop boundary to the direct coordinator. A can therefore fail to
reach output drain, trigger-UP/ACK, and `completeDirectVoiceSession` while B
remains pending. A plain `streaming=false` notification is insufficient because
the A teardown path can clear B's candidate/prebuffer.

This task now authorizes only the bounded A-terminal/B-preservation corrective
below. The current source, tests, and control records must be updated together
again after implementation.

## Objective

Fix the RC003-confirmed extreme rapid re-press failure without regressing accepted steady-state behavior, tail preservation, READY reuse, or prior Task 042 trigger serialization.

A new physical stream can begin while the previous physical stream is still inside the 350 ms `AUDIO_STOP` drain. Current code can ignore the new `AUDIO_START`, keep later audio under the old transport epoch, and reject or debounce the matching HID press. Separate old queued PCM drain from new BLE transport ownership.

## Required corrective model

### A. Transport epoch supersession

When an old physical-HTT stream is already in terminal `AUDIO_STOP` drain and an explicit physical `AUDIO_START reason == 0x03` arrives with a different stream ID, treat it as a new transport epoch.

- retire only the old BLE ingress drain barrier, protected by stream/generation identity;
- preserve already queued A PCM for output drain;
- start decoder state for B and install B stream ID;
- classify B as `.preHIDPhysical`;
- retain READY;
- stale A drain completion must not mutate or retire B.

Do not broaden this to same-stream duplicates, non-0x03 events, global UNKNOWN remaps, or normal host-grace behavior.

### B. Candidate PCM isolation

PCM owned by `.preHIDPhysical` must use a candidate-only AudioPipe path. It must not render through old session A merely because A's route is still active.

A queued output may finish; B candidate PCM accumulates separately; old A teardown must not clear B candidate/prebuffer; later B adoption promotes B candidate audio only.

### C. Earlier direct re-press deferral

If old direct session A has observed physical UP and a live new pre-HID candidate B exists, retain the existing one-slot pending direct B even before A reaches `directOutputDrainRequested`.

B remains serialized behind A. No B trigger DOWN/route/session promotion occurs until A transport/output/trigger-UP ownership retires. Early B UP still cancels cleanly.

### D. BLE live-candidate truth

Expose a thread-safe BLE read for a live `.preHIDPhysical` candidate so admission/debounce decisions do not depend only on asynchronous main-queue callback propagation.

### E. Evidence-gated microphone debounce bypass

Keep the generic 180 ms debounce. For the microphone key only, bypass debounce for a rapid DOWN when BLE already proves a live new physical candidate. Without that evidence, existing debounce behavior remains unchanged.

## Required tests

At minimum prove:

1. new reason03/different-stream start supersedes old physical drain;
2. stale old drain callback cannot retire the new stream;
3. B candidate PCM cannot render in A route;
4. A output drain cannot clear B candidate prebuffer;
5. B HID during old transport drain is deferred, not busy, even before `directOutputDrainRequested`;
6. existing A-UP-before-B-DOWN and promoted-B UP/output-drain/replay-ACK ordering stays green;
7. live candidate bypasses microphone 180 ms debounce;
8. no live candidate preserves debounce;
9. non-0x03/same-stream input does not use this supersession;
10. normal 350 ms tail behavior and prior HOST_MIC_OPEN safety stay green.

## Additional corrective requirement

Prove the complete lifecycle, not isolated callbacks:

```text
B AUDIO_START supersedes A ingress
-> terminally retire A transport ownership while preserving B candidate PCM
-> finish A queued output drain
-> finish A trigger-UP / replay-ACK lifecycle
-> promote B
-> adopt B's preserved candidate PCM
```

The test must also prove stale A retirement cannot clear or mutate B. If this
cannot be separated within the existing coordinator/AudioPipe ownership model,
stop and report the exact dependency instead of broadening the architecture.

## Delivered implementation evidence (2026-10-31)

- Finding validated: the old source rejected all AUDIO_START events during a
  physical AUDIO_STOP drain, allowed candidate PCM to consult the old active
  route, deferred direct re-press too late, and had no BLE-owned synchronous
  candidate truth for HID admission/debounce.
- Corrective paths: BLE transport epoch supersession with stale callback
  protection; candidate-only AudioPipe ingress and prebuffer preservation;
  earlier one-slot direct re-press retention; BLE-owned live candidate read;
  evidence-gated microphone debounce bypass.
- Focused boundary tests: 95 passed, 0 failed.
- Full Swift tests: 603 passed, 0 failed.
- ARM64 Release and x86_64 Release builds passed with exact single-arch
  validation.
- ATVV protocol self-tests passed 3/3; `git diff --check` passed.
- No package/install/runtime retest, driver/TCC mutation, merge/tag/release, or
  Gate F was performed.

Run relevant BLEBridge, AudioPipe, VoicePipelineSimplification/direct-session, HID/debounce policy, VoiceBoundaryOrdering, VoiceTriggerRuntime, PostReleaseCaptureGrace, realtime/reserve and ATVV tests; then full Swift tests, arm64/x86_64 Release builds, protocol self-tests and `git diff --check`.

## Boundary

Do not globally shorten/remove the 350 ms tail window; globally disable the 180 ms debounce; run parallel ambiguous ATVV epochs; broaden UNKNOWN; change READY, Gate C, Gate D, codec/framing, driver or TCC; add broad probes; merge/tag/release; or create Gate F.

If the smallest fix cannot preserve these boundaries, STOP and return evidence.

## Required return

Return start/final/local/remote identity, exact failure-model validation, transport-epoch predicate and stale-callback protection, candidate isolation, candidate preservation across old drain, earlier re-press deferral, live-candidate truth, debounce result, RED/GREEN tests, focused/full tests/builds/self-tests/diff check, changed paths, preserved-boundary flags, unresolved issues and next safe action.

After successful source implementation, update `CURRENT_STATUS.md` and this
file together, push the existing 042 branch, verify remote equality, and stop
at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`. Do not package/install before that
audit.
