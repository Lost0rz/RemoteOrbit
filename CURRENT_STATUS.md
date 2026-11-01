# CURRENT_STATUS

Last updated: 2026-11-01
State: `RO-DIAGNOSTICS-LEGACY-RETIREMENT-045 — DOMAIN_4_CORRECTIVE_IMPLEMENTATION_COMPLETE / WAITING_FOR_INDEPENDENT_WEB_AUDIT`
Repository: `Lost0rz/RemoteOrbit`
Human runtime/UI acceptance: `PENDING / USER-OWNED`

## Task 045 progress

- Task 045A: `DIAGNOSTICS_GATING / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 1: `LEGACY_VOICE_PRODUCT_SURFACE / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 2: `LEGACY_VOICE_PERSISTED_PREFERENCE_AUTHORITY / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 3: `PERSISTENT_VOICE_RUNTIME_STATE_MACHINE / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 4: `DUAL_RECEIVER_RUNTIME_STATE_MACHINE / CORRECTIVE_IMPLEMENTATION_COMPLETE / WAITING_FOR_INDEPENDENT_WEB_AUDIT`

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

## Domain 4 corrective handoff — primary runtime test coverage

Design authority: `docs/design/2026-11-01-045b-domain-4-dual-receiver-runtime-retirement.md`.

Implementation identity and delivery:

- Fresh start main: `dcbd5ab03a306a8abd6e45036b53e108003d3698`.
- Implementation HEAD (immutable): `07a1cb569b4c4e3525aa18ef3c624a001d038bc5`.
- Branch/worktree: `codex/task045b-domain4-dual-receiver-runtime-retirement` / `remoteorbit-task045b-domain4-dual-receiver-runtime-retirement`.
- Draft PR: `#35`, base `main@dcbd5ab03a306a8abd6e45036b53e108003d3698`.
- The live PR head is resolved from GitHub at audit time; this control handoff records the immutable implementation parent and does not predeclare its own future SHA.
- Implementation-head durable CI: run `41265919091`, job `124728576017`, `RemoteOrbit CI`, runner `remoteorbit-macmini`, passed Full Swift tests, Native Release build and Universal2 build-only packaging smoke.
- Local verification: focused changed-boundary tests passed; `swift test` passed 523/523; `swift build -c release` passed; `git diff --check` passed.
- The atomic control handoff commit is the direct child of the implementation HEAD. Its SHA and the post-push CI identity must be resolved from the live branch/PR after publication.

Corrective implementation identity and delivery:

- Previous production-retirement implementation HEAD remains immutable: `07a1cb569b4c4e3525aa18ef3c624a001d038bc5`.
- Corrective test implementation HEAD (immutable): `8741de39cc85122bc50e0a581a37e7c8501885d7`.
- Corrective changed path: `remote-orbit/Tests/RemoteOrbitTests/PrimaryVoiceRuntimeTests.swift` only; no production source, Dual source, or existing retained test was restored or changed.
- Corrective exact-head durable CI: run `41267350942`, job `124732821405`, `RemoteOrbit CI`, runner `remoteorbit-macmini`, passed Full Swift tests, Native Release build and Universal2 build-only packaging smoke.
- Corrective local verification: `PrimaryVoiceRuntimeTests` 13/13, `VoiceKeyFilterTests` 18/18, `VoicePressCoordinatorTests` 41/41, full `swift test` 536/536, `swift build -c release`, and `git diff --check` passed.
- Rehomed primary assertions cover startup restore alignment; connected apply commit; absent/existing mapping rollback; rollback lock; in-progress press rejection; disconnected apply; synthetic, active voice-hold and hardware/suppression ownership rejection; same-key no-op; all six primary keys; and bounded raw old/new reconfiguration suppression.
- The historical active-filter gate assertion was not duplicated: `VoiceKeyFilterTests.testSuppressedOwnershipBlocksTriggerReconfiguration` is the retained equivalent and passed. The unrelated historical modifier-release-set assertion was outside the primary runtime corrective boundary.
- The final control handoff commit is the direct child of corrective test HEAD. Do not encode its own future SHA here; resolve the live PR head and its post-push CI directly from GitHub after publication.

Retired implementation surface:

- Deleted `DualReceiverVoiceMode.swift`, `DualReceiverVoiceGestureRecognizer.swift`, and `DualReceiverMappedTriggerState.swift`.
- Removed AppController Dual/Receiver-B state, A↔B mapping transaction, generation/reconfiguration/prewarm/gesture orchestration, Dual-specific HID-removal cleanup and diagnostics.
- Removed Dual-only classified gate/hold and `PendingRepress` seams from `VoicePressCoordinator`.
- Removed the Dual-mode dependency and active-Dual exception from `HIDButtonDownPolicy`.
- Deleted the four dedicated Dual Receiver suites and `VoiceTriggerRuntimeTests.swift`; removed Dual-only coordinator and HID-policy cases while rehoming retained selected-profile trigger-key assertions.

Explicitly preserved:

- `VoiceInputProfile` / `VoiceInputProfileStore`, profile ID persistence, `.voiceKeyDefault` Codable compatibility and mapping schema.
- Primary `RemoteVoiceKeyMapping`, hidutil mapping/readback implementation, Gate-A direct LONG and the 300 ms contract.
- Repeated SHORT-prefix→LONG, rapid repress, SHORT tombstone, late mapped-edge suppression, suppression handoff, hardware Option ownership/held-UP acknowledgement, synthetic fallback, pre-HID candidate, output drain/tail/grace.
- BLE/ATVV/AudioPipe, EventSuppressor/generic HardwareOptionGate, receiver readiness, Task 045A diagnostics gating and independent recording.
- Generic non-Dual legacy short/local-microphone classifier seams remain frozen for a later domain.

### Verified implementation result

- Production microphone remains Gate-A direct LONG-only; `HIDButtonDownPolicy` now has no Dual-mode type or active-Dual exception.
- The deleted Dual symbols have no production or retained test callers; only historical preference string fixtures remain where required to prove inert compatibility bytes.
- Current LONG-only suppression/tombstone/repress/drain mechanisms remain live and passed the retained regression suites.

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

Await independent Web exact-head source/CI/identity audit of the live PR head after the corrective control handoff. No merge, Domain 5 mutation, app install, driver/CoreAudio/TCC mutation, tag/release or machine-owned hardware acceptance is authorized.
