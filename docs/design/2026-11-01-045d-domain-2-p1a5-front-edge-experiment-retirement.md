# Task 045D Wave D Domain 2 — P1-A5 Front-Edge Experiment Diagnostics Retirement

Date: 2026-11-01
Status: FROZEN FOR IMPLEMENTATION HANDOFF
Task: `RO-DIAGNOSTICS-LEGACY-RETIREMENT-045`
Domain: `WAVE_D_DOMAIN_2 / P1A5_FRONT_EDGE_EXPERIMENT_DIAGNOSTICS`

## 1. Objective

Retire the old P1-A5 front-edge experiment diagnostic layer after current structured long-term observability has become the durable diagnostic authority, without changing voice/audio product behavior or weakening current observability.

This is a diagnostics-residue retirement domain, not a voice-pipeline redesign.

## 2. Verified architecture

### 2.1 P1-A5 is an explicit experiment layer

`P1A5FrontEdgeDiagnostics.swift` defines a fixed RMS-based voice-onset detector and four fixed underrun-distance buckets. Its source comments explicitly describe the rule as fixed for the P1-A5 experiment and observation-only.

The experiment is enabled only when both:

- the unified diagnostics runtime gate is enabled; and
- `REMOTE_ORBIT_P1A5_FRONT_EDGE=1`.

### 2.2 Current diagnostic authority is independent

`VoiceTimingLogger.end(...)` completes the current generic session work before the P1-A5 report:

- generic T0–T10 timing snapshot;
- continuity evidence reporting when separately enabled;
- `LongTermObservabilityService.end(...)`;
- `VoiceAttemptDiagnostics.end(...)`.

Only after those paths complete does it guard on `p1A5Enabled` and print the experiment-only F0–F9/front-edge bucket report.

Therefore removing P1-A5 does not remove the current structured long-term diagnostic authority.

### 2.3 P1-A5 still creates isolated runtime work

Current residual ownership includes:

- BLEBridge `P1A5VoiceOnsetDetector` state/reset/analyze;
- `VoiceTimingLogger` P1-A5 flag, onset/bucket state and F-series report;
- AudioPipe P1-A5-only F-series marker publication;
- AudioPipe realtime `frontEdgeUnderrun` observation publication and off-path consumption.

### 2.4 `frontEdgeUnderrun` duplicates a retained active-underrun fact

For an active underrun, `AudioPipeRealtimeDiagnostics.recordRender(...)` currently publishes:

1. a normal render observation;
2. a `queueStarvation` observation when active underrun or tail-empty occurs;
3. a second `frontEdgeUnderrun` observation when the active-underrun count is positive.

The current long-term material-anomaly path consumes `queueStarvation`; P1-A5 consumes only the duplicate `frontEdgeUnderrun` to bucket underrun time relative to its experimental voiced-onset detector.

After P1-A5 retirement, `frontEdgeUnderrun` carries no independent current product/diagnostic meaning and should be removed while `queueStarvation` remains unchanged.

## 3. Selected design

Delete the P1-A5 experiment as one bounded vertical slice.

### Retire

- `P1A5FrontEdgeDiagnostics.swift` and its dedicated tests;
- `VoiceTimingLogger.p1A5Enabled`;
- P1-A5 onset/front-edge bucket state;
- experiment-only F0–F9 marker/report lifecycle;
- BLEBridge P1-A5 detector state/reset/analyze work;
- AudioPipe P1-A5 F-series marker branches;
- realtime `frontEdgeUnderrun` observation kind/enqueue/consumer path;
- executable/current documentation for the P1-A5 environment override, if present.

### Keep

- unified `DiagnosticsRuntimeGate`;
- generic `VoiceTimingLogger` T0–T10 lifecycle correlation;
- `P1A4MonotonicClock` as current shared timing infrastructure;
- continuity evidence and `REMOTE_ORBIT_CONTINUITY_EVIDENCE`;
- `LongTermObservabilityService`, incident coordinator and fixed traces;
- `queueStarvation`, render-starvation and main-queue-lag evidence;
- AudioPipe realtime counters and observation mailbox architecture;
- all voice/audio correctness behavior.

## 4. Why P1-A4 is not part of this retirement

The `P1A4MonotonicClock` name is historical, but its implementation is now generic shared infrastructure used across current reserve, timing, diagnostic and long-term-observability paths.

Likewise, the generic T0–T10 timing line remains useful correlation evidence and is not dependent on the P1-A5 voice-onset experiment.

Historical naming alone does not authorize deletion or renaming.

## 5. Why continuity is not part of this retirement

`REMOTE_ORBIT_CONTINUITY_EVIDENCE` and the continuity ledger have separate capture identity, BLE/decode/render correlation and current test coverage. Their ownership is independent from the P1-A5 voiced-onset detector and front-edge buckets.

Any later continuity/resource simplification requires a separate Wave D audit.

## 6. Behavioral invariants

This domain must not change:

- SHORT `<300 ms` absolute user-visible no-op;
- LONG `>=300 ms` direct remote voice lifecycle;
- candidate/pre-HID behavior;
- rapid repress;
- SHORT tombstone and late mapped-edge suppression/handoff;
- hardware Option ownership / held-UP acknowledgement;
- synthetic fallback;
- BLE READY/reuse and ATVV protocol;
- codec/gain/sample rate;
- remote prebuffer, playout reserve, IOProc/render and output drain;
- Domain 6 temporary system-input lease;
- selected profile/mapping/persistence compatibility;
- diagnostics gate or recording independence.

## 7. Realtime boundary

Removing `frontEdgeUnderrun` is a duplicate-observation retirement only.

Do not modify:

- active-underrun accounting values;
- queue-starvation conditions;
- tail-empty accounting;
- realtime observation capacity or ring/mailbox synchronization;
- ordinary realtime no-lock/no-dispatch/no-dynamic-buffer requirements.

The expected performance effect is only removal of one duplicate observation enqueue/consumer path during active underrun.

## 8. Test boundary

The dedicated P1-A5 tests may be deleted because they test only the fixed experiment detector/buckets.

Current generic diagnostic tests must remain. In particular retain/verify:

- LongTermObservability transport-to-render correlation;
- queue/render starvation anomaly evidence;
- diagnostics gate OFF behavior;
- continuity evidence where enabled;
- AudioPipe reserve/drain/current diagnostics;
- BLE decode/transport metrics;
- direct LONG-only ownership and rapid repress;
- input lease and recording independence.

If a retained test mentions an F-series marker but also protects current generic behavior, migrate only the generic assertion before removing the experiment marker.

## 9. Documentation boundary

Historical incident, old design and experimental evidence documents are records and are not deleted in this domain.

Only current executable instructions that tell operators to enable `REMOTE_ORBIT_P1A5_FRONT_EDGE` may be removed or marked retired.

Broad README/SETUP wording cleanup is a separate residue domain because those documents also contain unrelated historical product text.

## 10. Verification

Required evidence is defined in `CURRENT_TASK.md`. The implementation must include focused tests, full Swift tests, Release build, `git diff --check`, durable self-hosted CI and Universal2 build-only packaging.

No test may mutate live CoreAudio, default devices, TCC, app installation or driver installation.

## 11. Stop boundary

Local execution stops at `WAITING_FOR_INDEPENDENT_WEB_AUDIT` with a Draft PR and final-head CI evidence.

No merge and no Wave D Domain 3 work is authorized locally.

## 12. Design result

Selected option: **retire P1-A5 only; preserve current generic diagnostics and observability unchanged.**

`TASK_RECONCILIATION_REQUIRED: NO`.