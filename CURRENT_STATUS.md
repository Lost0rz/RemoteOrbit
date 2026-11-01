# CURRENT_STATUS

Last updated: 2026-11-01
State: `RO-DIAGNOSTICS-LEGACY-RETIREMENT-045 — DOMAIN_3_IMPLEMENTATION_IN_PROGRESS`
Repository: `Lost0rz/RemoteOrbit`
Task 043: `MERGED / HUMAN_ACCEPTANCE_DEFERRED / USER-OWNED`
Task 045 overall: `ACTIVE`
Task 045A: `DIAGNOSTICS_GATING / MERGED / MAIN_CI_PASS / CLOSED`
Task 045B Domain 1: `LEGACY_VOICE_PRODUCT_SURFACE / MERGED / MAIN_CI_PASS / CLOSED`
Task 045B Domain 2: `LEGACY_VOICE_PERSISTED_PREFERENCE_AUTHORITY / MERGED / MAIN_CI_PASS / CLOSED`
Task 045B Domain 3: `PERSISTENT_VOICE_RUNTIME_STATE_MACHINE / IMPLEMENTATION_IN_PROGRESS / DRAFT_PR_OPEN / CI_PENDING`

Canonical implementation basis before Domain 3 execution: `main@54075fbe09c4f76bcb1287e675120fede7de3bc0`.
Human runtime/UI acceptance: `PENDING / USER-OWNED`.

## Domain 3 execution transition

- Freshness reconciliation verified canonical remote `https://github.com/Lost0rz/remoteorbit.git` and fetched `origin/main` at `54075fbe09c4f76bcb1287e675120fede7de3bc0`.
- Active branch: `codex/task045b-domain3-persistent-voice-runtime-retirement`.
- Authoritative workspace: `/Volumes/Jack-Dev/Projects/remoteorbit-task045b-domain3-persistent-voice-runtime-retirement`.
- The Domain 2 worktree was clean, its implementation head was an ancestor of `origin/main`, and its merged PR was verified before worktree retirement. Domain 2 branch/history remain preserved.
- Domain 3 implementation commit: `7cb5822a449340bc10c187a81aeb006958a5b151`.
- Local focused contracts and LONG-only regression suites pass; full local Swift suite is `623/623`, and native Release build passes. Durable CI, Draft PR, and final handoff remain pending.
- Draft PR `#34` is open at exact head `91052b1d1bc196b3e3ae9a59186dd193878cc36b`, targeting `main@54075fbe09c4f76bcb1287e675120fede7de3bc0`; durable CI is pending.
- This control transition is a direct child of the audited `main@54075fbe09c4f76bcb1287e675120fede7de3bc0` and authorizes only the frozen Domain 3 implementation and its required verification/delivery gates.

## Domain 2 independent Web audit and closeout

Audit independence: `FRESH_CONTEXT`.

- PR `#33` was reviewed against exact base `main@3e73382a39b4585e90ecf01558933eba1a828b96` at exact final head `54dc4790b8196256cd7846efd19f00159cfb15ad`.
- Implementation head `527923776a9ba9c93e1624b2847f7781da6e57bc` advanced to the reviewed head by one control-only commit changing `CURRENT_STATUS.md` and `CURRENT_TASK.md`; no second product-code delta was introduced.
- Final PR CI run `41261638863`, job `124715933001`, runner `remoteorbit-macmini`, validated the generated merge ref from the exact base/head and passed source contracts, protocol self-tests, full Swift `660/660`, native Release build, and Universal2 build-only packaging smoke.
- Independent source review found no blocking defect or scope escape. Persistent and Dual runtime state machines, LONG-only correctness, current profile authority, diagnostics gating, and independent recording remained intact.
- PR `#33` was merged using exact expected head `54dc4790b8196256cd7846efd19f00159cfb15ad` as merge commit `e96f69b7e848a999757e423edd0cc72efd459a7c`.
- Post-merge `main` CI run `41262000791`, job `124716992559`, runner `remoteorbit-macmini`, completed successfully through all durable stages including Universal2 packaging.
- No app install, driver/CoreAudio/TCC mutation, tag, release, or hardware acceptance was performed.

## Legacy retirement execution model

Legacy retirement remains serial by bounded domain:

`Web audit/freeze → local cleanup → Web exact-head audit → merge/closeout → next domain`

Local execution performs freshness/identity reconciliation but does not redesign an already frozen domain unless current repository facts materially conflict with authority.

## Domain 3 audit — Persistent Voice Runtime State Machine

Audit basis: merged `main@e96f69b7e848a999757e423edd0cc72efd459a7c`.
Design authority: `docs/design/2026-11-01-045b-domain-3-persistent-voice-runtime-retirement.md`.

### Verified facts

- Production RC003 microphone input is already the Gate-A direct LONG-only path. `startDirectVoicePress` explicitly states that no timing classifier or receiver/session mode participates in that lifecycle.
- The historical coordinator still carries `VoiceSessionMode`, `PendingPersistentToggle`, a Persistent trigger key/owner, Persistent-specific callbacks, and `RemoteSegmentTriggerPolicy.audioOnly` even though production no longer enters Persistent mode.
- Persistent audio-only behavior owns extra suppression state and diagnostic branches, including `onHardwareOptionGateSuppressForAudioOnly`, deferred Persistent trigger retry, and Persistent-segment completion/release handling.
- `AppController` still wires Persistent-only filter callbacks and retains `currentPersistentSessionTriggerKey`, `initialPersistentSessionTriggerKey`, startup coordinator configuration, and `applyPersistentSessionTriggerKey` as runtime-only historical seams.
- `VoiceKeyFilter.emitPersistentShortTap` / `emitDeferredPersistentShortTap` are Persistent-specific semantic helpers. The underlying short-discard/suppression owner is not Persistent-only.
- Current LONG-only tests directly exercise bounded SHORT discard, late mapped-edge suppression, SHORT-tombstone handoff, repeated SHORT prefixes followed by LONG, rapid repress, hardware/synthetic ownership, and output-drain behavior. Those mechanisms must remain even if their lower-level historical names mention short/audio-only suppression.
- Dual Receiver still uses the legacy classified-hold lifecycle (`beginClassifiedHardwareGate`, `beginClassifiedHardwareHold`, pending/holding state, trigger ownership and drain). It is not part of Domain 3.

### Domain 3 classification

`RETIRE NOW`:

- Persistent IME session state and transitions (`VoiceSessionMode`, configured/owner state, `PendingPersistentToggle`);
- Persistent-specific short-toggle semantics, deferred open/close retry, and configured-key runtime reconfiguration;
- Persistent audio-only segment policy/state and Persistent-only suppression callbacks/diagnostics;
- Persistent-specific AppController startup/configuration/wiring (`currentPersistentSessionTriggerKey`, `initialPersistentSessionTriggerKey`, `applyPersistentSessionTriggerKey`, Persistent callback bridges);
- Persistent-only filter semantic helpers such as `emitPersistentShortTap` / `emitDeferredPersistentShortTap`, and any adjacent helper proven to have no retained LONG-only/Dual caller;
- Persistent-only tests, after rehoming any still-valid generic ownership/suppression assertion not already covered by retained LONG-only tests;
- stale comments/diagnostic fields that describe Persistent sessions as live product behavior.

`KEEP`:

- Gate-A LONG-only candidate/direct-session lifecycle;
- `VoicePressCoordinator.State` and generic pending/holding/drain machinery still used by Dual or retained test seams;
- 300 ms `holdActivationThreshold` and current LONG-only admission contract;
- `PendingRepress` as a shared ownership object, while removing only Persistent-specific fields where safe;
- `VoiceKeyFilter.discardDeferredHardwareTrigger`, short-tap tombstone ownership, late mapped-edge suppression, quiet-window retirement, suppression handoff, pending hardware repress, held Option-up, replay acknowledgement, and reset-on-device-removal safety;
- lower-level `HardwareOptionGate` suppression/transfer behavior still used by LONG-only, even where historical method names contain `AudioOnly`;
- Dual Receiver recognizer/mode/mapped-state and A/B transaction runtime;
- current `VoiceInputProfile` authority, mapping schema, BLE/ATVV, AudioPipe, drain/tail/grace, diagnostics gate, and recording control.

`FROZEN FOR LATER DOMAIN`:

- `DualReceiverVoiceGestureRecognizer`, `DualReceiverVoiceMode`, `DualReceiverMappedTriggerState` and all A/B mapping/reconfiguration behavior;
- non-Persistent legacy short-action/local-microphone classifier seams that are not required to remove Persistent state;
- broader renaming/refactoring of shared tombstone/suppression primitives solely because their historical names are stale.

## Next gate

Implement the frozen Domain 3 in the active worktree, then run its focused/full/build/durable-CI verification and atomic control handoff. No Domain 4 mutation, merge, app install, driver/CoreAudio/TCC mutation, tag, release, or machine-owned RC003/Doubao acceptance is authorized.
