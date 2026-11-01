# RemoteOrbit Current Task

## RO-DIAGNOSTICS-LEGACY-RETIREMENT-045 — Wave D / Domain 1 Remote-Only PCM Attribution Retirement

Status: `READY_FOR_IMPLEMENTATION_HANDOFF`
TASK_CLASS: `BOUNDED FINAL RESIDUE RETIREMENT`
Repository: `Lost0rz/RemoteOrbit`
Design authority: `docs/design/2026-11-01-045d-domain-1-remote-only-pcm-attribution-retirement.md`
Human runtime/UI acceptance: `PENDING / USER-OWNED`

## Completed prerequisite

Domain 6 is accepted and closed:

- PR #37 independent exact-head audit: PASS (`FRESH_CONTEXT`);
- final reviewed PR head: `85f521371dd2ff6dd5cc4e5c7cb45acf89c3e61a`;
- exact-head PR CI `41276388399` / job `124759311071` passed on `remoteorbit-macmini` including Full Swift 509/509, Native Release and Universal2 packaging;
- merged as `640256238941856c3eaa82a54cb6518d59792015` using exact expected head;
- post-merge main CI `41276777315` / job `124760439385` passed every durable stage including Universal2 packaging.

## Domain execution rule

Wave D remains serial:

`Web audit/freeze → local cleanup → Web exact-head audit → merge/closeout → next domain`

This Domain 1 has already been audited and designed by Web. Local execution performs freshness/identity reconciliation, implementation and verification only. Do not redo the domain audit or expand the boundary. If live repository facts materially conflict with this authority, stop with `AUTHORITY_RECONCILIATION_REQUIRED`.

Before product mutation, fetch live `main`, read `AGENTS.md`, `CURRENT_STATUS.md`, this file and the design authority, and require the durable CI attached to the live Wave D Domain 1 authority/control commit to be successful.

## Purpose

Retire the dead local/mixed-source PCM attribution model left behind after local microphone capture was removed, while keeping the AudioPipe ring and every remote realtime behavior observably equivalent.

## Authorized mutation

### `remote-orbit/Sources/RemoteOrbit/AudioPipeRealtime.swift`

Where current callers prove the ring is remote-only:

- retire `AudioPipePCMSource.local` and, if no retained need remains, the `AudioPipePCMSource` discriminator itself;
- remove the independent `remoteQueuedFrames` atomic counter and its source-conditioned publication/consumption/reset bookkeeping;
- simplify write/read result construction so remote queue depth values remain exactly equal to the corresponding total queue depth values in the remote-only product;
- keep result fields with remote-oriented names if they are still consumed by diagnostics/tests; this domain does not authorize a broad diagnostics schema rename;
- preserve ring capacity, FIFO ordering, exact-full/exact-empty semantics, wraparound, bounded indices, reader/reset gate protocol, zero-fill behavior and realtime callback constraints.

The preferred implementation is the smallest removal of redundant source attribution. Do not redesign the ring algorithm.

### `remote-orbit/Sources/RemoteOrbit/AudioPipe.swift`

Update current remote-only call sites only as needed by the ring API simplification.

Preserve:

- candidate/prebuffer behavior;
- playout reserve;
- remote activation/reset order;
- output drain;
- queue/overflow diagnostics values;
- IOProc/render behavior;
- diagnostic snapshots and external field meanings.

Any current diagnostic field representing remote queue depth or pending remote frames must report the same value it reports today for production remote-only traffic.

### `remote-orbit/Sources/RemoteOrbit/AudioDataPlaneDiagnostics.swift`

`AudioRemoteQueueAttribution` may be deleted/simplified only where direct source audit proves it has no production caller after Domain 6. Do not use this as authority to rewrite unrelated delivery, render, BLE, continuity or incident accounting.

### Tests

Remove/rewrite only tests whose sole purpose is the retired local/mixed-source model, including local-source writes or assertions that remote depth differs from total depth.

Retain or strengthen deterministic coverage for:

- FIFO and partial operations;
- exact full/empty distinction;
- wraparound;
- overflow rejection without overwrite;
- reset;
- SPSC stress/order;
- remote diagnostics counters;
- reserve wait/tail bypass;
- output drain;
- realtime callback no-lock/no-dispatch/no-dynamic-buffer contract;
- current remote queue/overflow diagnostic values.

If a mixed-source test also contains a current generic ring assertion, rehome that assertion before deleting the case.

## Explicit KEEP boundary

Do not change:

- `AudioPipe.pcmRingCapacityFrames`;
- ring read/write/reset synchronization protocol except removal of the redundant remote-source counter;
- playout reserve thresholds/state machine;
- remote gain, sample rate or resampling;
- candidate/prebuffer ownership;
- output-drain and post-release behavior;
- temporary system-input lease from Domain 6;
- Gate-A 300 ms LONG-only semantics;
- rapid repress, tombstone/suppression/handoff, hardware/synthetic ownership;
- BLE/ATVV/readiness;
- diagnostics runtime gate or independent recording;
- primary profile/mapping authority;
- external durable diagnostic schema/field names unless a compile-only adaptation is unavoidable.

Historical names are not retirement proof. In particular, current `beginShortTapDiscard`, `isShortTapDiscardSession`, and `transferShortTapDiscardToAudioOnlySuppression` ownership remain outside this domain because they are live LONG-only correctness mechanisms.

## Explicit non-goals

Do not:

- start another Wave D residue domain;
- broadly refactor AudioPipe/diagnostics architecture;
- rename live tombstone/suppression primitives for cosmetics;
- change diagnostics gating or timer policy;
- change 300 ms behavior;
- change BLE/ATVV, codec, gain, sample rate or prebuffer;
- change input-device lease behavior;
- install/replace the app;
- mutate live driver/CoreAudio/TCC/default audio devices;
- tag/release;
- merge the implementation PR locally.

## Verification required

Focused evidence must prove at minimum:

1. no production PCM source discriminator/local source remains if the enum is retired;
2. no redundant remote queue atomic counter remains;
3. production remote queue depth/pending-remote values equal total queued frames without semantic change;
4. FIFO/full-empty/wraparound/reset/stress behavior remains green;
5. realtime render callback remains free of ordinary locks, dispatch and dynamic sample buffers;
6. remote overflow/drop accounting remains equivalent;
7. reserve, render, tail and output-drain behavior remains green;
8. Domain 6 input-lease tests remain green;
9. LONG-only, rapid repress, tombstone/suppression, BLE/readiness, diagnostics-gate and recording regressions remain green;
10. no live `ShortTap`/`AudioOnly` correctness primitive was removed merely by name.

At minimum run focused suites covering:

- `AudioPipeRealtimeTests`
- `AudioPipeTests`
- `AudioDataPlaneMeasurementBoundaryTests`
- `AudioDataPlaneDiagnosticsTests`
- `AudioPipePlayoutReserveTests`
- `RemoteVoiceInputLeaseTests`
- `VoicePipelineSimplificationTests`
- `VoicePressCoordinatorTests`
- `VoiceKeyFilterTests`
- relevant BLE / diagnostics / readiness tests

Then run:

- full `swift test`;
- `swift build -c release`;
- `git diff --check`;
- durable `.github/workflows/remoteorbit-ci.yml` on `remoteorbit-macmini`;
- Universal2 build-only packaging smoke.

## Workspace / delivery

Start from fresh live `main` after reconciliation. Use one fresh worktree/branch, suggested:

`codex/task045d-domain1-remote-only-pcm-attribution-retirement`

The merged Domain 6 worktree may be retired only after confirming clean state and merged ancestry. Preserve its branch/history unless separately authorized.

Create one Draft PR. Do not merge locally.

After implementation/test/CI evidence is available, atomically update `CURRENT_STATUS.md` and `CURRENT_TASK.md` in one final handoff commit. Do not encode that control commit's own future SHA; resolve final PR head and post-push CI from GitHub at independent audit time.

## Stop

After implementation, verification, push, Draft PR, durable CI and atomic control handoff, stop at:

`WAITING_FOR_INDEPENDENT_WEB_AUDIT`

Do not start another Wave D domain, install the app, mutate driver/CoreAudio/TCC/default devices, tag/release or merge locally.

Return actual governance route/capability, topology/subagents, fresh start main, authority/control CI pre-mutation result, branch/worktree, implementation/final heads, remote equality, Draft PR, changed/deleted paths, retired attribution surface, retained diagnostic field semantics, focused/full/build/diff/CI/package results, Domain 6 worktree disposition, scope-mutation flags, unresolved uncertainty, `HUMAN_UI_ACCEPTANCE`, merge state and final actual state.