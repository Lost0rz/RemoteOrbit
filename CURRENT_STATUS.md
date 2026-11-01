# CURRENT_STATUS

Last updated: 2026-11-01
State: `RO-DIAGNOSTICS-LEGACY-RETIREMENT-045 — MACHINE_AUDIT_COMPLETE / READY_FOR_HUMAN_RUNTIME_ACCEPTANCE`
Repository: `Lost0rz/RemoteOrbit`
Human runtime/UI acceptance: `READY / USER-OWNED / NOT_YET_EXECUTED`

## Task 045 progress

- Task 045A: `DIAGNOSTICS_GATING / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 1: `LEGACY_VOICE_PRODUCT_SURFACE / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 2: `LEGACY_VOICE_PERSISTED_PREFERENCE_AUTHORITY / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 3: `PERSISTENT_VOICE_RUNTIME_STATE_MACHINE / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 4: `DUAL_RECEIVER_RUNTIME_STATE_MACHINE / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 5: `LEGACY_GENERIC_SHORT_CLASSIFIER_RUNTIME / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 6: `LOCAL_MICROPHONE_CAPTURE / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045D Domain 1: `REMOTE_ONLY_PCM_ATTRIBUTION / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045D Domain 2: `P1A5_FRONT_EDGE_EXPERIMENT_DIAGNOSTICS / MERGED / MAIN_CI_PASS / CLOSED`
- Final whole-repository machine audit: `PASS_WITH_FOLLOWUPS / READY_FOR_HUMAN_RUNTIME_ACCEPTANCE`

## Final whole-repository machine audit

Audit basis was fresh live `main` after Wave D Domain 2 closeout. The audit was read-only with respect to product source and runtime.

### Accepted machine conclusion

No additional product-code retirement Domain is required before human runtime acceptance.

Direct source/caller review and the durable regression suite establish that the planned obsolete voice/runtime authorities have been removed from production ownership:

- Persistent voice product/runtime authority: retired;
- Receiver-B / Dual Receiver runtime authority: retired;
- generic non-direct SHORT/LONG classifier states: retired;
- RemoteOrbit-owned local/external microphone AVCapture path and microphone TCC ownership: retired;
- local/mixed PCM attribution model: retired;
- P1-A5 front-edge experiment diagnostics and duplicate realtime observation: retired.

Current production voice ownership is the accepted LONG-only model: SHORT below the 300 ms boundary is a no-op; LONG crossing the boundary promotes to the direct remote voice lifecycle; release follows bounded output-drain/trigger-release ownership.

Historical names are not retirement evidence. `ShortTap` / `AudioOnly` suppression primitives and `P1A4MonotonicClock` remain current because direct callers still use them for LONG-only correctness/timing.

### Machine evidence

Latest product merge CI after Domain 2: run `41282571433`, job `124777309274`, `SUCCESS` on `remoteorbit-macmini`, including Source contract checks, Protocol self-tests, Full Swift tests (504/504), Native Release and Universal2 packaging.

Domain 2 closeout control CI: run `41282783523`, job `124777921972`, `SUCCESS` including the same durable gates.

Current source audit additionally confirmed:

- `main.swift` has no active Dual Receiver, local-microphone, P1-A5, legacy short-binding or `handleVoiceShortTap` production entry;
- `VoicePressCoordinator.State` is limited to `idle/opening/streaming/draining`;
- the hardware trigger filter discards short/unpromoted candidates and only releases captured trigger ownership after LONG confirmation/current LONG-ready seams;
- selected `VoiceInputProfile` is the single current profile authority; old momentary trigger bytes are compatibility projection/migration only and Persistent/Receiver-B bytes are not consulted;
- packaged Info.plist no longer declares microphone TCC; Bluetooth/Input Monitoring/Accessibility/Apple Events remain the relevant permission surfaces;
- AudioPipe realtime ring remains preallocated/bounded and its callback-side contract remains lock/dispatch/dynamic-sample-buffer free by source contract tests;
- no source-level `fatalError`, `TODO`, `FIXME`, or `try!` residue was found by the final audit search.

### Remaining uncertainty — human-owned, not machine blockers

CI cannot prove real RC003/Doubao/CoreAudio/TCC behavior. The following remain intentionally unpromoted until human acceptance:

- actual HID edge ordering and mapped-trigger suppression on the user's remote;
- actual BLE/ATVV start/stop/reconnect behavior;
- installed `RemoteOrbitAudio.driver` identity and `RemoteOrbit Mic 2ch` availability;
- actual Accessibility/Input Monitoring/Bluetooth permissions for the installed RemoteOrbit process;
- actual Doubao IME activation and text completeness at speech head/middle/tail;
- real rapid LONG/release/LONG behavior and physical-input lease restoration;
- idle/repeated-session resource behavior on the user's machine.

### Non-blocking follow-ups

These do not block human runtime acceptance but must not be mistaken for current runtime authority:

1. `README.md` and `SETUP_NOTES.md` still contain stale baseline/version text (`0.2.12 (Build 41)`) while current packaged Info.plist is `0.2.15 (Build 44)`. `SETUP_NOTES.md` also retains portions of the older classifier/first-PCM activation narrative. For this acceptance phase, `CURRENT_TASK.md` is the acceptance authority. Documentation should be reconciled before final release/tag.
2. Draft PR #25 (old v0.2.15 soak/release candidate) and Draft PR #26 (old Settings corrective) are historical/diverged and must not be merged into current main. They are repository-hygiene follow-ups for final closeout.
3. Draft PR #28 is a separate branding/icon task. It does not alter BLE/HID/AudioPipe/voice semantics and does not block Task 045 voice runtime acceptance; it requires its own lifecycle decision.
4. One test-only compiler warning remains for an unnecessary `try` in `LocalMicrophoneCaptureRetirementContractTests.swift`; no runtime effect was found.
5. CI packaging intentionally does not build the HAL driver, so its smoke app may report that the repair button is unavailable. Human acceptance may reuse an already-correct installed driver. If the driver is absent/incorrect, stop and obtain separate authorization before driver/CoreAudio mutation.

## Current boundary

The repository is now ready to enter human runtime acceptance. No Wave D Domain 3 product cleanup is authorized or required by this audit.

The exact human acceptance matrix and allowed side effects are owned by `CURRENT_TASK.md`.

Until the owner explicitly authorizes candidate installation/runtime mutation:

- no app replacement/install;
- no driver install/reload;
- no CoreAudio restart;
- no TCC reset/change;
- no default-device mutation by an agent;
- no tag/release;
- no stale PR merge/close unless separately authorized.
