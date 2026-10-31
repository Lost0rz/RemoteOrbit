# RemoteOrbit Current Task

## RO-VOICE-PIPELINE-SIMPLIFICATION-042 — RC003 Runtime Failure Corrective

Status: `WAITING_FOR_INDEPENDENT_WEB_AUDIT`

Repository: `Lost0rz/RemoteOrbit`
Active branch: `codex/voice-pipeline-simplification-042`
Audited source corrective A: `3d7b55cc557e52e994ff5c5a6b4c2217189f2751`
Corrective B implementation: `b4904f2faf26535fd39ba97d3a5dd30440de13b9`
Evidence/design authorities:
- `docs/incidents/2026-10-30-042-host-mic-open-rapid-repress.md`
- `docs/incidents/2026-10-31-042-rc003-runtime-owner-race.md`

## Objective

Finish the remaining Task 042 RC003 rapid-repress corrective without changing the accepted transport/candidate/output ownership architecture.

Corrective A (`noOptionEdge` pending hardware owner) passed independent source audit. The only current blocker is the released HOST_MIC_OPEN active-drain supersession callback ordering described below.

## Blocking source-audit finding

In `BLEBridge` host-grace supersession, old A currently calls `notifyStreaming(false)` before B candidate installation and before `notifyPhysicalTransportSuperseded()` is enqueued.

Those notifications are asynchronous to the main queue. When old `onStreamingChanged(false)` runs, BLE can already report B as a live `.preHIDPhysical` candidate, but `VoicePressCoordinator.preserveCandidateForDirectTransportStop` is still false until the later supersession callback executes.

If A is already physically up, `setRemoteStreaming(false)` can therefore enter `finishDirectTransportStop()` and call `AudioPipe.endRemoteCandidate()`. That clears the newly installed B candidate/prebuffer before `handlePhysicalTransportSupersession()` can mark it preserved.

This violates the required invariant:

`B candidate installed -> A terminal retirement -> B candidate/prebuffer survives -> B promotion/adoption`.

The current BLE unit test does not include the production main-queue callback chain and therefore does not detect this ordering defect.

## Authorized corrective

Implement the smallest ordering/notification correction only.

Required semantics:

1. For released HOST_MIC_OPEN + active drain + physical reason `0x03` + different stream ID, retire the old host intent/grace without allowing an ordinary old-A `streaming=false` callback to clear B.
2. Preserve the existing single `onPhysicalTransportSuperseded` coordinator terminal boundary for replacement-stream supersession, or establish equivalent preservation before any terminal callback can tear down candidate state.
3. B must still be installed as `.preHIDPhysical`, use a new transport epoch, retain READY, and remain protected from stale A drain/grace/MIC_CLOSE callbacks.
4. A queued output drain and trigger-UP lifecycle remain authoritative and serialized ahead of B promotion.
5. Do not send duplicate/stale MIC_CLOSE.
6. Do not alter Corrective A semantics that already passed source audit.

## Required deterministic regression

Add a cross-component production-shaped regression using real asynchronous callbacks:

- A is a direct host-owned voice session and physically released;
- A is inside active AUDIO_STOP drain with released host grace;
- B physical `AUDIO_START reason=0x03` with a different stream ID arrives;
- allow the real main-queue `onStreamingChanged` / `onPhysicalTransportSuperseded` callbacks to execute;
- B candidate has buffered PCM before/through A teardown;
- assert A terminal lifecycle starts/finishes without clearing B candidate/prebuffer;
- assert B remains `.preHIDPhysical` and can later be adopted/promoted;
- assert stale A drain/grace cannot mutate B and no stale MIC_CLOSE is sent.

Also keep all existing Task 042 focused/full tests green, arm64/x86_64 Release builds green, protocol self-tests green, and `git diff --check` clean.

## Boundary

- Same Task 042 branch/workspace.
- No new architecture/design exploration.
- No AudioPipe redesign; if unavoidable, STOP and return evidence before expanding scope.
- No new probes/instrumentation.
- No Doubao cooldown/re-arm timer.
- No 350 ms drain reduction/removal.
- No generic 180 ms debounce change.
- No driver/CoreAudio/TCC mutation.
- No package/install/hardware runtime retest before independent Web source audit.
- No merge/tag/release/Gate F.

## Required return

Return:

- start/final/local/remote identities;
- exact source change and why it removes the callback-ordering hazard;
- RED/GREEN cross-component regression evidence;
- proof B candidate/prebuffer survives the real main-queue A-terminal callback sequence;
- proof stale A drain/grace/MIC_CLOSE cannot mutate B;
- confirmation Corrective A remains unchanged/green;
- focused/full test counts;
- arm64/x86_64 Release results;
- protocol self-tests;
- `git diff --check`;
- exact changed paths;
- preserved-boundary report;
- unresolved issues.

If successful, update `CURRENT_STATUS.md` and `CURRENT_TASK.md` together, push only the existing Task 042 branch, verify remote delivery, and stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`. Do not package/install.

## Completion evidence for Corrective B callback ordering

- RED was observed in `testReleasedHostActiveDrainSupersessionPreservesCandidateThroughRealMainQueueTerminalOrdering`: before the source change, ordinary old-A `streaming=false` was emitted and B candidate/prebuffer fell from 4 samples to 0 during the real main-queue callback sequence.
- The bounded source change is only `oldSessionWasStreaming && !allowActiveDrain` around ordinary `notifyStreaming(false)` in `BLEBridge.supersedeReleasedHostMicOpenGraceIfNeeded`. Active-drain replacement now uses the existing single `onPhysicalTransportSuperseded` terminal boundary, then B pre-HID notification.
- GREEN proved no ordinary old-A false callback, physical supersession count 1, B candidate 4 samples before/after A terminal/output retirement, normal A completion, stale grace/drain protection, zero MIC_CLOSE, B `.preHIDPhysical` retention and later B `voiceSession` adoption consuming the prebuffer.
- Corrective A remains unchanged and green: no `main.swift` diff from `3d7b55cc...`; `VoicePipelineSimplificationTests` 34/34.
- Focused tests: `VoicePipelineSimplificationTests` 34/34; `BLEBridgeTests` 51/51; `VoiceKeyFilterTests` 16/16; `HIDButtonDownPolicyTests` 5/5; `AudioPipeTests` 12/12. Full `swift test`: 610/610. arm64/x86_64 Release builds passed. ATVV self-tests 3/3 passed. `git diff --check` passed.
- Changed paths are limited to `remote-orbit/Sources/RemoteOrbit/BLEBridge.swift`, `remote-orbit/Tests/RemoteOrbitTests/BLEBridgeTests.swift`, and this paired control receipt. No package/install/runtime retest, driver/CoreAudio/TCC mutation, merge/tag/release, or Gate F.
- The next safe action is independent Web source audit; do not package/install before that audit.
