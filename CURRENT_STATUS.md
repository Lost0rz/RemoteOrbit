# CURRENT_STATUS

Last updated: 2026-11-01
State: `RO-DIAGNOSTICS-LEGACY-RETIREMENT-045 — DOMAIN_5_AUDIT_COMPLETE / READY_FOR_IMPLEMENTATION_HANDOFF`
Repository: `Lost0rz/RemoteOrbit`
Human runtime/UI acceptance: `PENDING / USER-OWNED`

## Task 045 progress

- Task 045A: `DIAGNOSTICS_GATING / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 1: `LEGACY_VOICE_PRODUCT_SURFACE / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 2: `LEGACY_VOICE_PERSISTED_PREFERENCE_AUTHORITY / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 3: `PERSISTENT_VOICE_RUNTIME_STATE_MACHINE / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 4: `DUAL_RECEIVER_RUNTIME_STATE_MACHINE / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 5: `LEGACY_GENERIC_SHORT_CLASSIFIER_RUNTIME / AUDIT_COMPLETE / READY_FOR_IMPLEMENTATION_HANDOFF`

## Domain 4 independent Web audit and closeout

Audit independence: `FRESH_CONTEXT`.

- Final reviewed PR #35 head: `aaa4ff238b826da55e80f0ff9d8708c80f10f4b7`.
- Corrective implementation HEAD: `8741de39cc85122bc50e0a581a37e7c8501885d7`; corrective product-code delta was NONE.
- Exact-head PR CI run `41267602388`, job `124733560093`, passed on `remoteorbit-macmini` through source contracts, protocol self-tests, full Swift, native Release, and Universal2 build-only packaging.
- The primary runtime coverage blocker was closed by `PrimaryVoiceRuntimeTests.swift` plus the retained `VoiceKeyFilterTests.testSuppressedOwnershipBlocksTriggerReconfiguration` assertion.
- PR #35 was merged using exact expected head as merge commit `fa49bb4fe38fd87a7ed36ab7bccfcfe2259434c6`.
- Post-merge main CI run `41268164507`, job `124735221877`, completed successfully through every durable stage including Universal2 packaging.
- No app install, driver/CoreAudio/TCC mutation, tag/release, or machine-owned RC003/Doubao acceptance was performed.

Canonical audit basis for Domain 5: `main@fa49bb4fe38fd87a7ed36ab7bccfcfe2259434c6`.

## Legacy retirement execution model

Retirement remains serial by bounded domain:

`Web audit/freeze → local cleanup → Web exact-head audit → merge/closeout → next domain`

Local execution performs only freshness/identity reconciliation for a frozen domain. It does not re-audit or redesign the domain unless current repository facts materially conflict with authority.

## Domain 5 audit — Legacy Generic Short Classifier Runtime

Design authority: `docs/design/2026-11-01-045b-domain-5-legacy-generic-short-classifier-retirement.md`.

### Verified production facts

- Production `AppController.beginVoicePress(...)` ignores its legacy `shortBinding` argument and always calls the coordinator with `directSession: true` plus `longOnlyAdmission: true`; both HID and filter-fallback microphone entrypoints use that same Gate-A path.
- `handleVoiceShortTap(...)`, `AppController.bypassesShortClassification(for:)`, and `VoicePressCoordinator.usesLocalMicrophone(forShortBinding:)` have no production caller.
- Coordinator states `.pending` and `.holding`, the short-action callback/local-microphone fields, the old hold timer, release-bounce fence, and legacy tail/repress activation branches exist only for the non-direct classifier path.
- Current direct LONG-only ownership is separate: long-only candidate/timer, direct session, direct rapid-repress handoff, hardware/synthetic trigger ownership, transport admission, direct output drain, tombstone/suppression handoff, BLE/pre-HID/AudioPipe remote path.
- `VoicePressCoordinator.tailDrainDelay` still has a live non-legacy caller in the mapped-edge suppression quiet-period path; historical naming is not retirement authority.
- `AudioPipe` still contains a separate local/external microphone AVCapture subsystem. Domain 5 will remove its dead coordinator callers only; the AudioPipe implementation itself is frozen for a separate Domain 6 audit.
- `DisabledShortClassifierTests.swift` exclusively tests the obsolete pending/holding classifier and is a Domain 5 retirement candidate.
- `VoicePressCoordinatorTests.swift` is mixed: current direct LONG-only assertions must remain; legacy pending/holding/tail classifier cases may be removed only after current claims are shown covered by retained direct suites.

### Domain 5 classification

`RETIRE NOW`:

- the non-direct branch of `VoicePressCoordinator.keyDown(...)` and legacy-only parameters/API surface;
- `.pending` / `.holding` coordinator states and their old classification lifecycle;
- hold timer / legacy long promotion / legacy long-input / legacy tail-work-item lifecycle;
- short callback, local-mic short-request state, pending-short preparation state, release-bounce-only state, and legacy-only `PendingRepress` payload/activation branches;
- AppController dead `shortBinding` voice-entry plumbing, `handleVoiceShortTap(...)`, `bypassesShortClassification(for:)`, and other classifier-only helpers;
- HUD/readiness projection branches that exist solely for `.pending` / `.holding`;
- `DisabledShortClassifierTests.swift` and legacy-only cases in mixed coordinator tests, with any still-current assertion rehomed before deletion.

`KEEP`:

- Gate-A LONG-only candidate and 300 ms threshold;
- direct session `.opening` / `.streaming` / `.draining` lifecycle;
- direct rapid LONG/release/LONG and pending direct repress ownership;
- short-discard tombstone, late mapped-edge suppression and suppression handoff;
- hardware Option ownership, held-UP acknowledgement, synthetic fallback;
- pre-HID physical candidate, BLE/ATVV, AudioPipe remote path, output drain/tail/grace;
- `VoicePressCoordinator.tailDrainDelay` while the current suppression quiet-period caller remains;
- current primary mapping/profile authority and Domain 4 `PrimaryVoiceRuntimeTests`;
- Task 045A diagnostics gate and independent recording;
- `VoiceKeyFilter` short-discard/suppression primitives and `VoiceOptionTrigger` operations that still have current callers.

`FROZEN FOR DOMAIN 6`:

- `AudioPipe` local/external microphone AVCapture implementation, permission flow, local capture state, delegate path and its dedicated tests/comments. Domain 5 may remove now-dead callers from `main.swift` but must not mutate the AudioPipe local-microphone implementation itself.

`FROZEN FOR LATER / WAVE D`:

- cosmetic rename of live short/audio-only-named suppression primitives;
- broad diagnostics/history cleanup;
- final resource/regression audit and hardware acceptance.

## Next gate

Domain 5 is fully audited/frozen and ready for one bounded local implementation from fresh live `main`. No Domain 6 mutation, merge, app install, driver/CoreAudio/TCC mutation, tag/release, or machine-owned hardware acceptance is authorized.
