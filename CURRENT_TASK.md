# RemoteOrbit Current Task

## RO-DIAGNOSTICS-LEGACY-RETIREMENT-045 — Wave B / Domain 3 Persistent Voice Runtime State Machine

Status: `IMPLEMENTATION_IN_PROGRESS`
TASK_CLASS: `BOUNDED LEGACY RETIREMENT`
Repository: `Lost0rz/RemoteOrbit`
Design authority: `docs/design/2026-11-01-045b-domain-3-persistent-voice-runtime-retirement.md`
Human runtime/UI acceptance: `PENDING / USER-OWNED`

## Execution transition

- Fresh live basis: `origin/main@54075fbe09c4f76bcb1287e675120fede7de3bc0`, verified from `https://github.com/Lost0rz/remoteorbit.git` immediately before workspace creation.
- Active branch: `codex/task045b-domain3-persistent-voice-runtime-retirement`.
- Active workspace: `/Volumes/Jack-Dev/Projects/remoteorbit-task045b-domain3-persistent-voice-runtime-retirement`.
- Domain 2 worktree retirement was authorized only after clean-state and merged-ancestry verification; its branch/history remain preserved.
- Domain 3 implementation has started from the fresh live main. Draft PR, implementation HEAD, verification results, and final control HEAD remain pending.

## Completed prerequisite

Domain 2 is accepted and closed:

- PR #33 exact-head independent Web audit: PASS (`FRESH_CONTEXT`);
- merged as `e96f69b7e848a999757e423edd0cc72efd459a7c` from exact expected head `54dc4790b8196256cd7846efd19f00159cfb15ad`;
- post-merge CI `41262000791` / job `124716992559` succeeded on `remoteorbit-macmini` through all durable stages including Universal2 packaging.

## Domain execution rule

Legacy retirement remains serial:

`Web audit/freeze → local cleanup → Web exact-head audit → merge/closeout → next domain`

Do not redesign Domain 3 locally. Perform freshness/identity reconciliation only. A material conflict with this authority returns `AUTHORITY_RECONCILIATION_REQUIRED`.

## Domain 3 purpose

Remove the obsolete Persistent IME voice-session runtime state machine and its audio-only segment semantics while preserving the current LONG-only product path, all shared trigger-ownership/suppression/drain correctness, and the entire Dual Receiver runtime for a later dedicated domain.

## Authorized mutation

### `remote-orbit/Sources/RemoteOrbit/main.swift`

Retire Persistent-only runtime state and behavior from `VoicePressCoordinator` and `AppController`, including where applicable:

- `VoiceSessionMode` and Persistent configured/owner state;
- `PendingPersistentToggle` and deferred Persistent open/close retry;
- `persistentHoldActivationThreshold` / `isPersistentSessionLongPress`;
- Persistent toggle flags/arguments/branches in legacy `keyDown`, `PendingRepress`, `startAcceptedVoicePress`, and `keyUp`;
- Persistent-only trigger callbacks and diagnostics;
- the audio-only Persistent segment distinction (`RemoteSegmentTriggerPolicy.audioOnly`) and its Persistent-only state fields/branches;
- `currentPersistentSessionTriggerKey`, `initialPersistentSessionTriggerKey`, startup configuration of that key, and `applyPersistentSessionTriggerKey`;
- stale comments that describe SHORT/Persistent behavior as current production semantics.

`RemoteSegmentTriggerPolicy` may be removed entirely if, after deleting `.audioOnly`, its only remaining purpose would be a one-value wrapper around ordinary momentary behavior. Retained Dual/legacy momentary logging may be simplified to fixed momentary semantics without changing ownership/timing behavior.

### `VoiceKeyFilter` boundary inside `main.swift`

Persistent-only semantic helpers may be removed when exact call-site inspection proves they have no retained caller, including:

- `emitPersistentShortTap`;
- `emitDeferredPersistentShortTap`;
- Persistent-only audio-only suppression entry helpers.

Do **not** remove the underlying generic suppression/tombstone machinery merely because historical names mention short tap or audio-only. In particular preserve any lower-level owner transition still used by the LONG-only handoff.

### Tests

Persistent-only product/runtime suites may be removed or rewritten:

- `VoicePersistentSessionTests.swift`;
- `VoicePersistentShortTapTests.swift`;
- Persistent-only cases in `VoiceTriggerRuntimeTests.swift`, `VoiceOptionTriggerTests.swift`, diagnostic tests, or other directly affected suites.

Before deleting a Persistent suite, rehome any generic trigger-ownership/suppression assertion that remains relevant and is not already covered by retained LONG-only/Dual tests.

Existing `VoicePressCoordinatorTests` already own important current contracts such as bounded SHORT discard, late mapped-edge suppression, SHORT-tombstone handoff, repeated SHORT-prefix→LONG, rapid repress and direct drain. Do not weaken or delete those tests.

### Control files

At implementation handoff, update `CURRENT_STATUS.md` and `CURRENT_TASK.md` atomically in one commit after implementation/test/CI evidence is available.

## Explicit KEEP boundary

Do not delete, redesign, or weaken:

- `VoiceInputProfile` / `VoiceInputProfileStore` and current selected-profile authority;
- Gate-A private LONG candidate and direct session lifecycle;
- SHORT `<300 ms` no-op and LONG `>=300 ms` direct voice contract;
- `holdActivationThreshold == 0.30`;
- repeated SHORT-prefix→LONG recovery;
- rapid LONG/release/LONG and pending direct repress ownership;
- short-discard tombstone ownership;
- late mapped Option down/up/flags suppression;
- LONG-only suppression handoff;
- hardware Option deferral/replay/held-UP acknowledgement;
- synthetic fallback;
- output drain, tail/grace, pre-HID physical candidate, BLE READY/reuse and AudioPipe ownership;
- `VoicePressCoordinator.State` / generic pending/holding/drain machinery while still required by Dual or retained seams;
- `DualReceiverVoiceGestureRecognizer`, `DualReceiverVoiceMode`, `DualReceiverMappedTriggerState`, `currentSecondaryMomentaryVoiceTriggerKey`, A/B mapping/reconfiguration and their safety tests;
- non-Persistent short-action/local-microphone seams unless removal is an unavoidable compile-only consequence of deleting Persistent state and does not alter retained behavior;
- lower-level `HardwareOptionGate` suppression-transfer machinery used by current LONG-only behavior, even if a historical method name contains `AudioOnly`;
- Task 045A diagnostics gate and independent recording control.

## Explicit non-goals

Do not:

- retire Dual Receiver in Domain 3;
- redesign the current direct voice path;
- change 300 ms classification threshold;
- change BLE/ATVV, codec, sample rate, gain, AudioPipe transport/buffer/IOProc;
- change HID mapping/readback correctness or receiver-readiness architecture;
- broadly rename/refactor shared suppression primitives for cosmetics;
- install/replace the app, mutate driver/CoreAudio/TCC, tag or release;
- start Domain 4.

If deleting a Persistent symbol requires semantic removal/redesign of a retained Dual or LONG-only mechanism, stop with `AUTHORITY_RECONCILIATION_REQUIRED` rather than expanding scope.

## Verification required

Focused evidence must prove at minimum:

1. Persistent runtime/session symbols and Persistent open/close state transitions are absent from production runtime.
2. Persistent audio-only segment behavior and Persistent-specific trigger callbacks are absent.
3. AppController no longer stores/configures/reconfigures a Persistent trigger runtime key.
4. No product code can enter a Persistent session through the retained legacy classifier seams.
5. Shared short-discard/tombstone/suppression behavior used by LONG-only remains present and covered.
6. LONG-only current regression remains green, including bounded SHORT discard, repeated SHORT prefixes, late mapped-edge suppression, rapid repress, normal LONG/release/drain, synthetic fallback and pre-HID behavior.
7. Dual Receiver suites remain green and its source files/state machine are unchanged except directly adjacent compile adaptation with no semantic change.
8. Profile/persistence authority from Domains 1–2 and diagnostics gating from 045A remain green.

Then run:

- focused changed-boundary tests;
- full `swift test`;
- `swift build -c release`;
- `git diff --check`;
- durable `.github/workflows/remoteorbit-ci.yml` on `remoteorbit-macmini`, including Universal2 build-only packaging smoke.

## Workspace / delivery

Start from fresh live `main` after reconciliation. Use one fresh worktree/branch, suggested:

`codex/task045b-domain3-persistent-voice-runtime-retirement`

The merged Domain 2 worktree may be retired only after confirming clean state and merged ancestry. Preserve its branch/history unless separately authorized.

Create one Draft PR. Do not merge locally.

## Stop

After implementation, verification, push, Draft PR, durable CI, and atomic control handoff, stop at:

`WAITING_FOR_INDEPENDENT_WEB_AUDIT`

Do not start Domain 4. Do not install the app or mutate driver/CoreAudio/TCC.

Return actual governance route, start main, branch/worktree, implementation and final control heads, remote equality, Draft PR, changed paths, retired Persistent runtime surface, retained shared/Dual mechanisms, deleted/rehomed tests, focused/full/build/diff/CI/package results, predecessor-worktree disposition, explicit scope-mutation flags, unresolved uncertainty, `HUMAN_UI_ACCEPTANCE`, and final actual state.
