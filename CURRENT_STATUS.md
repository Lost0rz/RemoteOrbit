# CURRENT_STATUS

Last updated: 2026-10-28
State: TASK 038-B CLOSEOUT — MERGE AUTHORIZED
Repository: Lost0rz/RemoteOrbit

## Repository authority

- Canonical development repository: `/Volumes/Jack-Dev/Projects/remoteorbit`.
- Canonical branch: `main`.
- Verified origin: `https://github.com/Lost0rz/remoteorbit.git`.
- Task 038-A is merged and complete.
- Task 038-B is at evidence/diagnostic closeout. Product correction is not authorized by this state.
- Task 037 human UI acceptance debt remains separate and is not rewritten by Task 038.
- `AGENTS.md` durable rules remain authoritative and require no semantic change for this closeout.

## Task 038 roadmap

- `038-A MERGED / COMPLETE`: rapid re-press admission.
- `038-B EVIDENCE COMPLETE / MERGE AUTHORIZED`: continuity observability, runtime evidence capture, multi-session analysis, and active-bucket base-rate audit are complete. The evidence narrows the problem but does not establish an exclusive root cause.
- `038-C DEFERRED`: Option-edge authority. Not started by this closeout.
- `038-D DEFERRED`: interaction latency.
- `038-E DEFERRED`: runtime telemetry/log retention.
- `038-F DEFERRED`: privacy-preserving text-output observation.

## 038-B delivered capability

PR #24 adds an opt-in diagnostic continuity chain for:

`BLE notifications -> decode -> PCM submission -> AudioPipe queue/render -> underrun`

The diagnostic path is enabled only with `REMOTE_ORBIT_CONTINUITY_EVIDENCE=1` and uses session identity plus 100 ms monotonic buckets.

The probe architecture was hardened before runtime use:

- render-side observation no longer acquires the shared `VoiceTimingLogger` lock or mutates its central dictionary while `AudioPipe.stateLock` is held;
- lifecycle begin/end no longer perform full fixed-capacity scans while holding the audio state lock;
- AUDIO_START-before-HID observations retain a stable capture identity and bind once to the later gesture/session;
- submission observation is stored in the AudioPipe-owned fixed-capacity ledger rather than the central shared logger;
- default-off behavior remains unchanged;
- no buffer size, queue target, pacing, codec, BLE timing, AUDIO_STOP, SHORT/LONG, Option, or production audio behavior was intentionally changed.

Semantic source/test delivery head: `652ea306dc4a22ee3c489b254d87becc6f9a4ed0`.
Independent Web CODE_DIFF audit passed at product/control head `6b5fde0b767933a89b8b7643dabe473e46040df8`; later branch changes through the evidence phase are control/evidence records unless explicitly documented otherwise.

## 038-B frozen runtime evidence

Runtime identity:

- `/Applications/RemoteOrbit.app`
- bundle `com.lost0rz.RemoteOrbit`
- version/build `0.2.14 (43)`
- executable SHA-256 `926d5ddf4b8796303ec07fe051b1da36cd539fc045973bb8bb24c0bea9a588fc`
- `REMOTE_ORBIT_CONTINUITY_EVIDENCE=1`

Evidence window: `2026-10-28 19:19:13.941–19:58:44.510 +0800`.

Frozen set:

- 10 usable natural LONG sessions from the same runtime;
- one historical PID-18405 session excluded;
- all usable sessions had exact timing/BLE/decode/submission/render/continuity joins;
- `render_capacity_dropped=0` for all usable sessions.

## Final evidence verdict

### Established facts

- Active-stream underrun is real: 48 active underrun buckets across 4/10 sessions.
- Startup/prestable render starvation was not observed in the frozen set.
- Tail/teardown accounts for about 89.2% of total unfilled frames and must not be mixed with active-stream continuity defects.
- Decoder rejects were `0` across all 10 usable sessions.
- Zero-sample decodes were `0` across all 10 usable sessions.
- AudioPipe overflow drops were `0` across the usable set.

### Active-bucket base-rate result

Active buckets: 391 total = 48 underrun + 343 non-underrun controls.

BLE cadence:

- gap >20 ms: underrun `19/48 = 39.58%`; control `33/343 = 9.62%`; RR `4.11`;
- gap >30 ms: underrun `7/48 = 14.58%`; control `6/343 = 1.75%`; RR `8.34`;
- enrichment peaks at lag zero; consistent earlier BLE-gap precedence was not established.

PCM/supply:

- `submitted < requested`: underrun `33/48 = 68.75%`; control `204/343 = 59.48%`; RR `1.16`;
- supply deficit is only weakly enriched and has no consistent lagged precedence;
- same-bucket `submitted >= requested` cannot establish intra-bucket arrival-before-render ordering.

### Causal classification

- `DECODER_REJECTION_CAUSAL_STATUS = DOWNGRADED`
- `OVERFLOW_CAUSAL_STATUS = DOWNGRADED`
- `BLE_CADENCE_CAUSAL_STATUS = SUPPORTED_AS_RECURRING_CONTRIBUTOR`
- `PCM_SUPPLY_TO_UNDERRUN_CAUSAL_STATUS = DOWNGRADED_FROM_SUPPORTED`
- `ACTIVE_STREAM_UNDERRUN_STATUS = FACT`
- `FINAL_TEXT_OMISSION_STATUS = UNKNOWN`
- `ROOT_CAUSE_STATUS = NARROWED_NOT_ESTABLISHED`

BLE cadence is therefore evidence-backed as a recurring contributor, but it is not established as an exclusive root cause. PCM aggregate supply alone does not explain the observed active starvation.

## Remaining unresolved problem

The project still does not have a single corrective root cause for the continuity weakness.

The principal unresolved technical boundary is finer-grained ordering inside the current 100 ms bucket:

- when exactly BLE packets arrive;
- when decoded PCM is submitted;
- instantaneous AudioPipe queue depth immediately before render demand;
- whether render starvation occurs before late same-bucket supply arrives;
- whether a separate AudioPipe queue/render scheduling effect remains after BLE cadence contribution is accounted for.

Human-visible waveform/audio quality and final text omission were not independently observed in 038-B and remain UNKNOWN. 038-F was not started.

## Phase lessons

1. Separate observability health from product health. A complete evidence chain can PASS while audio continuity remains defective.
2. Do not diagnose from session aggregates alone. Normal active buckets are required as denominators before labeling a contributor.
3. Separate startup, active-stream, tail/teardown, and idle render populations. Tail artifacts dominated total unfilled frames in this phase.
4. Same-bucket totals do not prove event ordering. A 100 ms bucket can contain an early starvation followed by later PCM supply.
5. Diagnostic instrumentation on a real-time path must itself be audited for observer effect. Shared locks/dictionaries on the render/submission path were removed before trusting runtime results.
6. Runtime identity and macOS permissions are part of evidence provenance. The Bluetooth authorization detour demonstrated that a healthy HID path does not prove CoreBluetooth readiness.
7. Root cause remains `UNKNOWN/NARROWED` until competing explanations are discriminated; evidence should not be converted into opportunistic buffer or timing changes.

## Closeout / merge authority

The user explicitly authorized:

- updating the relevant project documentation;
- recording the unresolved problem, current conclusions, and phase lessons;
- merging PR #24 after the live merge gate is rechecked.

This closeout does **not** authorize:

- AudioPipe/BLE corrective implementation;
- finer-grained probe implementation;
- additional runtime sessions;
- 038-C/D/E/F execution;
- TCC, driver, CoreAudio, or release mutation beyond the PR merge itself.

After remote merge, local task-worktree cleanup remains a separate local-host lifecycle obligation and must be verified before claiming `CLOSED_CLEAN`.
