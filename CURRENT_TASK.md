# RemoteOrbit Current Task

## RO-RUNTIME-RELIABILITY-038 — Task 038

- Status: ACTIVE — 038-B AUDIO CONTINUITY EVIDENCE.
- Task class: RUNTIME RELIABILITY / DIAGNOSTIC EVIDENCE.
- Repository: `Lost0rz/RemoteOrbit`.
- Canonical repository: `/Volumes/Jack-Dev/Projects/remoteorbit`.
- Control baseline: `main` after PR #23 merge commit `79f3db92024e8a901d3a0fcec2c1f194c7136753`.
- 038-A is merged and closed to further product mutation unless a new regression specifically reopens it.
- Task 037 human acceptance debt remains pending and is not rewritten by Task 038.

## Roadmap state

- `038-A MERGED / COMPLETE`: rapid re-press admission.
- `038-B ACTIVE`: audio continuity evidence — only active slice.
- `038-C DEFERRED`: Option-edge authority.
- `038-D DEFERRED`: interaction latency.
- `038-E DEFERRED`: runtime telemetry/log retention.
- `038-F DEFERRED`: privacy-preserving text-output observation.

## Objective

Determine, with session-level evidence, whether the observed voice continuity weakness is caused by BLE notification cadence, decoded PCM supply, AudioPipe queue/render behavior, or an interaction between those layers.

The evidence chain under study is:

`BLE notifications -> decode -> PCM submission -> AudioPipe queue -> render/underrun`

Historical logs indicate decoder rejects and overflow drops were zero while delivery deficit and underrun recurred. Treat that as task input, not a predeclared root-cause verdict.

## Authorized 038-B scope

1. Reconcile fresh `main`, open PRs/worktrees, and existing diagnostic authorities before mutation.
2. Create one 038-B branch/worktree from the activation control head and register it before any source/test change.
3. Inventory existing continuity telemetry and tests before adding probes.
4. Build a per-session correlation model using existing fields where possible, including:
   - notification count and gap distribution (`max`, `p95`, `>20/30/50/100ms`);
   - decoded frame/sample counts;
   - expected samples, deficit samples/ms, delivery ratio;
   - stream lifecycle and AUDIO_STOP/drain timing;
   - AudioPipe render requested/filled/unfilled frames;
   - underrun callbacks/duration/max underrun;
   - queue depth min/current/max;
   - overflow/drop counters;
   - active-stream versus tail/boundary classification.
5. Compare representative normal, weak, short, and long sessions rather than relying on one aggregate statistic.
6. Determine whether current telemetry can directly align a BLE supply gap with the corresponding PCM/AudioPipe starvation interval.
7. If the evidence chain is incomplete, add only the smallest observation instrumentation required to correlate those layers by session/time. Instrumentation must be diagnostic-only and must not change production behavior.
8. Add focused tests for any new accounting/probe logic.
9. Run proportional verification: focused tests, full Swift tests when source changes, release build for source changes, and diff check.
10. Return to `WAITING_FOR_INDEPENDENT_WEB_AUDIT` if source/test instrumentation changes are delivered. If no source change is required, return a read-only evidence report with explicit classifications and next-governance recommendation.

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

## Current next action

Create/register the 038-B diagnostic worktree from the current control head, then perform the continuity telemetry inventory and correlation audit. Do not tune or fix audio behavior in this phase.
