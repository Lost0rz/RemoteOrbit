# RemoteOrbit Current Task

## RO-RUNTIME-RELIABILITY-038 — Task 038

- Status: WAITING_FOR_INDEPENDENT_WEB_AUDIT — 038-B corrective-1 delivered.
- Task class: RUNTIME RELIABILITY / DIAGNOSTIC EVIDENCE.
- Repository: `Lost0rz/RemoteOrbit`.
- Canonical repository: `/Volumes/Jack-Dev/Projects/remoteorbit`.
- Control baseline: `main` after PR #23 merge commit `79f3db92024e8a901d3a0fcec2c1f194c7136753` and the paired 038-B activation transition.
- 038-A is merged and closed to further product mutation unless a new regression specifically reopens it.
- Task 037 human acceptance debt remains pending and is not rewritten by Task 038.

## Roadmap state

- `038-A MERGED / COMPLETE`: rapid re-press admission.
- `038-B WAITING_FOR_INDEPENDENT_WEB_AUDIT`: audio continuity evidence and corrective-1 probe architecture delivered; no runtime capture is authorized.
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
- Current source/test HEAD: `0c26c61c2a2ec1f147f6179b20a864f335af1dfb`, pushed and verified equal to the remote 038-B branch.
- PR #24: OPEN + DRAFT + UNMERGED; its live head is the current tip of this authorized branch and must be read directly for any future transition. The last revalidated tip before this control correction is `229fec6680cdd09a90c1a7134403cb9bd6620fce`; corrective-1 reproduced and removed render-path probe self-contention, then returned the task to independent Web audit.

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
11. Return to `WAITING_FOR_INDEPENDENT_WEB_AUDIT` if source/test instrumentation changes are delivered. This slice delivered source/test instrumentation and corrective-1 in `0c26c61`; PR #24 is now at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`. If no later authority transition exists, do not install/release/runtime-capture.
12. Corrective-1 completed: the audit property was reproduced, and the smallest architecture change was made so continuity capture inside CoreAudio IOProc uses no shared logger lock, cross-thread blocking synchronization, dictionary/hash mutation, string formatting/printing, synchronous dispatch, or unbounded allocation. The existing clock, session identity, 100 ms buckets, fields, active/tail/idle accounting, and default-off behavior were preserved.

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
- No package/install/release/driver/TCC mutation unless a later control transition explicitly authorizes a runtime-capture step.
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

## Current next action

Independent Web audit of PR #24. Do not tune, install, release, capture runtime, or fix audio behavior.
