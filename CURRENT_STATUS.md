# CURRENT_STATUS

Last updated: 2026-11-01
State: `RO-DIAGNOSTICS-LEGACY-RETIREMENT-045 — DOMAIN_2_IMPLEMENTATION_IN_PROGRESS`
Repository: `Lost0rz/RemoteOrbit`
Task 043: `MERGED / HUMAN_ACCEPTANCE_DEFERRED / USER-OWNED`
Task 045 overall: `ACTIVE`
Task 045A: `DIAGNOSTICS_GATING / MERGED / MAIN_CI_PASS / CLOSED`
Task 045B Domain 1: `LEGACY_VOICE_PRODUCT_SURFACE / MERGED / MAIN_CI_PASS / CLOSED`
Task 045B Domain 2: `LEGACY_VOICE_PERSISTED_PREFERENCE_AUTHORITY / IMPLEMENTATION_IN_PROGRESS`

Active branch: `codex/task045b-domain2-legacy-voice-persisted-preferences`
Authoritative workspace: `/Volumes/Jack-Dev/Projects/remoteorbit-task045b-domain2-legacy-voice-persisted-preferences`
Implementation base: `origin/main@3e73382a39b4585e90ecf01558933eba1a828b96`
Start HEAD: `3e73382a39b4585e90ecf01558933eba1a828b96`

## Domain 1 independent Web audit and closeout

Audit independence: `FRESH_CONTEXT`.

- PR `#32` was reviewed at exact head `c6dc8c739cd9b5414c02cd2028e68fd57f337e17` against exact base `main@03d130ab9129932e3b1dc9fabf818f87f56c8fd4`.
- The implementation head was `9795719e403848b397c572a6072c43c76f95b888`; the only later commit to the reviewed head changed `CURRENT_STATUS.md` and `CURRENT_TASK.md` only.
- Exact-head PR CI `41259513453`, job `124709675970`, runner `remoteorbit-macmini` passed source contracts, protocol self-tests, full Swift `660/660`, native Release build, and Universal2 build-only packaging smoke.
- Independent source review found no blocking defect or scope escape. Persistent runtime, Dual runtime, AppStorage legacy persistence, LONG-only correctness, and Task 045A diagnostics gating were preserved.
- PR `#32` was merged with exact expected head as merge commit `1ba1f142a20a1da7a6ad7e6494d2126bc738c327`.
- Post-merge `main` CI run `41260109751`, job `124711439107`, runner `remoteorbit-macmini` completed successfully through every durable stage.
- Human UI/runtime acceptance remains `PENDING / USER-OWNED`; no app/driver/CoreAudio/TCC install or mutation was performed.

## Legacy retirement execution model

Legacy retirement remains serial by bounded domain:

`Web audit/freeze → local cleanup → Web exact-head audit → merge/closeout → next domain`

Local execution performs freshness/identity reconciliation but does not redesign an already frozen domain unless live facts materially conflict with authority.

## Domain 2 audit — Legacy Voice Persisted Preference Authority

Audit basis: merged `main@1ba1f142a20a1da7a6ad7e6494d2126bc738c327`.
Design authority: `docs/design/2026-11-01-045b-domain-2-legacy-voice-persisted-preference-authority.md`.

### Verified facts

- `VoiceInputProfile` / `VoiceInputProfileStore` is the retained user configuration authority. Its migration reads only the historical momentary trigger and deliberately ignores Persistent and Receiver-B preferences.
- `AppStorage` still declares and reads/writes `RemoteOrbit.persistentSessionTriggerKey` and `RemoteOrbit.secondaryMomentaryVoiceTriggerKey`; its legacy migration still seeds a Persistent key from the old generic trigger.
- `AppController.restoreVoiceTriggerRuntime()` still reads both retired preferences at launch, configures the historical Persistent coordinator key, and restores the Receiver-B value even though the direct Gate A microphone path does not consult those authorities.
- After Domain 1, `applyPersistentSessionTriggerKey` and `applySecondaryVoiceTriggerKey` have no product-surface callers. They remain historical runtime/test seams.
- The production RC003 microphone path is Gate A direct voice; its HID button-down policy is explicitly evaluated with `dualReceiverVoiceMode: .legacy`.
- Persistent and Dual runtime state machines still use their internal current-state values and are intentionally outside Domain 2.

### Domain 2 classification

`RETIRE NOW`:

- actual AppStorage/UserDefaults authority for Persistent-session trigger selection;
- actual AppStorage/UserDefaults authority for Receiver-B trigger selection;
- migration logic that creates/seeds the retired Persistent preference;
- production startup restore/hydration of Persistent and Receiver-B preferences;
- production persistence writes from the historical Persistent/Receiver-B runtime configuration seams;
- stale diagnostics/comments that describe these retired values as production persisted authorities;
- tests whose only contract is that Persistent/Receiver-B preferences independently round-trip through AppStorage.

`KEEP / COMPATIBILITY`:

- `VoiceInputProfile` / `VoiceInputProfileStore` and `RemoteOrbit.voiceInputProfileID`;
- historical `RemoteOrbit.voiceTriggerKey` plus `RemoteOrbit.momentaryVoiceTriggerKey` compatibility/migration projection used to seed or roll back the retained profile authority;
- current direct trigger reconfiguration and selected-profile persistence;
- `.voiceKeyDefault` Codable mapping token and mapping schema;
- existing old Persistent/Receiver-B UserDefaults bytes may remain inert; Domain 2 does not actively delete user data.

`FROZEN FOR LATER DOMAIN`:

- `VoiceSessionMode`, `PendingPersistentToggle`, `RemoteSegmentTriggerPolicy`, Persistent runtime state transitions and coordinator tests;
- `DualReceiverVoiceGestureRecognizer`, `DualReceiverVoiceMode`, `DualReceiverMappedTriggerState`, A/B mapping transaction state and runtime tests;
- `currentPersistentSessionTriggerKey` / `currentSecondaryMomentaryVoiceTriggerKey` as runtime-only state while those legacy state machines still exist;
- `applyPersistentSessionTriggerKey` / `applySecondaryVoiceTriggerKey` as runtime-only seams, except Domain 2 removes their production persistence side effects;
- all LONG-only ownership/suppression/repress/drain/pre-HID/BLE/AudioPipe mechanisms.

## Next gate

Local implements only Domain 2 from fresh live `main`, opens one Draft PR, runs focused + full durable verification, updates both control files atomically, and stops at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`.

No Domain 3 mutation, merge, install, release, driver/CoreAudio/TCC mutation is authorized locally.
