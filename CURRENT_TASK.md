# RemoteOrbit Current Task

## RO-DIAGNOSTICS-LEGACY-RETIREMENT-045 — Wave B / Domain 4 Dual Receiver Runtime State Machine

Status: `READY_FOR_IMPLEMENTATION_HANDOFF`
TASK_CLASS: `BOUNDED LEGACY RETIREMENT`
Repository: `Lost0rz/RemoteOrbit`
Design authority: `docs/design/2026-11-01-045b-domain-4-dual-receiver-runtime-retirement.md`
Human runtime/UI acceptance: `PENDING / USER-OWNED`

## Completed prerequisite

Domain 3 is accepted and closed:

- PR #34 independent exact-head audit: PASS (`FRESH_CONTEXT`) after control-plane identity reconciliation;
- final reconciled PR head: `ccc32f605da81fb9874f831677cd969d30058a22`;
- exact-head durable PR CI `41263839832` / job `124722386420` passed on `remoteorbit-macmini`;
- merged as `e8118342f43154a6b2a93cd70b679f4ef52f366b` using exact expected head;
- post-merge main CI `41264568492` / job `124724579093` passed every durable stage including Universal2 packaging.

## Domain execution rule

Legacy retirement remains serial:

`Web audit/freeze → local cleanup → Web exact-head audit → merge/closeout → next domain`

Domain 4 has already been audited and designed by Web. Local execution performs freshness/identity reconciliation, implementation and verification only. Do not redo the domain audit or choose a different retirement boundary. If live facts materially conflict with this authority, stop with `AUTHORITY_RECONCILIATION_REQUIRED`.

## Domain 4 purpose

Remove the obsolete Dual Receiver A/B voice runtime, Receiver-B runtime state, secondary-mapping transaction and Dual-only coordinator seams. Preserve the current single-profile primary mapping authority, Gate-A LONG-only product behavior and all shared correctness mechanisms.

## Authorized mutation

### Standalone Dual sources

Delete:

- `remote-orbit/Sources/RemoteOrbit/DualReceiverVoiceMode.swift`
- `remote-orbit/Sources/RemoteOrbit/DualReceiverVoiceGestureRecognizer.swift`
- `remote-orbit/Sources/RemoteOrbit/DualReceiverMappedTriggerState.swift`

### `remote-orbit/Sources/RemoteOrbit/main.swift`

Retire Dual-only AppController/runtime ownership where present:

- `dualReceiverVoiceGestureRecognizer` / `dualReceiverVoiceMode`;
- `currentSecondaryMomentaryVoiceTriggerKey` / `initialSecondaryMomentaryVoiceTriggerKey` runtime-only Receiver-B seam;
- `currentDualReceiverShortBinding`;
- `dualReceiverMappedTriggerState` and generation/phase state;
- Dual reconfiguration/mapping gates;
- Dual prewarm, physical-down and active-gesture state;
- `configureDualReceiverVoiceMode(...)`;
- `applySecondaryVoiceTriggerKey(...)`;
- `handleDualReceiverMicrophoneEdge(...)` and its event-dispatch/orchestration;
- secondary B mapping arm and primary A mapping restore;
- Dual-specific HID-removal/BLE-loss cleanup and diagnostics;
- directly adjacent helpers whose only caller is that Dual transaction.

Retain the selected-profile primary mapping/readback authority. Do not remove `RemoteVoiceKeyMapping` merely because the Dual transaction also used it.

### VoicePressCoordinator boundary in `main.swift`

Retire only Dual-specific classified ownership proven to have no retained non-Dual caller, including where applicable:

- `classifiedDualReceiverHold`;
- `classifiedDualReceiverTriggerKey`;
- `prearmedDualReceiverHardwareGateSessionID`;
- `beginClassifiedHardwareGate(...)`;
- `beginClassifiedHardwareHold(...)`;
- `cancelClassifiedHardwareGate(...)`;
- Dual-only classified trigger/output-drain branches;
- Dual-only `PendingRepress` fields if no retained caller remains.

Do not broadly remove `VoicePressCoordinator.State`, generic pending/holding/drain behavior, or generic legacy classifier/local-microphone seams in this domain.

### `remote-orbit/Sources/RemoteOrbit/KeyMapping/HIDMonitor.swift`

After removing `DualReceiverVoiceMode`, simplify `HIDButtonDownPolicy.resolve(...)` to remove the Dual-mode parameter and active-Dual microphone exception while preserving:

- generic repeat behavior;
- advanced-gesture behavior for non-microphone buttons;
- microphone no-debounce behavior when a live physical candidate exists.

Update all retained callers/tests accordingly. This is a compile/authority cleanup, not permission to redesign input policy.

### Tests

Dedicated Dual suites may be deleted after checking for still-live generic claims:

- `DualReceiverVoiceGestureRecognizerTests.swift`
- `DualReceiverVoiceModeTests.swift`
- `DualReceiverVoiceSettingsTests.swift`
- `DualReceiverVoiceTransactionTests.swift`

Remove Dual-only cases/harness fields from directly affected suites such as:

- `VoiceTriggerRuntimeTests.swift`;
- `HIDButtonDownPolicyTests.swift`;
- any other test whose only contract is Receiver-B / A↔B transaction behavior.

If a deleted Dual test contains a generic assertion still relevant to the current product and not already strongly covered, rehome that assertion to an appropriate retained suite. Do not retain dead Dual tests solely to preserve test count.

### Control files

After implementation/test/CI evidence is available, atomically update `CURRENT_STATUS.md` and `CURRENT_TASK.md` in one final handoff commit.

## Explicit KEEP boundary

Do not delete, redesign or weaken:

- `VoiceInputProfile` / `VoiceInputProfileStore` and profile ID persistence;
- `.voiceKeyDefault` Codable compatibility and mapping schema;
- primary `RemoteVoiceKeyMapping`, hidutil apply and mapping readback verification;
- Gate-A private LONG candidate and direct session lifecycle;
- SHORT `<300 ms` absolute user-visible no-op;
- LONG `>=300 ms` direct remote voice lifecycle;
- `holdActivationThreshold == 0.30` where retained/current;
- repeated SHORT-prefix→LONG recovery;
- rapid LONG/release/LONG and pending direct repress ownership;
- short-discard tombstone ownership;
- late mapped Option down/up/flags suppression;
- LONG-only suppression handoff;
- hardware Option deferral/replay/held-UP acknowledgement;
- synthetic fallback;
- pre-HID physical candidate;
- output drain, tail/grace;
- BLE READY/reuse, ATVV, codec, gain/sample-rate and AudioPipe transport/buffer/IOProc;
- EventSuppressor and generic HardwareOptionGate ownership;
- receiver readiness architecture;
- Task 045A diagnostics gate and independent recording control;
- generic non-Dual legacy short-action/local-microphone classifier seams, except compile-only removal of a field/call proven exclusively Dual-owned.

Historical helper names do not classify ownership. In particular do not remove a lower-level short/audio-only-named suppression primitive if current LONG-only code still calls it.

## Explicit non-goals

Do not:

- start Domain 5;
- clean every remaining legacy classifier/local-mic seam;
- cosmetically rename shared suppression/tombstone primitives;
- change the current 300 ms voice contract;
- alter primary mapping semantics or readback correctness;
- change BLE/ATVV, AudioPipe, codec, sample rate or gain;
- install/replace the app;
- mutate driver/CoreAudio/TCC/default audio devices;
- tag/release;
- merge the Domain 4 PR locally.

## Verification required

Focused evidence must prove at minimum:

1. all three standalone `DualReceiver*.swift` production sources are absent;
2. AppController contains no Dual mode/recognizer/mapped-state/Receiver-B runtime or A↔B mapping transaction;
3. VoicePressCoordinator contains no Dual-only classified gate/hold ownership;
4. `HIDButtonDownPolicy` no longer depends on Dual mode and retained generic/live-candidate policy tests pass;
5. selected-profile primary mapping and mapping readback tests remain green;
6. current LONG-only regression remains green, including bounded SHORT discard, repeated SHORT prefix→LONG, late mapped-edge suppression, rapid repress, synthetic fallback, transport loss and normal release/output drain;
7. Task 045A diagnostics gating and recording independence remain green;
8. BLE/AudioPipe/receiver-readiness relevant regression remains green;
9. no product code or test harness references deleted Dual symbols except historical docs/string fixtures intentionally preserved.

Then run:

- focused changed-boundary tests;
- full `swift test`;
- `swift build -c release`;
- `git diff --check`;
- durable `.github/workflows/remoteorbit-ci.yml` on `remoteorbit-macmini`;
- Universal2 build-only packaging smoke.

## Workspace / delivery

Start from fresh live `main` after reconciliation. Use one fresh worktree/branch, suggested:

`codex/task045b-domain4-dual-receiver-runtime-retirement`

The merged Domain 3 worktree may be retired only after confirming clean state and merged ancestry. Preserve its branch/history unless separately authorized.

Create one Draft PR. Do not merge locally.

## Stop

After implementation, verification, push, Draft PR, durable CI and atomic control handoff, stop at:

`WAITING_FOR_INDEPENDENT_WEB_AUDIT`

Do not start Domain 5. Do not install the app or mutate driver/CoreAudio/TCC.

Return actual governance route, start main, branch/worktree, implementation/final heads, remote equality, Draft PR, changed/deleted paths, retired Dual surface, preserved primary/LONG-only mechanisms, deleted/rehomed tests, focused/full/build/diff/CI/package results, predecessor-worktree disposition, scope-mutation flags, unresolved uncertainty, `HUMAN_UI_ACCEPTANCE`, and final actual state.
