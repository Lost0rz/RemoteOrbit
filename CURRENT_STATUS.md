# CURRENT_STATUS

Last updated: 2026-11-01
State: `RO-DIAGNOSTICS-LEGACY-RETIREMENT-045 — WAVE_D_DOMAIN_1_IMPLEMENTATION_COMPLETE / WAITING_FOR_INDEPENDENT_WEB_AUDIT`
Repository: `Lost0rz/RemoteOrbit`
Human runtime/UI acceptance: `PENDING / USER-OWNED`

## Task 045 progress

- Task 045A: `DIAGNOSTICS_GATING / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 1: `LEGACY_VOICE_PRODUCT_SURFACE / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 2: `LEGACY_VOICE_PERSISTED_PREFERENCE_AUTHORITY / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 3: `PERSISTENT_VOICE_RUNTIME_STATE_MACHINE / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 4: `DUAL_RECEIVER_RUNTIME_STATE_MACHINE / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 5: `LEGACY_GENERIC_SHORT_CLASSIFIER_RUNTIME / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 6: `LOCAL_MICROPHONE_CAPTURE / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045D Domain 1: `REMOTE_ONLY_PCM_ATTRIBUTION / IMPLEMENTATION_COMPLETE / PR_CI_PASS / WAITING_FOR_INDEPENDENT_WEB_AUDIT`

## Domain 6 independent Web audit and closeout

Audit independence: `FRESH_CONTEXT`.

- Final reviewed PR #37 head: `85f521371dd2ff6dd5cc4e5c7cb45acf89c3e61a`.
- Immutable implementation HEAD: `84bd468ad9059b0313f07e905f169b1d41cd53e2`.
- Exact-head PR CI run `41276388399`, job `124759311071`, passed on `remoteorbit-macmini` through source contracts, protocol self-tests, full Swift 509/509, Native Release and Universal2 `x86_64 arm64` packaging.
- Independent source audit confirmed AVCapture/local microphone ownership and microphone TCC were retired while the system input selector, persisted preferred input, remote AudioPipe path and temporary input lease remained intact.
- Input lease restoration occurs only after actual output drain; rapid A→B direct repress transfers the lease without an intermediate physical-input restore. The `stop()` edge noted in the execution receipt is reached from application termination and is not a normal-runtime blocker.
- PR #37 was made Ready only after audit PASS and merged with exact expected head as `640256238941856c3eaa82a54cb6518d59792015`.
- Post-merge main CI run `41276777315`, job `124760439385`, passed source contracts, protocol self-tests, full Swift, Native Release and Universal2 packaging.
- No app install, driver/CoreAudio/TCC/default-device runtime mutation, tag/release or machine-owned RC003/Doubao acceptance was performed.

Canonical audit basis for Wave D: `main@640256238941856c3eaa82a54cb6518d59792015`.

## Wave D execution model

Final residue/resource/regression work remains serial by bounded domain:

`Web audit/freeze → local cleanup → Web exact-head audit → merge/closeout → next domain`

Wave D is not a broad cleanup authorization. Each residue is classified first. Live correctness mechanisms with historical names remain KEEP until ownership proves otherwise.

## Wave D Domain 1 execution — Remote-Only PCM Attribution

Implementation branch/worktree: `codex/task045d-domain1-remote-only-pcm-attribution-retirement` from fresh live `main@8648c3f9c3f0f12e57e54767bfd04d8b05fff3ec` (control-only CI run `41277112083`, job `124761430249`, final SUCCESS before mutation).

Implementation HEAD / Draft PR #38 head: `23328cc68a3044413b66f4218cf27a925e35e588`.

Retired surface:

- `AudioPipePCMSource` (including `.local`) — deleted; the single production `.remote` write dropped its discriminator;
- `remoteQueuedFrames` atomic counter and all source-conditioned increment/decrement/reset bookkeeping — deleted;
- `AudioRemoteQueueAttribution` — deleted (no production caller);
- mixed/local-source ring test and two attribution-helper tests — deleted; a new test pins remote-depth fields equal to total depth at write/read/overflow boundaries.

Retained: result/diagnostic field names (`remoteQueueDepth*Frames`, `remoteFramesConsumed`, `pendingRemoteFrames`) now derive from the authoritative total queue depth, observably equal to prior remote-only production values. Ring capacity/FIFO/full-empty/wraparound/reset/SPSC gate, reserve, render, tail/drain, realtime callback contract, LONG-only/suppression/tombstone, BLE/ATVV, Domain 6 input lease, diagnostics gate and recording are unchanged (no voice/transport semantic mutation; ring algorithm and capacity unchanged).

Verification evidence:

- focused suites (AudioPipeRealtime, AudioPipe, AudioDataPlaneMeasurementBoundary, AudioDataPlaneDiagnostics, AudioPipePlayoutReserve, RemoteVoiceInputLease, VoicePipelineSimplification, VoicePressCoordinator, VoiceKeyFilter, BLEBridge, VoiceReceiverReadiness, DiagnosticsRuntimeGate, DiagnosticHardening): 248/248 green;
- full `swift test`: 507/507 green;
- `swift build -c release`: PASS;
- `git diff --check`: clean;
- local Universal2 build-only packaging smoke: PASS (`x86_64 arm64`);
- durable RemoteOrbit CI on `remoteorbit-macmini` at exact PR head: run `41279444041`, job `124768161983`, SUCCESS.

Domain 6 worktree retired after clean + merged-ancestry confirmation; branch `codex/task045b-domain6-local-microphone-capture-retirement` and history preserved. No app install, driver/CoreAudio/TCC/default-device mutation, tag/release, or machine-owned hardware acceptance was performed. PR #38 remains Draft and unmerged.

## Wave D Domain 1 audit — Remote-Only PCM Attribution

Design authority: `docs/design/2026-11-01-045d-domain-1-remote-only-pcm-attribution-retirement.md`.

Verified facts:

- After Domain 6, RemoteOrbit production has exactly one PCM producer for the output ring: remote ATVV audio. `AudioPipe.schedule(...)` writes the ring with `.remote`; no production `.local` write remains.
- `FixedCapacityPCMFrameRing` still carries the historical `AudioPipePCMSource.local` model and a second atomic `remoteQueuedFrames` counter in addition to total read/write indices.
- In production, remote queue depth is therefore equal to total queue depth. The extra source discriminator/counter is no longer carrying product information.
- `AudioRemoteQueueAttribution` remains defined in diagnostics source but has no production caller; mixed/local attribution assertions remain test-only historical residue.
- Existing diagnostic field names such as remote queue depth and pending remote frames are still useful external evidence and must preserve their observable values.
- Ring capacity, FIFO ordering, SPSC reset/read gates, playout reserve, realtime callback rules, output drain and remote diagnostics are current behavior and are not retirement targets.
- Historical `ShortTap` / `AudioOnly` suppression names in the voice-key path are current LONG-only correctness mechanisms with live callers; they are explicitly outside this domain.

Classification:

`RETIRE NOW`:
- `AudioPipePCMSource.local` and the source discriminator if no current caller remains;
- the redundant `remoteQueuedFrames` atomic bookkeeping and source-conditioned increment/decrement logic;
- dead mixed/local queue-attribution helper logic with no production caller;
- tests that exist solely to model mixed local+remote PCM after local capture retirement.

`KEEP / PRESERVE SEMANTICS`:
- total ring depth and exact FIFO/capacity/reset behavior;
- remote diagnostic/public snapshot field names and values;
- remote overflow/drop/queue accounting;
- realtime no-lock/no-dispatch/no-allocation callback contract;
- playout reserve, render, tail drain, output-drain completion and candidate/prebuffer behavior;
- all voice LONG-only, BLE/ATVV, input-lease, diagnostics-gate and recording behavior.

`FROZEN FOR LATER WAVE D DOMAINS`:
- live historical naming in tombstone/suppression primitives;
- broader diagnostic/resource lifecycle cleanup;
- documentation/test naming cleanup unrelated to this attribution model;
- final hardware/runtime acceptance.

## Next gate

Wave D Domain 1 implementation is complete with durable CI PASS at the exact Draft PR #38 head. Next: independent Web exact-head audit of PR #38 (`FRESH_CONTEXT`), then merge/closeout under that audit's authority. No other Wave D domain, app install, driver/CoreAudio/TCC mutation, tag/release or machine-owned hardware acceptance is authorized.