# CURRENT_STATUS

Last updated: 2026-11-01
State: `RO-DIAGNOSTICS-LEGACY-RETIREMENT-045 — WAVE_D_DOMAIN_2_IMPLEMENTATION_COMPLETE / WAITING_FOR_INDEPENDENT_WEB_AUDIT`
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
- Task 045D Domain 1: `REMOTE_ONLY_PCM_ATTRIBUTION / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045D Domain 2: `P1A5_FRONT_EDGE_EXPERIMENT_DIAGNOSTICS / IMPLEMENTATION_COMPLETE / PR_CI_PASS / WAITING_FOR_INDEPENDENT_WEB_AUDIT`

## Wave D Domain 1 closeout

Independent Web audit of PR #38 passed with `FRESH_CONTEXT` at exact head `2fdb917e8c4d53e138315b8541e7b70202205d8e`; immutable implementation head was `23328cc68a3044413b66f4218cf27a925e35e588` and base was `8648c3f9c3f0f12e57e54767bfd04d8b05fff3ec`.

PR #38 was marked Ready only after audit PASS and merged with exact expected head as `3c1fa40e7304cbbef042a39010807743172ef3aa`.

Post-merge `main` CI run `41280239681`, job `124770517508`, passed source contracts, protocol self-tests, full Swift tests, Native Release and Universal2 build-only packaging. Domain 1 is therefore closed.

No app install, driver/CoreAudio/TCC/default-device mutation, tag/release or machine-owned hardware acceptance was performed.

## Wave D execution model

Final residue/resource/regression work remains serial by bounded domain:

`Web audit/freeze → local cleanup → Web exact-head audit → merge/closeout → next domain`

Historical naming is not retirement proof. Current correctness and diagnostic authority remain KEEP until direct ownership/caller evidence proves otherwise.

## Wave D Domain 2 execution — P1-A5 Front-Edge Experiment Diagnostics

Implementation branch/worktree: `codex/task045d-domain2-p1a5-front-edge-experiment-retirement` from fresh live `main@64c068cbbbfa24f4998bf974e9be527e0311e81e` (control CI run `41280826266`, job `124772229811`, final SUCCESS before mutation).

Implementation HEAD / Draft PR #39 head: `0fda6a43aa37dd160988f1fdb4dc7d9737bc3f72`.

Retired surface:

- `P1A5FrontEdgeDiagnostics.swift` and `P1A5FrontEdgeDiagnosticsTests.swift` — deleted;
- `VoiceTimingLogger`: `p1A5Enabled`, `frontEdgeUnderrunStats`, `recordVoiceOnset`, `recordFrontEdgeUnderrun`, F0–F9 marker/report lifecycle and the final `[P1-A5] FRONT_EDGE_TIMELINE` report — deleted; `hasEvent` deleted with its only callers (P1-A5 F6 gates);
- BLEBridge: detector state/reset/analyze and F1/F2/F3 marker branches — deleted;
- AudioPipe: P1-A5-only F4/F5/F7/F8/F9 marker branches and the front-edge observation consumer — deleted;
- `AudioPipeRealtimeObservation.Kind.frontEdgeUnderrun` and its duplicate active-underrun enqueue — deleted;
- `REMOTE_ORBIT_P1A5_FRONT_EDGE` — removed from the launch instrumentation label and the diagnostic export receipt.

Retained unchanged: `DiagnosticsRuntimeGate`, generic T0–T10 timeline, `P1A4MonotonicClock` (untouched), `REMOTE_ORBIT_CONTINUITY_EVIDENCE`/continuity ledger, `LongTermObservabilityService`/incident coordinator/fixed traces, current `queueStarvation` + render-starvation + main-queue-lag evidence, realtime counters/mailbox/reserve/render/drain, candidate/prebuffer, Domain 6 input lease, LONG-only/tombstone/suppression, BLE/ATVV/readiness, recording and primary mapping.

Verification evidence:

- focused suites (AudioPipeRealtime, AudioPipe, AudioDataPlaneDiagnostics, AudioDataPlaneMeasurementBoundary, AudioPipePlayoutReserve, LongTermObservability, DiagnosticsRuntimeGate, DiagnosticHardening, BLEBridge, VoicePipelineSimplification, VoicePressCoordinator, VoiceKeyFilter, VoiceReceiverReadiness, RemoteVoiceInputLease, WavRecorderDiagnostics): 286/286 green;
- full `swift test`: 504/504 green;
- `swift build -c release`: PASS;
- `git diff --check`: clean;
- local Universal2 build-only packaging smoke: PASS (`x86_64 arm64`);
- durable RemoteOrbit CI on `remoteorbit-macmini` at exact PR head: run `41281602473`, job `124774470884`, SUCCESS.

Wave D Domain 1 worktree retired after clean + merged-ancestry confirmation; branch `codex/task045d-domain1-remote-only-pcm-attribution-retirement` and history preserved. No app install, driver/CoreAudio/TCC/default-device mutation, tag/release, or machine-owned hardware acceptance was performed. PR #39 remains Draft and unmerged.

## Wave D Domain 2 audit — P1-A5 Front-Edge Experiment Diagnostics

Design authority: `docs/design/2026-11-01-045d-domain-2-p1a5-front-edge-experiment-retirement.md`.

Verified facts:

- `P1A5FrontEdgeDiagnostics.swift` is explicitly an observation-only experiment model: fixed RMS voice-onset detector plus fixed front-edge underrun buckets.
- `VoiceTimingLogger.p1A5Enabled` requires both the diagnostics gate and `REMOTE_ORBIT_P1A5_FRONT_EDGE=1`; the P1-A5 F0–F9/front-edge report runs only after the normal generic timing/LongTermObservability session end path has already completed.
- BLEBridge still owns P1-A5-only detector state/reset/analyze work behind that opt-in gate.
- AudioPipe still records P1-A5-only F4/F7/F8/F9 markers and consumes the P1-A5 front-edge underrun observation.
- AudioPipeRealtime currently emits a `frontEdgeUnderrun` observation for every active underrun in addition to the existing `queueStarvation` observation for the same active underrun. The latter feeds current long-term anomaly handling and is retained.
- Current durable long-term observability is separately owned by `LongTermObservabilityService`, bounded traces, transport metrics, render starvation and main-queue-lag evidence; it does not require the P1-A5 front-edge report to exist.
- `P1A4MonotonicClock` is current shared timing infrastructure and is not retirement scope despite its historical name.
- `REMOTE_ORBIT_CONTINUITY_EVIDENCE` / continuity ledger and T0–T10 generic voice timing remain separate current evidence and are not retirement scope.

Classification:

`RETIRE NOW`:
- `P1A5FrontEdgeDiagnostics.swift` experiment-only detector/bucket model;
- `P1A5FrontEdgeDiagnosticsTests.swift` experiment-only tests;
- `VoiceTimingLogger.p1A5Enabled`, `frontEdgeUnderrunStats`, P1-A5 F0–F9 marker/report ownership, `recordVoiceOnset`, `recordFrontEdgeUnderrun`;
- BLEBridge P1-A5 detector/reset/analyze branches;
- AudioPipe P1-A5-only marker branches;
- `AudioPipeRealtimeObservation.Kind.frontEdgeUnderrun` and its duplicate active-underrun enqueue/consumer path, where current `queueStarvation` evidence remains equivalent for the active-underrun fact;
- directly associated current environment-variable/documentation references only if they describe this executable P1-A5 experiment control.

`KEEP`:
- diagnostics runtime gate;
- `VoiceTimingLogger` generic session timing and T0–T10 lifecycle correlation;
- `P1A4MonotonicClock`;
- continuity evidence and `REMOTE_ORBIT_CONTINUITY_EVIDENCE`;
- `LongTermObservabilityService`, bounded trace/incident capture and current queue-starvation/render-starvation evidence;
- AudioPipe realtime counters, reserve, render, drain and remote diagnostics;
- LONG-only, rapid repress, tombstone/suppression/handoff, hardware ownership, synthetic fallback, pre-HID, BLE/ATVV/readiness, Domain 6 input lease, recording and primary mapping authority.

`FROZEN FOR LATER`:
- broad historical naming/documentation cleanup;
- generic P1-A4 naming cleanup;
- old incident/design documents kept as historical evidence;
- any further diagnostic/resource lifecycle reduction not directly owned by P1-A5;
- final hardware/runtime acceptance.

## Next gate

Wave D Domain 2 implementation is complete with durable CI PASS at the exact Draft PR #39 head. Next: independent Web exact-head audit of PR #39 (`FRESH_CONTEXT`), then merge/closeout under that audit's authority.

No Wave D Domain 3, app install, driver/CoreAudio/TCC/default-device mutation, tag/release or machine-owned hardware acceptance is authorized.