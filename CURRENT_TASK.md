# RemoteOrbit Current Task

## RO-DIAGNOSTICS-LEGACY-RETIREMENT-045 — Wave D / Domain 2 P1-A5 Front-Edge Experiment Diagnostics Retirement

Status: `WAITING_FOR_INDEPENDENT_WEB_AUDIT`
TASK_CLASS: `BOUNDED FINAL RESIDUE RETIREMENT`
Repository: `Lost0rz/RemoteOrbit`
Design authority: `docs/design/2026-11-01-045d-domain-2-p1a5-front-edge-experiment-retirement.md`
Human runtime/UI acceptance: `PENDING / USER-OWNED`

## Completed prerequisite

Wave D Domain 1 `REMOTE_ONLY_PCM_ATTRIBUTION` is accepted and closed:

- PR #38 independent exact-head audit: PASS (`FRESH_CONTEXT`);
- final reviewed PR head: `2fdb917e8c4d53e138315b8541e7b70202205d8e`;
- immutable implementation head: `23328cc68a3044413b66f4218cf27a925e35e588`;
- exact-head PR CI passed including Full Swift 507/507, Native Release and Universal2 packaging;
- merged with exact expected head as `3c1fa40e7304cbbef042a39010807743172ef3aa`;
- post-merge main CI run `41280239681`, job `124770517508`, passed source contracts, protocol self-tests, Full Swift, Native Release and Universal2 packaging.

## Domain execution rule

Wave D remains serial:

`Web audit/freeze → local cleanup → Web exact-head audit → merge/closeout → next domain`

This Domain 2 has already been audited and designed by Web. Local execution performs freshness/identity reconciliation, bounded implementation and verification only. Do not redo the audit, redesign the diagnostic architecture or widen the domain.

Before product mutation:

1. fresh-fetch live `main`;
2. read `AGENTS.md`, `CURRENT_STATUS.md`, this file and the design authority;
3. require the durable CI attached to the live Domain 2 control/authority commit to be final SUCCESS;
4. stop with `AUTHORITY_RECONCILIATION_REQUIRED` if live source materially conflicts with this authority.

## Purpose

Retire the obsolete P1-A5 front-edge experiment diagnostics and their duplicate realtime observation work, while preserving current gated diagnostics, long-term observability, continuity evidence and all voice/audio correctness behavior.

## Verified ownership basis

- `P1A5FrontEdgeDiagnostics.swift` defines a fixed experiment-only voice-onset detector and four front-edge underrun buckets.
- P1-A5 runtime is opt-in behind `DiagnosticsRuntimeGate.shared.isEnabled && REMOTE_ORBIT_P1A5_FRONT_EDGE == "1"`.
- `VoiceTimingLogger.end(...)` completes generic T0–T10 timing, continuity reporting, `LongTermObservabilityService.end(...)` and `VoiceAttemptDiagnostics.end(...)` before the P1-A5-only F0–F9/front-edge report.
- BLEBridge's `p1A5VoiceOnsetDetector` exists only to feed that experiment report.
- AudioPipe's P1-A5 markers exist only to feed that experiment report.
- AudioPipeRealtime emits both current `queueStarvation` and P1-A5 `frontEdgeUnderrun` observations for the same active underrun. Current long-term anomaly handling remains on `queueStarvation`.

## Authorized mutation

### `remote-orbit/Sources/RemoteOrbit/P1A5FrontEdgeDiagnostics.swift`

Delete the experiment-only source if all current callers are removed.

### `remote-orbit/Sources/RemoteOrbit/VoiceOptionTrigger.swift`

Within `VoiceTimingLogger`, retire only P1-A5-specific ownership:

- `p1A5Enabled`;
- `frontEdgeUnderrunStats` storage/reset/snapshot;
- P1-A5 F0–F9-only marker/report state;
- `recordVoiceOnset(...)`;
- `recordFrontEdgeUnderrun(...)`;
- final `[P1-A5] FRONT_EDGE_TIMELINE` report.

Preserve generic T0–T10 timeline/correlation, continuity ledger, transport metrics, `LongTermObservabilityService` calls, `VoiceAttemptDiagnostics` and diagnostic gating.

Do not rename or delete `P1A4MonotonicClock` in this domain.

### `remote-orbit/Sources/RemoteOrbit/BLEBridge.swift`

Remove only P1-A5-specific detector state/reset/analyze/marker calls. Preserve:

- normal ATVV decode and PCM delivery;
- current transport/notification/decode metrics;
- long-term observability calls;
- recording lifecycle;
- BLE READY/reuse and all drain/supersession behavior.

### `remote-orbit/Sources/RemoteOrbit/AudioPipe.swift`

Remove only P1-A5-specific F-series marker publication and front-edge experiment consumption.

Preserve current:

- realtime counters;
- long-term observation traces;
- render-starvation anomaly handling;
- queue/depth/drop diagnostics;
- reserve/render/output-drain behavior;
- candidate/prebuffer;
- Domain 6 input lease semantics.

### `remote-orbit/Sources/RemoteOrbit/AudioPipeRealtime.swift`

Retire `AudioPipeRealtimeObservation.Kind.frontEdgeUnderrun` and its duplicate active-underrun enqueue if direct caller audit remains as frozen.

Keep `queueStarvation`. Do not alter how active underrun/tail/idle counters are calculated and do not redesign the observation mailbox.

### Tests

Delete `P1A5FrontEdgeDiagnosticsTests.swift` if the experiment source is removed.

Adjust/rehome only directly affected tests. Do not delete current generic assertions merely because test names contain historical terminology.

If another retained test directly depends on an F0–F9 P1-A5 marker, determine whether the assertion is truly experiment-only. If it protects current generic timing/continuity/long-term semantics, rehome the generic assertion instead of deleting it.

### Current documentation/control references

Remove/update only executable/current documentation references that instruct users or developers to enable `REMOTE_ORBIT_P1A5_FRONT_EDGE`. Historical incident/design evidence is not cleanup scope.

## Explicit KEEP boundary

Do not change:

- `DiagnosticsRuntimeGate` behavior or effective gate;
- recording control;
- `P1A4MonotonicClock` implementation/API;
- generic T0–T10 voice lifecycle timing;
- `REMOTE_ORBIT_CONTINUITY_EVIDENCE` or continuity ledger semantics;
- `LongTermObservabilityService`, its incident coordinator, fixed traces, summaries or anomaly thresholds;
- current `queueStarvation` / render-starvation evidence;
- MainQueue responsiveness probe;
- AudioPipe ring/capacity/realtime synchronization;
- playout reserve;
- output drain/tail/grace;
- candidate/prebuffer;
- Gate-A 300 ms LONG-only semantics;
- SHORT tombstone, mapped-edge suppression/handoff, rapid repress, hardware/held-UP ownership;
- synthetic fallback or pre-HID physical candidate;
- BLE/ATVV protocol, codec, gain or sample rate;
- receiver readiness;
- Domain 6 temporary input lease;
- primary profile/mapping/persistence compatibility authority.

Historical `ShortTap` / `AudioOnly` names remain current correctness mechanisms and are not authorized for cosmetic cleanup here.

## Explicit non-goals

Do not:

- start Wave D Domain 3;
- turn this into a broad diagnostics rewrite;
- remove generic diagnostics because P1-A5 is retired;
- retire or rename P1-A4 timing infrastructure;
- retire continuity evidence;
- modify long-term incident semantics;
- change voice/audio product behavior;
- install/replace the app;
- mutate live driver/CoreAudio/TCC/default audio devices;
- tag/release;
- merge locally.

## Verification required

Focused evidence must prove at minimum:

1. no production `P1A5FrontEdge*` source/type remains;
2. no `REMOTE_ORBIT_P1A5_FRONT_EDGE` production control remains;
3. BLEBridge performs no P1-A5 detector/reset/analyze work;
4. AudioPipe performs no P1-A5 F-series/front-edge experiment work;
5. realtime no longer emits duplicate `frontEdgeUnderrun` while current `queueStarvation` remains;
6. generic T0–T10 lifecycle timing remains;
7. continuity evidence remains;
8. LongTermObservability transport/render/starvation/anomaly tests remain green;
9. diagnostics OFF still performs no structured diagnostic work as required by 045A;
10. recording independence remains;
11. AudioPipe realtime/reserve/output-drain regressions remain green;
12. LONG-only/rapid-repress/tombstone/suppression/transport-loss regressions remain green;
13. BLE/ATVV/readiness regressions remain green;
14. Domain 6 input lease remains green;
15. no live hardware/default-device mutation occurs during tests.

At minimum run focused suites covering:

- `AudioPipeRealtimeTests`
- `AudioPipeTests`
- `AudioDataPlaneDiagnosticsTests`
- `AudioDataPlaneMeasurementBoundaryTests`
- `AudioPipePlayoutReserveTests`
- `LongTermObservabilityTests`
- `DiagnosticsRuntimeGateTests`
- `DiagnosticHardeningTests`
- `BLEBridgeTests`
- `VoicePipelineSimplificationTests`
- `VoicePressCoordinatorTests`
- `VoiceKeyFilterTests`
- `VoiceReceiverReadinessTests`
- `RemoteVoiceInputLeaseTests`
- `WavRecorderDiagnosticsTests`

Then run:

- full `swift test`;
- `swift build -c release`;
- `git diff --check`;
- durable `.github/workflows/remoteorbit-ci.yml` on `remoteorbit-macmini`;
- Universal2 build-only packaging smoke.

## Workspace / delivery

Start from fresh live `main` after reconciliation. Use one fresh worktree/branch, suggested:

`codex/task045d-domain2-p1a5-front-edge-experiment-retirement`

The merged Wave D Domain 1 worktree may be retired only after confirming clean state and merged ancestry. Preserve its branch/history unless separately authorized.

Create one Draft PR. Do not merge locally.

After implementation/test/CI evidence is available, atomically update `CURRENT_STATUS.md` and `CURRENT_TASK.md` in one handoff commit. Do not encode that control commit's own future SHA; resolve final PR head and final-head CI at independent Web audit time.

## Stop

After implementation, verification, push, Draft PR, durable final-head CI, Universal2 and atomic control handoff, stop at:

`WAITING_FOR_INDEPENDENT_WEB_AUDIT`

Do not start another Wave D domain, install the app, mutate driver/CoreAudio/TCC/default devices, tag/release or merge locally.

## Execution receipt (2026-11-01)

- Fresh start: live `main@64c068cbbbfa24f4998bf974e9be527e0311e81e`; pre-mutation control CI run `41280826266`, job `124772229811`, final SUCCESS.
- Branch/worktree: `codex/task045d-domain2-p1a5-front-edge-experiment-retirement`.
- Implementation HEAD = Draft PR #39 head: `0fda6a43aa37dd160988f1fdb4dc7d9737bc3f72`.
- Deleted: `P1A5FrontEdgeDiagnostics.swift`, `P1A5FrontEdgeDiagnosticsTests.swift`. Modified: `VoiceOptionTrigger.swift`, `BLEBridge.swift`, `AudioPipe.swift`, `AudioPipeRealtime.swift`, `main.swift`, `Diagnostics/DiagnosticExport.swift`, `AudioPipeRealtimeTests.swift` (+2/−339 plus deletions).
- Retired: `p1A5Enabled`, `frontEdgeUnderrunStats`, `recordVoiceOnset`, `recordFrontEdgeUnderrun`, F0–F9 marker/report lifecycle, `[P1-A5] FRONT_EDGE_TIMELINE`, BLEBridge detector state/reset/analyze + F1/F2/F3 branches, AudioPipe F4/F5/F7/F8/F9 branches + front-edge consumer, `Kind.frontEdgeUnderrun` + duplicate enqueue, `REMOTE_ORBIT_P1A5_FRONT_EDGE` controls, orphaned `hasEvent`.
- Retained unchanged: `DiagnosticsRuntimeGate`, T0–T10 generic timing, `P1A4MonotonicClock`, continuity evidence, `LongTermObservabilityService`, current `queueStarvation`/render-starvation/main-queue-lag evidence, realtime counters/mailbox/reserve/render/drain, LONG-only/suppression/tombstone, BLE/ATVV/readiness, Domain 6 input lease, recording.
- Focused suites 286/286; full `swift test` 504/504; Release PASS; `git diff --check` clean; local Universal2 packaging smoke PASS (`x86_64 arm64`); durable CI run `41281602473`, job `124774470884`, on `remoteorbit-macmini`, SUCCESS.
- Wave D Domain 1 worktree retired (clean + merged ancestry verified); its branch/history preserved.
- No merge, no app install, no driver/CoreAudio/TCC/default-device mutation, no tag/release. HUMAN_UI_ACCEPTANCE remains `PENDING / USER-OWNED`.

Next action: independent Web exact-head audit of Draft PR #39 (`FRESH_CONTEXT`).

Return actual governance route/capability, topology/subagents, fresh start main, authority/control CI pre-mutation result, branch/worktree, implementation/final heads, remote equality, Draft PR, changed/deleted paths, retired P1-A5 surface, retained generic timing/continuity/LongTermObservability evidence, realtime duplicate-observation disposition, focused/full/build/diff/CI/package results, Wave D Domain 1 worktree disposition, scope-mutation flags, unresolved uncertainty, `HUMAN_UI_ACCEPTANCE`, merge state and final actual state.