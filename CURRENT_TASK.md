# RemoteOrbit Current Task

## RO-RUNTIME-RELIABILITY-038 — Task 038

- Status: BLE_START_INCIDENT_DIAGNOSIS — 038-B.
- Task class: RUNTIME RELIABILITY / DIAGNOSTIC EVIDENCE.
- Repository: `Lost0rz/RemoteOrbit`.
- Canonical repository: `/Volumes/Jack-Dev/Projects/remoteorbit`.
- Control baseline: `main` after PR #23 merge commit `79f3db92024e8a901d3a0fcec2c1f194c7136753` and the paired 038-B activation transition.
- 038-A is merged and closed to further product mutation unless a new regression specifically reopens it.
- Task 037 human acceptance debt remains pending and is not rewritten by Task 038.

## Roadmap state

- `038-A MERGED / COMPLETE`: rapid re-press admission.
- `038-B BLE_START_INCIDENT_DIAGNOSIS`: the first healthy-permission session reached `INPUT/GESTURE + REMOTE_ROUTE_BEGIN` but stopped before confirmed BLE audio start; existing evidence must determine whether `micOpen` was transmitted.
- `038-C DEFERRED`: Option-edge authority.
- `038-D DEFERRED`: interaction latency.
- `038-E DEFERRED`: runtime telemetry/log retention.
- `038-F DEFERRED`: privacy-preserving text-output observation.

## Objective

Determine, with session-level evidence, whether the observed voice continuity weakness is caused by BLE notification cadence, decoded PCM supply, AudioPipe queue/render behavior, or an interaction between those layers.

The evidence chain under study is:

`BLE notifications -> decode -> PCM submission -> AudioPipe queue -> render/underrun`

Historical logs indicate decoder rejects and overflow drops were zero while delivery deficit and underrun recurred. Treat that as task input, not a predeclared root-cause verdict.

## Authorized lifecycle closeout before 038-B writing

The previous 038-A implementation worktree may be retired locally before creating the 038-B writer. This is explicitly authorized only when the local executor proves:

- the worktree/branch identity is the merged 038-A lineage;
- the worktree is clean;
- all commits are reachable from current `main` or otherwise intentionally retained;
- there is no unique or unpushed work.

If those checks pass, remove the old local 038-A worktree and prune its registration. A local 038-A branch may also be removed if fully merged and non-unique. Remote branch deletion is not required by this transition. If the path is already absent, classify that as reconciliation rather than claiming a deletion.

## 038-B authorized writer identity

- Branch: `codex/runtime-reliability-038-b-continuity-evidence`.
- Worktree: `/private/tmp/remoteorbit-runtime-reliability-038-b-continuity-evidence`.
- Start HEAD: `e80c8be50fa489c7f04c4ca5567aff7cc5d3af9b`.
- Registration: this paired control commit; the worktree was clean before source/test or diagnostic mutation.
- The old 038-A worktree closeout was performed after proving clean state, merged reachability, and no unique/unpushed commits; its local branch was deleted and remote branch retained.
- Current source/test HEAD: `652ea306dc4a22ee3c489b254d87becc6f9a4ed0`, pushed and verified equal to the remote 038-B branch before this paired closeout control update.
- PR #24: OPEN + DRAFT + UNMERGED; its live head is the current tip of the authorized branch and was remote-verified for this transition. Current GitHub metadata reports `mergeable=true`; this is only a repository fact and merge remains prohibited. The independent Web CODE_DIFF audit passed at the audited product head `6b5fde0b767933a89b8b7643dabe473e46040df8`; later commits are paired control-only runtime transition/result records. Corrective-1 reproduced and removed render-path probe self-contention; corrective-2 bounded lifecycle work; corrective-3 closed the AUDIO_START-before-HID correlation gap; corrective-4 removed submission-path probe contention.
- Corrective-2 delivery source/test HEAD: `ebd6f1daa6a15f4790ec0faa342dc80a1a0c518a`; corrective-3 delivery source/test HEAD: `7d33e01cf94aa3685ccfdecc6df28207258cb1bb`, both verified as ancestors of the current branch.

## Authorized 038-B scope

1. Reconcile fresh `main`, open PRs/worktrees, and existing diagnostic authorities before mutation.
2. Perform the authorized 038-A local workspace closeout above before creating the new writer.
3. Create one 038-B branch/worktree from the activation control head and register it before any source/test change.
4. Inventory existing continuity telemetry and tests before adding probes.
5. Build a per-session correlation model using existing fields where possible, including:
   - notification count and gap distribution (`max`, `p95`, `>20/30/50/100ms`);
   - decoded frame/sample counts;
   - expected samples, deficit samples/ms, delivery ratio;
   - stream lifecycle and AUDIO_STOP/drain timing;
   - AudioPipe render requested/filled/unfilled frames;
   - underrun callbacks/duration/max underrun;
   - queue depth min/current/max;
   - overflow/drop counters;
   - active-stream versus tail/boundary classification.
6. Compare representative normal, weak, short, and long sessions rather than relying on one aggregate statistic.
7. Determine whether current telemetry can directly align a BLE supply gap with the corresponding PCM/AudioPipe starvation interval.
8. If the evidence chain is incomplete, add only the smallest observation instrumentation required to correlate those layers by session/time. This was completed as an opt-in 100 ms bucket ledger using the existing P1A4 monotonic clock and VoiceTimingLogger session identity; it must remain diagnostic-only and must not change production behavior.
9. Add focused tests for any new accounting/probe logic.
10. Run proportional verification: focused tests, full Swift tests when source changes, release build for source changes, and diff check.
11. Return to `WAITING_FOR_INDEPENDENT_WEB_AUDIT` if source/test instrumentation changes are delivered. This slice delivered source/test instrumentation in `0c26c61` and corrective-2 in `ebd6f1d`; PR #24 is now at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`. If no later authority transition exists, do not install/release/runtime-capture.
12. Corrective-1 completed: the audit property was reproduced, and the smallest architecture change was made so continuity capture inside CoreAudio IOProc uses no shared logger lock, cross-thread blocking synchronization, dictionary/hash mutation, string formatting/printing, synchronous dispatch, or unbounded allocation. The existing clock, session identity, 100 ms buckets, fields, active/tail/idle accounting, and default-off behavior were preserved.
13. Corrective-2 completed in `ebd6f1d`: the fixed-capacity render-side evidence model is preserved while disabled begin/end are cheap, lock-held begin/end are bounded, and snapshot creation is safely detached from render writes. The clock, session identity, 100 ms buckets, BLE/decode/submission correlation, active/tail/idle accounting, overflow evidence, `render_capacity_dropped`, and default-off behavior are preserved.
14. Corrective-3 authorized in the current execution card: add a deterministic RED regression for AUDIO_START before HID/session creation, then close only the late session-correlation gap. Preserve pre-session observations, reject stale/wrong-session binding, preserve session isolation, and keep corrective-1/2 render and lifecycle invariants unchanged. Stop if this requires a material AudioPipe redesign or changes product voice semantics.
15. Corrective-3 delivered in `7d33e01`: AUDIO_START owns a stable capture identity when the gesture UUID is absent; pre-session observations are retained and bound once to the later HID session. The HID-before-AUDIO_START path remains bound to the same capture identity, while wrong/repeated capture bindings are rejected. No voice semantics, rapid re-press behavior, audio scheduling, queue targets, BLE timing, or AUDIO_STOP interpretation changed.
16. Corrective-4 is authorized in the current execution card: reproduce the remaining `AudioPipe.stateLock -> VoiceTimingLogger.recordContinuitySubmitted -> shared diagnostic lock/dictionary` edge, then move only submission observation into the existing AudioPipe-owned fixed-capacity ledger. Preserve monotonic timestamp, submitted frames, queue depth, 100 ms bucket alignment, capture identity, provisional AUDIO_START-before-HID support, and exact one-time submission-plus-render merge after detach. Preserve corrective-1/2/3 invariants and stop for any production audio redesign, unsafe association, or authority drift.
17. Corrective-4 verification must cover submission bucket/queue evidence, provisional and bound ordering, wrong/stale isolation, same-session submission-plus-render merge, disabled mode, consecutive sessions, focused diagnostics, affected AudioPipe/order/lifecycle tests, full Swift tests, release build, and diff check. After delivery, return to `WAITING_FOR_INDEPENDENT_WEB_AUDIT`; do not install, release, merge, or capture runtime.
18. Corrective-4 delivered in `652ea30`: `AudioPipe.schedule()` records submission evidence in the AudioPipe-owned fixed-capacity ledger, central merge includes submitted frames and queue depth, and `VoiceTimingLogger.recordContinuitySubmitted()` plus its shared-lock/dictionary path were removed. No voice semantics, audio scheduling, queue targets, BLE timing, or AUDIO_STOP interpretation changed.

19. The resume card authorizes only fresh-process permission verification and first-session probe, then natural session capture if probe health passes. The installed identity must remain `com.lost0rz.RemoteOrbit 0.2.14 (43)` with executable SHA-256 `926d5ddf4b8796303ec07fe051b1da36cd539fc045973bb8bb24c0bea9a588fc`; launch only with `REMOTE_ORBIT_CONTINUITY_EVIDENCE=1`. Do not change TCC, merge, release, tune audio, restart CoreAudio, change the driver, add text observation, or begin 038-C/D/E/F.

## Required output / evidence

The 038-B result must include:

- exact source/runtime/log identities used;
- number and duration of sessions analyzed;
- per-session continuity metrics;
- normal-versus-weak comparison;
- whether decoder rejection is supported or downgraded as a cause;
- whether AudioPipe overflow is supported or downgraded as a cause;
- whether BLE cadence deficit temporally precedes or coincides with AudioPipe underrun;
- whether underrun occurs predominantly during active speech supply or only at startup/tail boundaries;
- FACT / INFERENCE / UNKNOWN classification for each causal step;
- the smallest next action justified by evidence.

## Non-goals / prohibited mutation

- No AudioPipe buffer-size, target-depth, scheduling, pacing, resampling, or playback tuning.
- No Adaptive Playout production changes.
- No BLE codec, notification, packet timing, keep-alive, micOpen/micClose, or AUDIO_STOP semantic changes.
- No SHORT/LONG or rapid re-press behavior changes.
- No Option/noOptionEdge fix.
- No text-output Accessibility observer.
- No DiagnosticAuthority redesign or log-retention cleanup.
- No mapping/config backup cleanup.
- No package/install/release/driver/TCC mutation except the explicitly authorized diagnostic app build/install/run already performed in the current runtime-capture card; driver, TCC, LaunchAgent, CoreAudio, and release mutations remain prohibited.
- No opportunistic refactor.

## Stop conditions

- Stop for material authority drift, unexpected active writer/PR, unique unpushed work, or scope conflict.
- If existing telemetry cannot establish time correlation and instrumentation would materially affect the audio path, stop instead of adding an intrusive probe.
- If evidence points to a different layer outside 038-B, report it and stop; do not silently expand into 038-C/D/E/F.
- If a corrective production change becomes justified, stop after the evidence verdict and request a new governance transition before implementing it.
- Corrective-1 stop condition: if safe render observation requires a material AudioPipe redesign or cannot be made non-perturbing within this boundary, revert only the intrusive render-side portion and stop.

## Corrective-1 delivery receipt

- Audit finding: FACT — the previous render-side continuity probe called the shared logger while `AudioPipe.stateLock` was held; that logger acquired a global `NSLock` and mutated a dictionary.
- Architecture: FACT — `AudioContinuityRenderLedger` is AudioPipe-owned, fixed-capacity, preallocated storage; render-side observation only samples the existing monotonic clock, computes a bounded bucket index, and updates fixed counters. Lifecycle snapshot creation and central dictionary merge are outside render.
- Lifecycle/default-off coverage: FACT — focused tests cover active render, tail/overflow, stale timestamp/session reset, consecutive sessions, bounded capacity, disabled context, and snapshot merge.
- Product/runtime boundary: UNKNOWN — no installed/runtime capture was performed, so this commit does not establish runtime underrun behavior or a product audio root cause.

## Corrective-2 scope receipt

- Remaining audit basis: FACT — `beginRemoteAudioDiagnostics()` resets all 8,192 buckets under `stateLock` even when continuity is disabled; `endRemoteAudioDiagnostics()` snapshots/filters and resets the full ledger under the same lock.
- Required result: FACT — delivered in `ebd6f1d`; disabled begin/end avoid capacity-proportional work, enabled begin/end keep lock-held work bounded, and snapshot detachment cannot race render writes.
- Stop boundary: if safe detachment requires a material AudioPipe redesign or new synchronization risk, revert only the intrusive corrective-2 portion and stop.

## Corrective-2 delivery receipt

- Lifecycle ordering: FACT — enabled ledger construction occurs before `stateLock`; end detaches the live ledger and disables capture under `stateLock`, then snapshots the detached ledger after unlock.
- Default-off invariant: FACT — `AudioPipe` keeps no continuity ledger when the context is nil; begin/end perform no fixed-capacity reset or snapshot scan.
- Snapshot race safety: FACT — render writes require the attached ledger and existing `stateLock`; once detached under that lock, render can only observe nil/disabled state, so the detached ledger is stable for snapshot creation.
- Verification: FACT — focused diagnostics 28/28, AudioPipe 4/4, full Swift 417/417, release build PASS, diff check PASS.
- Product/runtime boundary: UNKNOWN — no installed/runtime capture was performed, so this does not establish runtime underrun behavior or an audio root cause.

## Current next action

Inspect existing evidence for incident session `AD04FCCB-020E-4071-BD90-B24EFB4B2ACE` and determine whether the failure occurred before `micOpen` transmission or after `micOpen` transmission without `AUDIO_START`. Do not create another runtime incident, request another user voice session, mutate product behavior, or change TCC, driver, CoreAudio, or PR lifecycle.

## 038-B BLE-start incident diagnosis transition

- Transition authority: FACT — the current BLE-start incident card explicitly authorizes this control-only transition and bounded existing-evidence diagnosis.
- Incident session: `AD04FCCB-020E-4071-BD90-B24EFB4B2ACE`.
- Incident interval: `2026-10-28 15:45:41.216 +0800` through `2026-10-28 15:45:44.685 +0800`.
- `LAST_CONFIRMED_GOOD_STAGE`: `INPUT/GESTURE + REMOTE_ROUTE_BEGIN`.
- `FIRST_FAILED_OR_UNCONFIRMED_STAGE`: `BLE AUDIO START / FIRST REMOTE AUDIO PACKET`.
- Root cause: UNKNOWN.
- No second user session is authorized in this pass.
- No product fix is authorized in this pass.

## Runtime-capture result receipt

- `TOTAL_VOICE_SESSIONS=0`; `USABLE_SESSION_COUNT=0`; `EXCLUDED_SESSION_COUNT=0` because no session was emitted.
- `PROBE_HEALTH=FAIL/INCOMPLETE`: no `CONTINUITY_SESSION`, `CONTINUITY_BUCKET`, matching session identity, or `render_capacity_dropped` record was observed; app log reports `input=false accessibility=false`.
- `SESSION_JOIN_INTEGRITY=UNKNOWN`; `RENDER_CAPACITY_DROP_STATUS=UNKNOWN`; no per-session metrics or comparisons are available.
- `RUNTIME_BUILD_IDENTITY=FACT`: `com.lost0rz.RemoteOrbit` `0.2.14 (43)`, universal arm64+x86_64, installed `/Applications/RemoteOrbit.app`, executable SHA-256 `926d5ddf4b8796303ec07fe051b1da36cd539fc045973bb8bb24c0bea9a588fc`.
- `CAPTURE_ENVIRONMENT=FACT`: only `REMOTE_ORBIT_CONTINUITY_EVIDENCE=1`; log identity is `/Users/ox_miles/Library/Logs/RemoteOrbit/RemoteOrbit.log` plus `voice-diagnostic-current.jsonl`; local PTY capture is `/private/tmp/remoteorbit-038-b-runtime-capture.wWfAWx/diagnostic.tty.log`.
- `ROOT_CAUSE_STATUS=UNKNOWN`: decoder rejection, overflow, BLE cadence, PCM supply, active underrun, and final-text omission remain unclassified. The smallest justified next action is user-owned permission authorization followed by natural voice sessions, with at least one healthy probe session before the preferred ten-session set.

## Corrective-4 delivery receipt

- Audit finding reproduced: FACT — `AudioPipe.schedule()` held `stateLock` across `VoiceTimingLogger.recordContinuitySubmitted()`, which acquired shared diagnostic locking and mutated the central dictionary.
- Architecture delivered: FACT — the same timestamp, submitted frames, queue depth, 100 ms alignment, capture identity, provisional late-binding origin, and session association now use the existing AudioPipe-owned fixed-capacity ledger; detached snapshot merge carries submission and render evidence once.
- State-lock audit: FACT — AudioPipe continuity calls under `stateLock` are now only `continuityRenderLedger?.recordSubmitted`, `recordRender`, and `recordOverflow`; none acquires the VoiceTimingLogger lock, mutates a shared dictionary/hash, formats/prints, dispatches synchronously, or performs unbounded aggregation.
- Verification: FACT — focused diagnostics 32/32, AudioPipe 4/4, VoiceBoundaryOrdering 3/3, VoicePressCoordinator 39/39, full Swift 421/421, release build PASS, and diff check PASS.
- Product/runtime boundary: UNKNOWN — no installed/runtime capture was performed, so this delivery does not establish runtime underrun behavior or an audio root cause.

## Corrective-3 delivery receipt

- Audit finding reproduced: FACT — when AUDIO_START arrived before HID, `currentContinuityContext()` was nil, AudioPipe created no render ledger, and later HID session creation had no binding path.
- Correlation architecture: FACT — opt-in AUDIO_START creates a stable `captureID`; the AudioPipe render ledger stores the capture start and can bind exactly once to the later gesture UUID. HID-before-AUDIO_START creates the same bound capture through the existing logger session.
- Pre-session evidence: FACT — BLE/decode records are accepted while the provisional capture awaits its session, and pre-session render buckets remain in fixed storage until late binding; the bucket origin stays the AUDIO_START monotonic timestamp so the snapshot joins the central ledger.
- Stale/wrong-session protection: FACT — AudioPipe binding requires the exact captureID and an unbound active ledger; wrong and repeated bindings are rejected, and captureID is checked again during snapshot merge.
- Render/lifecycle preservation: FACT — render remains AudioPipe-owned fixed-capacity mutation only; late binding is bounded metadata under `stateLock`; construction remains outside the lock; snapshot remains after safe detach; default-off keeps the ledger nil.
- Product/runtime boundary: UNKNOWN — no installed/runtime capture was performed, so no runtime underrun or audio root-cause claim is made.
