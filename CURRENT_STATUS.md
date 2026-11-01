# CURRENT_STATUS

Last updated: 2026-11-01
State: `RO-DIAGNOSTICS-LEGACY-RETIREMENT-045 — DOMAIN_5_IMPLEMENTATION_COMPLETE / WAITING_FOR_INDEPENDENT_WEB_AUDIT`
Repository: `Lost0rz/RemoteOrbit`
Human runtime/UI acceptance: `PENDING / USER-OWNED`

## Task 045 progress

- Task 045A: `DIAGNOSTICS_GATING / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 1: `LEGACY_VOICE_PRODUCT_SURFACE / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 2: `LEGACY_VOICE_PERSISTED_PREFERENCE_AUTHORITY / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 3: `PERSISTENT_VOICE_RUNTIME_STATE_MACHINE / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 4: `DUAL_RECEIVER_RUNTIME_STATE_MACHINE / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 5: `LEGACY_GENERIC_SHORT_CLASSIFIER_RUNTIME / IMPLEMENTATION_COMPLETE / WAITING_FOR_INDEPENDENT_WEB_AUDIT`

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

### Frozen audit basis before implementation

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

## Domain 5 implementation handoff identity

- Fresh start main: `683eb48d3e0edc4595fa6f61982c176c8675ddbb`.
- Immutable implementation HEAD: `e4c285ecbe2ad9a3a79e4dd2f01607857fdc4c37`.
- Branch/worktree: `codex/task045b-domain5-legacy-generic-short-classifier-retirement` / `remoteorbit-task045b-domain5-legacy-generic-short-classifier-retirement`.
- Draft PR: `#36`, base `main@683eb48d3e0edc4595fa6f61982c176c8675ddbb`.
- The live PR head is resolved from GitHub at audit time; this handoff records the immutable implementation HEAD and does not predeclare its own future SHA.
- Implementation-head durable CI: run `41271178228`, job `124744101031`, `RemoteOrbit CI`, runner `remoteorbit-macmini`, passed full Swift tests, Native Release build and Universal2 build-only packaging smoke.
- Local verification: focused retained voice/runtime/BLE/readiness/filter suites passed; full `swift test` passed 502/502; `git diff --check` passed; `swift build -c release` passed.
- Changed paths: `remote-orbit/Sources/RemoteOrbit/main.swift`, `remote-orbit/Sources/RemoteOrbit/VoiceReceiverReadiness.swift`, and directly affected retained voice/runtime tests under `remote-orbit/Tests/RemoteOrbitTests/`; deleted `remote-orbit/Tests/RemoteOrbitTests/DisabledShortClassifierTests.swift`.
- `AudioPipe.swift` is unchanged; no app install, driver/CoreAudio/TCC mutation, default-device mutation, tag/release, or merge was performed.
- `CURRENT_STATUS.md` and `CURRENT_TASK.md` are updated in one atomic handoff commit, which is a direct child of the implementation HEAD. Its SHA and the post-push CI identity must be resolved from the live branch/PR after publication.

## Next gate

Await independent Web exact-head source/CI/identity audit of the live PR head after the control handoff. No merge, Domain 6 mutation, app install, driver/CoreAudio/TCC mutation, tag/release, or machine-owned hardware acceptance is authorized.
