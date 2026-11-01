# CURRENT_STATUS

Last updated: 2026-11-01
State: `RO-DIAGNOSTICS-LEGACY-RETIREMENT-045 — WAVE_D_DOMAIN_2_AUDIT_COMPLETE / READY_FOR_IMPLEMENTATION_HANDOFF`
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
- Task 045D Domain 2: `P1A5_FRONT_EDGE_EXPERIMENT_DIAGNOSTICS / AUDIT_COMPLETE / READY_FOR_IMPLEMENTATION_HANDOFF`

## Wave D Domain 1 closeout

Independent Web audit of PR #38 passed with `FRESH_CONTEXT` at exact head `2fdb917e8c4d53e138315b8541e7b70202205d8e`; immutable implementation head was `23328cc68a3044413b66f4218cf27a925e35e588` and base was `8648c3f9c3f0f12e57e54767bfd04d8b05fff3ec`.

PR #38 was marked Ready only after audit PASS and merged with exact expected head as `3c1fa40e7304cbbef042a39010807743172ef3aa`.

Post-merge `main` CI run `41280239681`, job `124770517508`, passed source contracts, protocol self-tests, full Swift tests, Native Release and Universal2 build-only packaging. Domain 1 is therefore closed.

No app install, driver/CoreAudio/TCC/default-device mutation, tag/release or machine-owned hardware acceptance was performed.

## Wave D execution model

Final residue/resource/regression work remains serial by bounded domain:

`Web audit/freeze → local cleanup → Web exact-head audit → merge/closeout → next domain`

Historical naming is not retirement proof. Current correctness and diagnostic authority remain KEEP until direct ownership/caller evidence proves otherwise.

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

Wave D Domain 2 is audited and frozen for one bounded local implementation from fresh live `main`, after the durable CI attached to this control-only authority transition is final SUCCESS.

No Wave D Domain 3, app install, driver/CoreAudio/TCC/default-device mutation, tag/release or machine-owned hardware acceptance is authorized.