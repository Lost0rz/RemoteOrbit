# CURRENT_STATUS

Last updated: 2026-11-01
State: `RO-DIAGNOSTICS-LEGACY-RETIREMENT-045 — DOMAIN_1_IMPLEMENTATION_COMPLETE / WAITING_FOR_INDEPENDENT_WEB_AUDIT`
Repository: `Lost0rz/RemoteOrbit`
Task 043: `MERGED / HUMAN_ACCEPTANCE_DEFERRED / USER-OWNED`
Task 045 overall: `ACTIVE`
Task 045A: `DIAGNOSTICS_GATING / MERGED / MAIN_CI_PASS / CLOSED`
Task 045B Domain 1: `LEGACY_VOICE_PRODUCT_SURFACE / IMPLEMENTATION_COMPLETE / DRAFT_PR_OPEN / DURABLE_CI_PASS / WAITING_FOR_INDEPENDENT_WEB_AUDIT`
Active branch: `codex/task045b-domain1-legacy-voice-product-surface`
Authoritative workspace: `/Volumes/Jack-Dev/Projects/remoteorbit-task045b-domain1-legacy-voice-product-surface`
Implementation base: `origin/main@03d130ab9129932e3b1dc9fabf818f87f56c8fd4`
Implementation head: `9795719e403848b397c572a6072c43c76f95b888`
Remote branch head: `9795719e403848b397c572a6072c43c76f95b888` (equal)
Draft PR: `#32` (`https://github.com/Lost0rz/RemoteOrbit/pull/32`)

## Task 045A closeout

- PR `#31` merged from exact reviewed head `d41a53e1f0d484bbf591bd8244cdf22ceedc9ece`.
- Merge commit: `27357a8e6301507b712ef65e9a74e973786dd263`.
- Post-merge durable CI run `41258162847`, job `124705656701`, runner `remoteorbit-macmini`: source contracts PASS, protocol self-tests PASS, full Swift tests PASS, native Release build PASS, Universal2 build-only packaging smoke PASS.
- No app install, driver/CoreAudio/TCC mutation, tag, or release was performed.
- Human RC003/Doubao acceptance remains deferred and user-owned.

## Task 045B Domain 1 execution

- Retired the Settings-only Persistent-session, Receiver-B, and microphone-SHORT
  product surface, including its SettingsWindow/main bridge wiring.
- Keymap microphone presentation is now fixed to retained LONG remote voice only.
- `.voiceKeyDefault` remains Codable-compatible and no longer carries Persistent
  user-facing wording.
- Focused source-contract, Keymap, profile-migration, and LONG-only suites passed
  (`96` tests, `0` failures); full `swift test` passed (`660` tests, `0` failures).
- `swift build -c release` passed.
- Durable CI run `41259237157`, job `124708848980`, passed on runner
  `remoteorbit-macmini`, including Universal2 build-only packaging smoke.
- The verified clean Task 045A worktree was retired after confirming its clean
  state and merged ancestry; its branch/history was retained.
- No Persistent runtime, Dual runtime, or AppStorage legacy persistence mutation
  was performed.

## Legacy retirement execution model

Legacy retirement proceeds serially by bounded domain:

1. Web performs a fresh read-only domain audit and freezes `KEEP / RETIRE / COMPATIBILITY` boundaries.
2. Local execution removes only that audited domain and returns machine evidence in one Draft PR/workspace.
3. Web independently re-audits the exact implementation head.
4. The current domain must be accepted and merged/closed before the next domain is authorized.

Local execution performs only freshness/identity reconciliation. It must not re-audit or redesign an already frozen domain unless live repository facts materially conflict with the authority.

## Domain 1 audit — Legacy Voice Product Surface

Audit basis: merged `main@27357a8e6301507b712ef65e9a74e973786dd263`.

### Verified facts

- Production RC003 microphone DOWN/UP uses the Gate A direct voice path; application mappings and the historical microphone short/long classifier do not participate in the production microphone path.
- `VoiceInputProfile` / `VoiceInputProfileStore` is the retained user voice-trigger configuration authority. Its migration explicitly permits only the old momentary trigger to seed the profile; Persistent and Receiver-B preferences do not compete with the new authority.
- `SettingsView.swift` still contains legacy Persistent-session, Receiver-B, and microphone-SHORT state, handlers, bridge closures, dead cards, and strings even though the current microphone page uses the newer direct-transfer card.
- `SettingsWindow.swift` and `main.swift` still wire Persistent/Receiver-B/microphone-SHORT settings callbacks into that legacy Settings surface.
- `KeymapOverlay.swift` still presents the microphone single-click action as `输入法持续会话`, which contradicts the durable SHORT=no-op product contract.
- `ButtonBinding.voiceKeyDefault` and the default microphone mapping still carry historical Persistent wording. The enum case remains useful as a persisted configuration compatibility token and must not be removed in Domain 1.
- AppStorage Persistent/Receiver-B preference keys and the underlying Persistent/Dual runtime are still connected to historical runtime/config plumbing. They are not part of Domain 1 and remain frozen for later domain audits.

### Domain 1 classification

`RETIRE NOW`:

- Settings-only Persistent-session trigger controls/state/handlers;
- Settings-only Receiver-B controls/state/handlers/runtime bridge;
- Settings-only microphone-SHORT mode/configuration controls and dead cards;
- obsolete SettingsWindow/main wiring whose only purpose is to supply those retired Settings controls;
- stale microphone KeymapOverlay single-click/Persistent presentation;
- stale user-facing Persistent wording on the retained `.voiceKeyDefault` compatibility token/default-mapping comments.

`KEEP`:

- `VoiceInputProfile` and `VoiceInputProfileStore`;
- current selected voice profile and normal direct trigger reconfiguration path;
- `ButtonBinding.voiceKeyDefault` Codable case as a compatibility token for existing mapping files;
- mapping file schema and existing user mappings;
- all LONG-only correctness mechanisms and current Gate A production path.

`FROZEN FOR LATER DOMAIN`:

- `AppStorage.persistentSessionTriggerKey*` and `secondaryMomentaryVoiceTriggerKey*` persistence/migration plumbing;
- `VoiceSessionMode`, `PendingPersistentToggle`, `RemoteSegmentTriggerPolicy`, Persistent runtime state and tests;
- `DualReceiverVoiceGestureRecognizer`, `DualReceiverVoiceMode`, `DualReceiverMappedTriggerState`, dual runtime reconfiguration and tests;
- any shared tombstone/suppression/repress/drain mechanism still required by LONG-only behavior.

Design authority: `docs/design/2026-11-01-045b-domain-1-legacy-voice-product-surface.md`.

## Next gate

`WAITING_FOR_INDEPENDENT_WEB_AUDIT` on PR `#32`. No merge and no Domain 2 mutation
are authorized locally.
