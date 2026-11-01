# RemoteOrbit Current Task

## RO-DIAGNOSTICS-LEGACY-RETIREMENT-045 — Wave B / Domain 1 Legacy Voice Product Surface

Status: `WAITING_FOR_INDEPENDENT_WEB_AUDIT`
TASK_CLASS: `BOUNDED LEGACY RETIREMENT`
Repository: `Lost0rz/RemoteOrbit`
Design authority: `docs/design/2026-11-01-045b-domain-1-legacy-voice-product-surface.md`
Human runtime/UI acceptance: `DEFERRED / USER-OWNED`

## Completed prerequisite

Task 045A diagnostics gating is closed:

- PR #31 merged as `27357a8e6301507b712ef65e9a74e973786dd263`;
- post-merge CI `41258162847` / job `124705656701` succeeded on `remoteorbit-macmini` through source contracts, protocol self-tests, full Swift tests, native Release build, and Universal2 packaging smoke.

## Domain execution rule

This legacy-retirement task is serial by domain. For each domain:

`Web audit/freeze → local cleanup → Web exact-head audit → merge/closeout → next domain`

The local executor must not re-audit or redesign this domain. Freshness/identity reconciliation is required; material conflict with current authority returns `AUTHORITY_RECONCILIATION_REQUIRED` rather than silently changing scope.

## Domain 1 purpose

Remove obsolete user-facing/configuration-surface semantics for Persistent session, Receiver B, and microphone SHORT behavior while preserving the current LONG-only product behavior and all legacy runtime/persistence internals for later dedicated audits.

## Authorized mutation

Domain 1 may modify only the product-surface/settings boundary and directly related tests/documentation:

- `remote-orbit/Sources/RemoteOrbit/KeyMapping/SettingsView.swift`
  - remove legacy Persistent-session Settings state/types/handlers/cards/messages;
  - remove Receiver-B Settings state/types/handlers/cards/messages/runtime bridge;
  - remove microphone-SHORT mode/configuration state/types/handlers/cards/messages;
  - keep the current direct-transfer microphone card and ordinary diagnostics/recording/mapping UI.
- `remote-orbit/Sources/RemoteOrbit/KeyMapping/SettingsWindow.swift`
  - remove constructor parameters/callbacks that exist only for the retired Settings controls.
- `remote-orbit/Sources/RemoteOrbit/main.swift`
  - remove only `openKeyMapping`/Settings bridge wiring whose sole consumer is the retired Settings surface;
  - keep underlying Persistent/Dual runtime methods, state, storage reads/writes, and tests untouched for later domains.
- `remote-orbit/Sources/RemoteOrbit/KeyMapping/KeymapOverlay.swift`
  - microphone presentation must no longer show any SHORT action or Persistent/Codex short semantics;
  - present the fixed production microphone behavior as LONG remote voice only.
- `remote-orbit/Sources/RemoteOrbit/KeyMapping/ButtonDefinitions.swift`
  - retain `ButtonBinding.voiceKeyDefault` as a Codable compatibility token;
  - remove stale user-facing Persistent wording/comments so it no longer claims SHORT toggles a session.
- focused tests may be changed/added only to prove this product-surface retirement boundary.
- `CURRENT_STATUS.md` and `CURRENT_TASK.md` are updated atomically at handoff.

If compilation proves a directly adjacent symbol is used exclusively by the retired Settings surface, it may be removed only when doing so does not enter persistence or runtime state-machine ownership. Otherwise leave it for the next domain and report it.

## Explicit KEEP boundary

Do not remove or redesign:

- `VoiceInputProfile` / `VoiceInputProfileStore`;
- selected profile persistence and normal direct voice-trigger reconfiguration;
- `ButtonBinding.voiceKeyDefault` enum/Codable token;
- mapping file schema or existing user mapping compatibility;
- `AppStorage.persistentSessionTriggerKey*`;
- `AppStorage.secondaryMomentaryVoiceTriggerKey*`;
- legacy momentary compatibility projection used by `VoiceInputProfileStore`;
- `VoiceSessionMode`, `PendingPersistentToggle`, `RemoteSegmentTriggerPolicy`;
- `DualReceiverVoiceGestureRecognizer`, `DualReceiverVoiceMode`, `DualReceiverMappedTriggerState`;
- Persistent/Dual runtime configuration/reconfiguration methods except Settings-only call-site wiring;
- Persistent/Dual runtime tests except a product-surface assertion that is directly obsolete because the UI/presentation was retired.

## Durable product boundary

Must remain unchanged:

- SHORT `<300 ms` = absolute user-visible no-op;
- LONG `>=300 ms` = direct remote voice lifecycle;
- repeated SHORT prefixes must not poison a final LONG;
- rapid LONG/release/LONG remains bounded;
- late mapped Option suppression/tombstone ownership remains;
- pre-HID physical candidate, BLE READY/reuse, AudioPipe ownership, output drain and post-release grace remain;
- diagnostics gating from Task 045A remains intact;
- recording remains independently controlled.

No BLE/ATVV, codec, gain, sample rate, AudioPipe transport/buffer/IOProc, HID mapping/readback correctness, receiver-readiness architecture, app installation, driver/CoreAudio/TCC, tag/release changes.

## Verification required

Focused evidence must prove at minimum:

1. Settings product source no longer contains/owns the legacy microphone Persistent/Receiver-B/SHORT configuration surface.
2. SettingsWindow/main no longer pass legacy Settings-only voice callbacks.
3. Keymap microphone presentation exposes no single-click/Persistent/Codex-short behavior and still exposes remote LONG voice.
4. `.voiceKeyDefault` remains decodable/encodable for existing mapping compatibility but has no stale Persistent user-facing label.
5. Existing `VoiceInputProfile` authority/migration tests stay green.
6. Current LONG-only regression, including `VoicePressCoordinatorTests`, stays green without weakening tests.

Then run:

- focused changed-boundary tests;
- full `swift test`;
- `swift build -c release`;
- durable `.github/workflows/remoteorbit-ci.yml` on `remoteorbit-macmini` for the final PR tree, including Universal2 build-only packaging smoke.

## Workspace / delivery

The active worktree/branch was created from fresh live `main` after reconciliation:

`codex/task045b-domain1-legacy-voice-product-surface`

Workspace: `/Volumes/Jack-Dev/Projects/remoteorbit-task045b-domain1-legacy-voice-product-surface`
Start HEAD: `03d130ab9129932e3b1dc9fabf818f87f56c8fd4`
Final HEAD: `9795719e403848b397c572a6072c43c76f95b888`
Remote branch HEAD: `9795719e403848b397c572a6072c43c76f95b888` (equal)

The already-merged Task 045A worktree may be retired only after confirming it is clean and fully merged; do not delete unknown/unmerged work.

Draft PR: `#32` (`https://github.com/Lost0rz/RemoteOrbit/pull/32`), open and Draft.
Durable CI: run `41259237157`, job `124708848980`, `success` on
`remoteorbit-macmini`; Universal2 build-only packaging smoke passed.
The 045A predecessor worktree was retired after a clean/merged check; its branch
was retained.

## Stop

After implementation, tests, push, Draft PR, durable CI, and this atomic control handoff, stop at:

`WAITING_FOR_INDEPENDENT_WEB_AUDIT`

Do not start Domain 2. Do not install the app or mutate driver/CoreAudio/TCC. Return actual branch/worktree/head, changed paths, compatibility decisions, tests/CI, remote-head equality, and unresolved uncertainty.
