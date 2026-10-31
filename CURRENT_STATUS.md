# CURRENT_STATUS

Last updated: 2026-10-31
State: `RO-VOICE-PIPELINE-SIMPLIFICATION-042 — WAITING_FOR_INDEPENDENT_WEB_AUDIT`
Repository: `Lost0rz/RemoteOrbit`
Active branch: `codex/voice-pipeline-simplification-042`

## Current authority

- Corrective A source remains unchanged at `3d7b55cc557e52e994ff5c5a6b4c2217189f2751`.
- Corrective B callback-ordering source is committed at `b4904f2faf26535fd39ba97d3a5dd30440de13b9`.
- Control handoff before this corrective: `9907005054ff795df947b743dae15e6d9ad08671`.
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

Corrective B's callback-ordering defect was reproduced, corrected and deterministically verified.

### Finding — released HOST_MIC_OPEN active-drain supersession could clear B candidate

The BLE supersession predicate itself is narrow and appropriate, but the host-grace retirement path calls `notifyStreaming(false)` before B is installed and before `notifyPhysicalTransportSuperseded()` is enqueued.

All three callbacks are dispatched asynchronously to the main queue. By the time the old `streaming=false` callback runs, BLE may already have installed B as a live `.preHIDPhysical` candidate. `VoicePressCoordinator.setRemoteStreaming(false)` then observes the direct A session and can enter `finishDirectTransportStop()`. At that moment `preserveCandidateForDirectTransportStop` is still false because the later physical-supersession callback has not run yet. The existing teardown therefore calls `AudioPipe.endRemoteCandidate()`, which clears `pendingRemotePrebuffer` and deactivates the candidate.

The subsequent `handlePhysicalTransportSupersession()` callback sets preservation too late.

This violated the required invariant that B candidate/prebuffer survive A terminal retirement.

The new cross-component regression reproduced this exact ordering before the fix.

## Corrective B implementation evidence

- Exact source change: in `supersedeReleasedHostMicOpenGraceIfNeeded`, ordinary `notifyStreaming(false)` now executes only when `oldSessionWasStreaming && !allowActiveDrain`. The active-drain replacement path therefore emits only `onPhysicalTransportSuperseded` followed by `onPreHIDPhysicalStreamChanged(true)`.
- RED: `testReleasedHostActiveDrainSupersessionPreservesCandidateThroughRealMainQueueTerminalOrdering` failed before the fix because ordinary old-A `streaming=false` was emitted and B candidate samples changed from `4` to `0` after the main-queue terminal callbacks.
- GREEN: the same test passed 1/1. Ordinary old-A `streaming=false` was not emitted; physical supersession callback count was `1`; B candidate samples remained `4` before and after A terminal/output retirement; A completed and released its coordinator session; stale A grace expiration returned false; stale A drain completion left B `.preHIDPhysical` with `4` candidate samples; MIC_CLOSE count remained `0`; B later adopted as `voiceSession` and consumed the candidate prebuffer.
- Corrective A unchanged: `main.swift` has no diff from `3d7b55cc...`; `VoicePipelineSimplificationTests` remained green at 34/34.
- Focused suites: `VoicePipelineSimplificationTests` 34/34, `BLEBridgeTests` 51/51, `VoiceKeyFilterTests` 16/16, `HIDButtonDownPolicyTests` 5/5, `AudioPipeTests` 12/12.
- Full Swift tests: 610/610 passed.
- Release builds: arm64 and x86_64 source binaries passed architecture checks using the established package build triples.
- Protocol self-tests: 3/3 passed. `git diff --check`: passed.
- Product source scope: `remote-orbit/Sources/RemoteOrbit/BLEBridge.swift` only; test scope: `remote-orbit/Tests/RemoteOrbitTests/BLEBridgeTests.swift`; no `main.swift` or `AudioPipe.swift` change.
- No package/install/runtime retest, driver/CoreAudio/TCC mutation, merge/tag/release, new probe, or Gate F occurred.

The bounded implementation uses the existing single physical-supersession terminal boundary and does not redesign the transport model.

## Preserved boundaries

- 350 ms normal no-replacement tail unchanged.
- Generic 180 ms debounce unchanged.
- No Doubao post-processing delay/re-arm workaround.
- READY / strict READY, Gate C ring, Gate D 45 ms reserve, ATVV codec/framing unchanged.
- Driver/CoreAudio/TCC unchanged.
- No package/install/hardware runtime retest before the next independent Web source audit.
- No merge/tag/release/Gate F.

## Next

Push and verify the paired control receipt on the existing Task 042 branch, then stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`. The next safe action is an independent Web source audit; human RC003 runtime acceptance remains pending and user-owned.
