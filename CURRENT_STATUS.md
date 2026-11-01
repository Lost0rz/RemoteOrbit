# CURRENT_STATUS

Last updated: 2026-11-01
State: `RO-DIAGNOSTICS-LEGACY-RETIREMENT-045 — DOMAIN_4_AUDIT_COMPLETE / READY_FOR_IMPLEMENTATION_HANDOFF`
Repository: `Lost0rz/RemoteOrbit`
Human runtime/UI acceptance: `PENDING / USER-OWNED`

## Task 045 progress

- Task 045A: `DIAGNOSTICS_GATING / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 1: `LEGACY_VOICE_PRODUCT_SURFACE / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 2: `LEGACY_VOICE_PERSISTED_PREFERENCE_AUTHORITY / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 3: `PERSISTENT_VOICE_RUNTIME_STATE_MACHINE / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 4: `DUAL_RECEIVER_RUNTIME_STATE_MACHINE / AUDIT_COMPLETE / READY_FOR_IMPLEMENTATION_HANDOFF`

## Domain 3 independent Web audit and closeout

Audit independence: `FRESH_CONTEXT`.

- Immutable implementation HEAD: `7cb5822a449340bc10c187a81aeb006958a5b151`.
- Final reconciled PR #34 head: `ccc32f605da81fb9874f831677cd969d30058a22`; the final reconciliation delta from `ebb9e9e4a237a66711ba2bab7e5e905c8d1d6c53` changed `CURRENT_STATUS.md` and `CURRENT_TASK.md` only.
- Exact-head durable PR CI `41263839832`, job `124722386420`, passed on `remoteorbit-macmini` through source contracts, protocol self-tests, full Swift, native Release, and Universal2 build-only packaging.
- Independent Web source/CI/identity audit found no remaining blocking finding after the control-plane reconciliation.
- PR #34 was merged using exact expected head `ccc32f605da81fb9874f831677cd969d30058a22` as merge commit `e8118342f43154a6b2a93cd70b679f4ef52f366b`.
- Post-merge main CI run `41264568492`, job `124724579093`, completed successfully through every durable stage including Universal2 packaging.
- No app install, driver/CoreAudio/TCC mutation, tag/release or machine-owned RC003/Doubao acceptance was performed.

Canonical audit basis for Domain 4: `main@e8118342f43154a6b2a93cd70b679f4ef52f366b`.

## Legacy retirement execution model

Retirement remains serial by bounded domain:

`Web audit/freeze → local cleanup → Web exact-head audit → merge/closeout → next domain`

Local execution performs only freshness/identity reconciliation for a frozen domain. It does not re-audit or redesign the domain unless current repository facts materially conflict with authority.

## Domain 4 audit — Dual Receiver Runtime State Machine

Design authority: `docs/design/2026-11-01-045b-domain-4-dual-receiver-runtime-retirement.md`.

### Verified production facts

- Production RC003 microphone input is Gate-A direct LONG-only; production `HIDButtonDownPolicy.resolve(...)` is invoked with `dualReceiverVoiceMode: .legacy`.
- `handleDualReceiverMicrophoneEdge(isDown:at:)` exists only as a definition in current `main.swift`; there is no production caller.
- `applySecondaryVoiceTriggerKey(...)` no longer has a product caller after Domains 1–2, and `configureDualReceiverVoiceMode(...)` is only part of that retired Receiver-B runtime seam.
- The standalone Dual sources remain present: `DualReceiverVoiceMode.swift`, `DualReceiverVoiceGestureRecognizer.swift`, and `DualReceiverMappedTriggerState.swift`.
- AppController still contains the dead A/B runtime island: recognizer/mode/mapped state, Receiver-B runtime value, secondary mapping arm/primary restore, reconfiguration ownership, prewarm and active-gesture state.
- VoicePressCoordinator still contains Dual-only classified gate/hold state and branches, while current Gate-A LONG-only ownership is represented separately.
- Current LONG-only suppression/tombstone/repress/drain mechanisms remain live and are not Dual-owned.

### Domain 4 classification

`RETIRE NOW`:

- all three standalone Dual Receiver source files;
- AppController Dual/Receiver-B runtime state and A↔B mapping transaction/orchestration;
- Dual-specific mapping generation/reconfiguration/prewarm/gesture state and diagnostics;
- Dual-only VoicePressCoordinator classified gate/hold state and methods proven to have no retained caller;
- Dual-specific `HIDButtonDownPolicy` input/exception once the mode type is removed;
- four dedicated `DualReceiver*Tests.swift` suites plus Dual-only cases/harness fields elsewhere, after rehoming any still-live generic assertion.

`KEEP`:

- `VoiceInputProfile` / `VoiceInputProfileStore` selected-profile authority;
- primary `RemoteVoiceKeyMapping` and HID mapping/readback verification;
- Gate-A direct LONG lifecycle and 300 ms contract;
- repeated SHORT-prefix→LONG, rapid repress, short tombstone, mapped-edge suppression and suppression handoff;
- hardware Option ownership, held-UP acknowledgement, synthetic fallback;
- pre-HID candidate, BLE/ATVV, AudioPipe, output drain/tail/grace;
- EventSuppressor / generic HardwareOptionGate;
- Task 045A diagnostics gate and independent recording;
- generic non-Dual legacy short/local-microphone classifier seams for a later domain;
- historical documentation as history.

`FROZEN FOR LATER DOMAIN`:

- generic legacy classifier/local-mic residue not required to remove Dual;
- cosmetic renames/refactors of live suppression/tombstone primitives;
- final broad legacy residue and Wave D resource/regression audit.

## Next gate

Domain 4 is fully audited/frozen and ready for one bounded local implementation from fresh live `main`. No Domain 5 mutation, merge, app install, driver/CoreAudio/TCC mutation, tag/release or machine-owned hardware acceptance is authorized.
