# RemoteOrbit Current Task

## RO-DIAGNOSTICS-LEGACY-RETIREMENT-045 — Wave B / Domain 5 Legacy Generic Short Classifier Runtime

Status: `WAITING_FOR_INDEPENDENT_WEB_AUDIT`
TASK_CLASS: `BOUNDED LEGACY RETIREMENT`
Repository: `Lost0rz/RemoteOrbit`
Design authority: `docs/design/2026-11-01-045b-domain-5-legacy-generic-short-classifier-retirement.md`
Human runtime/UI acceptance: `PENDING / USER-OWNED`

## Implementation handoff identity

- Fresh start main: `683eb48d3e0edc4595fa6f61982c176c8675ddbb`.
- Immutable implementation HEAD: `e4c285ecbe2ad9a3a79e4dd2f01607857fdc4c37`.
- Branch/worktree: `codex/task045b-domain5-legacy-generic-short-classifier-retirement` / `remoteorbit-task045b-domain5-legacy-generic-short-classifier-retirement`.
- Draft PR: `#36`; live PR head must be resolved from GitHub at audit time.
- Implementation-head durable CI: `41271178228` / job `124744101031` / `remoteorbit-macmini` / PASS, including Universal2 build-only packaging smoke.
- Local: focused retained voice/runtime/BLE/readiness/filter suites PASS, full `swift test` PASS (502/502), Release build PASS, and `git diff --check` PASS.
- The implementation changed only the Domain 5 coordinator/AppController/readiness surface and directly affected tests; `AudioPipe.swift` is unchanged. The obsolete `DisabledShortClassifierTests.swift` was deleted.
- This control handoff is one atomic commit directly after the implementation HEAD. Do not encode its own future SHA here; resolve the live PR head and post-push CI directly from GitHub.
- Final state: `WAITING_FOR_INDEPENDENT_WEB_AUDIT`.

## Completed prerequisite

Domain 4 is accepted and closed:

- PR #35 independent exact-head audit: PASS (`FRESH_CONTEXT`) after the primary-runtime test corrective;
- final reviewed PR head: `aaa4ff238b826da55e80f0ff9d8708c80f10f4b7`;
- exact-head durable PR CI `41267602388` / job `124733560093` passed on `remoteorbit-macmini`;
- merged as `fa49bb4fe38fd87a7ed36ab7bccfcfe2259434c6` using exact expected head;
- post-merge main CI `41268164507` / job `124735221877` passed every durable stage including Universal2 packaging.

## Domain execution rule

Legacy retirement remains serial:

`Web audit/freeze → local cleanup → Web exact-head audit → merge/closeout → next domain`

Domain 5 has already been audited and designed by Web. Local execution performs freshness/identity reconciliation, implementation and verification only. Do not redo the domain audit or choose a different retirement boundary. If live facts materially conflict with this authority, stop with `AUTHORITY_RECONCILIATION_REQUIRED`.

## Domain 5 purpose

Remove the obsolete generic non-direct SHORT/LONG classifier runtime and its local-microphone short-action caller plumbing. Preserve the production Gate-A direct LONG-only path and every shared correctness mechanism. Do not retire the separate AudioPipe local-microphone implementation in this domain.

## Authorized mutation

### `remote-orbit/Sources/RemoteOrbit/main.swift`

Retire the legacy non-direct classifier surface where ownership is proven legacy-only, including as applicable:

- `VoicePressCoordinator.State.pending` / `.holding`;
- non-direct `keyDown(...)` branch and legacy-only parameters such as short callback/local-microphone/bypass flags;
- legacy `startAcceptedVoicePress(...)`, hold timer/promotion, legacy long-input and tail-work-item lifecycle;
- short callback state, local-microphone short-request state, pending-short preparation state and release-bounce-only state;
- legacy-only `PendingRepress` payload fields and activation path while preserving direct pending-repress ownership;
- legacy remote-output-drain/tail fields and helpers proven not used by the direct path;
- test-only accessors that exist only for retired legacy state;
- AppController `beginVoicePress(...)` dead `shortBinding` parameter;
- `handleVoiceShortTap(...)`, `bypassesShortClassification(for:)`, `usesLocalMicrophone(forShortBinding:)`, and adjacent helpers with no retained caller;
- state callback/HUD plumbing that refers only to `.pending` / `.holding`.

The retained public/coordinator entry should represent the current Gate-A LONG-only authority rather than preserving boolean switches for dead modes. Behavior-neutral signature simplification is authorized when all production callers already use the same direct LONG-only mode.

### `remote-orbit/Sources/RemoteOrbit/VoiceReceiverReadiness.swift`

Update `VoiceHUDProjection` only as required by removal of `.pending` / `.holding`. Preserve the current semantics for `.idle`, `.opening`, `.streaming`, and `.draining`; do not redesign receiver readiness.

### Tests

Delete `remote-orbit/Tests/RemoteOrbitTests/DisabledShortClassifierTests.swift` after confirming it remains entirely obsolete classifier coverage.

In mixed suites such as `VoicePressCoordinatorTests.swift`:

- remove only tests whose contract is the retired non-direct `.pending` / `.holding` classifier, legacy tail-work-item path, or legacy short/local-mic callback;
- preserve all current direct LONG-only, candidate, rapid-repress, tombstone/suppression, transport-loss and output-drain assertions;
- if a removed legacy test contains a still-current generic claim not strongly covered elsewhere, rehome that claim before deletion.

Update `VoiceReceiverReadinessTests.swift` only for the removed state cases; keep current opening/streaming/draining and receiver-listening assertions.

Adjust other tests only when they directly reference the retired classifier API/state. Do not delete tests solely to reduce count.

### Explicit Domain 6 freeze

Do NOT modify `remote-orbit/Sources/RemoteOrbit/AudioPipe.swift` local/external microphone capture implementation in Domain 5, including:

- `localMicrophoneCaptureRequested`;
- microphone permission/request state;
- `setLocalMicrophoneCaptureEnabled(...)`;
- AVCapture session/delegate path;
- start/stop local microphone helpers;
- local microphone scheduling/counters.

Domain 5 may remove dead callers from `main.swift`. The implementation itself is a separate Domain 6 audit/retirement boundary.

## Explicit KEEP boundary

Do not delete, redesign or weaken:

- production Gate-A long-only candidate and timer;
- `holdActivationThreshold == 0.30`;
- SHORT `<300 ms` absolute user-visible no-op and LONG `>=300 ms` direct voice contract;
- direct `.opening` / `.streaming` / `.draining` session lifecycle;
- direct rapid LONG/release/LONG and pending direct hardware/synthetic repress ownership;
- long-only candidate previous-owner handoff;
- short-discard tombstone ownership;
- late mapped Option down/up/flags suppression;
- LONG-only suppression handoff;
- hardware Option deferral/replay/held-UP acknowledgement;
- synthetic fallback;
- pre-HID physical candidate;
- BLE READY/reuse, ATVV, AudioPipe remote transport/buffer/IOProc;
- direct output drain, tail/grace and transport-loss behavior;
- `VoicePressCoordinator.tailDrainDelay` while its live VoiceKeyFilter suppression quiet-period caller exists;
- `VoiceKeyFilter` / EventSuppressor / generic HardwareOptionGate live primitives;
- selected `VoiceInputProfile` / `VoiceInputProfileStore` and primary `RemoteVoiceKeyMapping` authority;
- `PrimaryVoiceRuntimeTests.swift` current runtime coverage;
- receiver readiness architecture apart from compile-only state-projection cleanup;
- Task 045A diagnostics gate and independent recording control.

Historical names are not ownership proof. In particular do not delete `ShortTap`, `AudioOnly`, or tail-named lower-level primitives if current LONG-only/suppression callers remain.

## Explicit non-goals

Do not:

- start Domain 6 or delete the AudioPipe local-microphone implementation;
- rename live suppression/tombstone primitives for cosmetics;
- change 300 ms semantics;
- change primary mapping/profile semantics;
- change BLE/ATVV, codec, gain, sample rate, prebuffer, IOProc or receiver-readiness architecture;
- install/replace the app;
- mutate driver/CoreAudio/TCC/default audio devices;
- tag/release;
- merge the Domain 5 PR locally.

## Verification required

Focused evidence must prove at minimum:

1. production voice entry no longer exposes a dead `shortBinding`/classifier selection surface;
2. coordinator has no `.pending` / `.holding` state or non-direct generic classifier path;
3. no product caller remains for `handleVoiceShortTap`, classifier bypass helper, or local-mic short helper;
4. direct rapid-repress `PendingRepress` ownership remains and no legacy-only payload is required;
5. current LONG-only candidate, 300 ms threshold, repeated SHORT-prefix→LONG, mapped-edge suppression/tombstone handoff, synthetic fallback, rapid repress, transport loss and output drain remain green;
6. primary runtime/profile/mapping tests remain green;
7. receiver readiness/HUD tests remain green for current states;
8. diagnostics gating, recording independence, BLE/AudioPipe remote path and readiness regressions remain green;
9. `AudioPipe.swift` local-microphone implementation is unchanged in this domain;
10. `tailDrainDelay` or equivalent live suppression quiet-period behavior is preserved.

Then run:

- focused changed-boundary tests;
- full `swift test`;
- `swift build -c release`;
- `git diff --check`;
- durable `.github/workflows/remoteorbit-ci.yml` on `remoteorbit-macmini`;
- Universal2 build-only packaging smoke.

## Workspace / delivery

Start from fresh live `main` after reconciliation. Use one fresh worktree/branch, suggested:

`codex/task045b-domain5-legacy-generic-short-classifier-retirement`

The merged Domain 4 worktree may be retired only after confirming clean state and merged ancestry. Preserve its branch/history unless separately authorized.

Create one Draft PR. Do not merge locally.

### Control files

After implementation/test/CI evidence is available, atomically update `CURRENT_STATUS.md` and `CURRENT_TASK.md` in one final handoff commit. Do not encode the control commit's own future SHA; resolve final PR head and post-push CI from GitHub at audit time.

## Stop

After implementation, verification, push, Draft PR, durable CI and atomic control handoff, stop at:

`WAITING_FOR_INDEPENDENT_WEB_AUDIT`

Do not start Domain 6. Do not install the app or mutate driver/CoreAudio/TCC.

Return actual governance route/capability, execution topology/subagents, start main, branch/worktree, implementation/final heads, remote equality, Draft PR, changed/deleted paths, retired classifier surface, preserved direct LONG-only surface, legacy tests deleted/pruned/re-homed, focused/full/build/diff/CI/package results, Domain 4 worktree disposition, scope-mutation flags, unresolved uncertainty, `HUMAN_UI_ACCEPTANCE`, and final actual state.
