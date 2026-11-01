# RemoteOrbit Current Task

## RO-DIAGNOSTICS-LEGACY-RETIREMENT-045 — Wave B / Domain 2 Legacy Voice Persisted Preference Authority

Status: `READY_FOR_IMPLEMENTATION_HANDOFF`
TASK_CLASS: `BOUNDED LEGACY RETIREMENT`
Repository: `Lost0rz/RemoteOrbit`
Design authority: `docs/design/2026-11-01-045b-domain-2-legacy-voice-persisted-preference-authority.md`
Human runtime/UI acceptance: `PENDING / USER-OWNED`

## Completed prerequisite

Domain 1 is accepted and closed:

- PR #32 exact-head independent Web audit: PASS (`FRESH_CONTEXT`);
- merged as `1ba1f142a20a1da7a6ad7e6494d2126bc738c327`;
- post-merge CI `41260109751` / job `124711439107` succeeded on `remoteorbit-macmini` through all durable stages.

## Domain execution rule

Legacy retirement remains serial:

`Web audit/freeze → local cleanup → Web exact-head audit → merge/closeout → next domain`

Do not redesign Domain 2 locally. Perform freshness/identity reconciliation only. A material mismatch with current authority returns `AUTHORITY_RECONCILIATION_REQUIRED`.

## Domain 2 purpose

Retire the obsolete Persistent-session and Receiver-B **persisted preference authorities** so the launched product no longer reads, creates, restores, or writes those preferences. Preserve their historical runtime state machines and runtime-only test seams for later dedicated domains.

## Authorized mutation

### `remote-orbit/Sources/RemoteOrbit/AppStorage.swift`

Retire actual storage authority for:

- `RemoteOrbit.persistentSessionTriggerKey`;
- `RemoteOrbit.secondaryMomentaryVoiceTriggerKey`.

Remove their AppStorage constants/properties/read/write helpers and stop legacy migration from seeding a Persistent key.

Preserve:

- `RemoteOrbit.voiceTriggerKey` legacy compatibility alias;
- `RemoteOrbit.momentaryVoiceTriggerKey` compatibility projection;
- the ability for an old generic trigger value to seed the retained momentary/profile authority.

Do **not** actively delete already-existing Persistent/Receiver-B UserDefaults values. They become inert historical bytes, preserving rollback/reversibility without remaining an authority.

### `remote-orbit/Sources/RemoteOrbit/main.swift`

Remove production AppStorage coupling for retired preferences:

- production initializer defaults must no longer read/write AppStorage Persistent or Receiver-B preferences;
- production `restoreVoiceTriggerRuntime()` must no longer hydrate Persistent/Receiver-B state from UserDefaults or claim those values as persisted production configuration;
- historical `applyPersistentSessionTriggerKey` / `applySecondaryVoiceTriggerKey` may remain as runtime-only seams, but must not write retired product preferences.

Runtime-only state required by the still-retained historical state machines may remain. Do not delete Persistent/Dual state machines in this domain.

If injected legacy runtime initialization seams are still needed solely to keep later-domain runtime tests deterministic, they may remain only if their production defaults are inert and comments/tests clearly establish that they are not product persistence authorities. Prefer removing obsolete persistence hooks when this can be done without redesigning the runtime state machines.

### Tests

Focused test changes may include:

- `VoiceTriggerKeyTests.swift`;
- `DualReceiverVoiceSettingsTests.swift`;
- `VoicePipelineSimplificationTests.swift`;
- `VoiceTriggerRuntimeTests.swift`;
- a new bounded source-contract test if useful.

Tests must stop asserting Persistent/Receiver-B AppStorage round-trip as a valid product contract. Runtime-state tests may be adapted only as necessary to supply runtime-only state explicitly; do not weaken their ownership/timing/safety assertions.

### Control files

Update `CURRENT_STATUS.md` and `CURRENT_TASK.md` atomically at handoff.

## Explicit KEEP boundary

Do not remove or redesign:

- `VoiceInputProfile` / `VoiceInputProfileStore`;
- profile ID persistence;
- `voiceTriggerKeyKey` / `momentaryVoiceTriggerKeyKey` compatibility path;
- current profile/direct trigger reconfiguration;
- `.voiceKeyDefault` Codable token and mapping schema;
- `VoiceSessionMode`, `PendingPersistentToggle`, `RemoteSegmentTriggerPolicy`;
- Persistent runtime state transitions;
- `DualReceiverVoiceGestureRecognizer`, `DualReceiverVoiceMode`, `DualReceiverMappedTriggerState`;
- Dual A/B mapping transaction state;
- runtime-only `currentPersistentSessionTriggerKey` / `currentSecondaryMomentaryVoiceTriggerKey` while those state machines remain;
- runtime-only Persistent/Dual configuration methods except removal of retired persistence side effects;
- current LONG-only correctness path and all ownership/suppression/repress/drain/pre-HID/BLE/AudioPipe mechanisms;
- Task 045A diagnostics gate and independent recording control.

## Durable product boundary

Must remain unchanged:

- SHORT `<300 ms` = absolute user-visible no-op;
- LONG `>=300 ms` = direct remote voice lifecycle;
- repeated SHORT prefixes do not poison final LONG;
- rapid LONG/release/LONG remains bounded;
- current selected `VoiceInputProfile` remains the user configuration authority.

No BLE/ATVV, codec, gain, sample rate, AudioPipe transport/buffer/IOProc, HID mapping/readback correctness, receiver-readiness architecture, app install, driver/CoreAudio/TCC, tag/release changes.

## Verification required

Focused evidence must prove at minimum:

1. AppStorage no longer exposes or migrates Persistent/Receiver-B preference authority.
2. Legacy generic/momentary trigger compatibility still seeds `VoiceInputProfile` correctly.
3. Existing stale Persistent/Receiver-B UserDefaults values cannot override or compete with the selected profile authority.
4. Launched-product startup restore no longer reads Persistent/Receiver-B AppStorage preferences.
5. Historical runtime Persistent/Dual seams, where retained, remain deterministic without product persistence writes.
6. Existing Persistent/Dual runtime safety tests remain green except assertions explicitly retired because they asserted persistence rather than runtime behavior.
7. Current LONG-only regression suite, including `VoicePressCoordinatorTests`, remains green.

Then run:

- focused changed-boundary tests;
- full `swift test`;
- `swift build -c release`;
- `git diff --check`;
- durable `.github/workflows/remoteorbit-ci.yml` on `remoteorbit-macmini`, including Universal2 build-only packaging smoke.

## Workspace / delivery

Start from fresh live `main` after reconciliation. Use one fresh worktree/branch, suggested:

`codex/task045b-domain2-legacy-voice-persisted-preferences`

The merged Domain 1 worktree may be retired only after confirming clean state and merged ancestry. Preserve its branch/history unless separately authorized otherwise.

Create one Draft PR. Do not merge locally.

## Stop

After implementation, verification, push, Draft PR, durable CI, and atomic control handoff, stop at:

`WAITING_FOR_INDEPENDENT_WEB_AUDIT`

Do not start Domain 3. Do not install the app or mutate driver/CoreAudio/TCC. Return actual branch/worktree/head, changed paths, retired persistence surface, preserved runtime/compatibility seams, focused/full tests, CI identity, remote equality, predecessor-worktree disposition, unresolved uncertainty, and final state.