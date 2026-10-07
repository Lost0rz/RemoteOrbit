# RemoteOrbit Current Task

## Current task — RO-INCIDENT-20261004-01 / DISABLED-SHORT CLASSIFIER MINIMAL REGRESSION FIX

- **Status:** ACTIVE / NARROW PRODUCT FIX CANDIDATE AUTHORIZED
- **Incident ID:** `RO-INCIDENT-20261004-01`
- **Control parent before task authorization:** `4cf70339b9f8243b07b13b70cdbb336bf38dcdad`
- **Authorized branch:** `codex/disabled-short-classifier-regression-fix`
- **Planned worktree:** `/private/tmp/remoteorbit-disabled-short-classifier-regression-fix`
- **Product Construction Gate:** OPEN ONLY FOR THIS EXACT CLASSIFIER CORRECTIVE
- **Install/runtime replacement:** NOT AUTHORIZED
- **User hardware reproduction:** NOT AUTHORIZED before independent Web audit

## Objective

Restore the previously hardware-validated Disabled-SHORT semantic without changing the accepted physical/system-mapped trigger architecture:

> When microphone SHORT is Disabled, a quick press must still remain inside the normal ~300 ms SHORT/LONG classifier and be dropped as a disabled SHORT. Only a true hold crossing the existing threshold may enter the remote-microphone HOLD path.

This task does **not** claim that the exact external Doubao event mechanism is already known. It tests the confirmed PR #14 semantic regression as the smallest behavior candidate for the current user-visible symptom.

## Evidence basis

### Historical good contract

- PR #6 / `80ec3adfe065eac90547f7a76c58f0b510c639b9`: Disabled SHORT does not bypass classifier.
- Accepted PR #7 selectively incorporated this corrective.
- Historical hardware acceptance: Disabled SHORT 20/20 without BLE/audio start; Disabled LONG 10/10 entered holding/BLE.
- Accepted production architecture retained physical/system-mapped Option as normal owner; synthetic normal-owner architecture was not adopted.

### Regression

- PR #14 / `346b064de1c320c84706ecd590aa952cfe473da6`, merged as `924a8d3a26d213552fe9b42c9bb5e3bf31755a25`, changed `bypassesShortClassification(for:)` from always false to `binding.isDisabled`.
- Current main still has:

```swift
static func bypassesShortClassification(for binding: ButtonBinding) -> Bool {
    binding.isDisabled
}
```

- Current `VoicePressCoordinator` immediately logs HOLD and enters `holding` when that bypass is true.
- Current `DisabledShortClassifierTests` explicitly encode this PR #14 behavior.

### Current sealed runtime evidence

```text
WINDOW: 2026-10-07 18:59:41–19:06:46 +08:00
SEQ: 4437–4779
GESTURE_COUNT: 16
BYPASS_TRUE_COUNT: 16
GESTURE_RESULT_HOLD_COUNT: 16
SESSION_MODE_IDLE_COUNT: 16
MAPPED_TRIGGER_EVENT_COUNT: 0
SYNTHETIC_TRIGGER_EDGE_COUNT: 0
```

User-visible fact: with SHORT Disabled, a fast click can nevertheless visibly open a Doubao Session.

## Gate 0 — exact authority and clean isolation

1. `git fetch origin --prune`.
2. Verify live `origin/main` equals the control HEAD containing this task. The executor must print the exact SHA before creating any branch/worktree.
3. Verify canonical remote is `Lost0rz/RemoteOrbit`.
4. Do not use, clean, reset, stash or repair the historical dirty/superseded canonical checkout.
5. Create or reuse only:
   - branch: `codex/disabled-short-classifier-regression-fix`
   - worktree: `/private/tmp/remoteorbit-disabled-short-classifier-regression-fix`
6. The authorized branch must start exactly from the current control HEAD and the worktree must be clean.
7. Read `AGENTS.md`, `CURRENT_STATUS.md`, and `CURRENT_TASK.md` from that exact HEAD.

Any ref mismatch, dirty authorized worktree, unexpected branch ancestry or fetch failure => STOP without product mutation.

## Gate 1 — baseline read-only confirmation

Before editing, confirm on the authorized baseline:

1. `AppController.bypassesShortClassification(for: .preset(.disabled))` currently evaluates to true by implementation.
2. `VoicePressCoordinator` immediately enters HOLD when `bypassesShortClassification == true`.
3. `DisabledShortClassifierTests.swift` currently asserts the PR #14 immediate-HOLD behavior.
4. No source change after PR #14 already restores the historical Disabled-SHORT classifier contract.

Return these facts in the final evidence report; do not broaden source audit beyond what is needed for this candidate.

## Gate 2 — RED tests first

Modify the existing Disabled-SHORT test contract **before** product implementation so it describes the intended restored behavior.

Required focused assertions, adapted to current APIs without restructuring unrelated code:

1. `testDisabledShortBindingDoesNotBypassClassifier`
   - `.preset(.disabled)` => `bypassesShortClassification == false`.

2. Disabled quick release test
   - keyDown with Disabled semantics enters `.pending`, not `.holding`;
   - release before the threshold returns `.idle`;
   - configured short action is not executed as a product action;
   - HOLD/remote-route activation is not observed;
   - no synthetic trigger edge is emitted by the test seam.

3. Disabled true-long test
   - before the threshold: remains `.pending`;
   - after crossing the existing `holdActivationThreshold`: enters `.holding` exactly once;
   - existing remote route preparation occurs exactly once after promotion;
   - do not change the threshold value.

4. Existing `.voiceKeyDefault` short/long classifier behavior remains pending/classified as before.

Run only the focused Disabled-SHORT test target and prove RED against the current product implementation. RED must be caused by the current PR #14 bypass behavior, not compilation errors or unrelated failures.

If a valid RED cannot be established, STOP and report why.

## Gate 3 — minimal GREEN implementation

Authorized product change:

- `remote-orbit/Sources/RemoteOrbit/main.swift`

Implement the smallest current-code equivalent of the historical good contract:

```text
Disabled SHORT must not bypass the short/long classifier.
```

Expected shape: `bypassesShortClassification(for:)` must return false for Disabled as well as the existing non-disabled bindings.

Do not cherry-pick historical source wholesale. Do not revert PR #14 wholesale. Do not modify the 300 ms threshold.

Preserve the current `preparesRemoteTransport` plumbing unless a focused test proves it must change for the restored contract. In particular, pending transport preparation may remain transport-only; this task must not authorize micOpen/audio/trigger emission before true HOLD promotion.

## Strict source boundary

Authorized product source path:

```text
remote-orbit/Sources/RemoteOrbit/main.swift
```

Authorized primary test path:

```text
remote-orbit/Tests/RemoteOrbitTests/DisabledShortClassifierTests.swift
```

A second existing test file may be touched only if required to express a current public/test seam that directly verifies this same classifier boundary. If that happens, report the exact reason before claiming completion.

Forbidden product changes:

- `RemoteVoiceKeyMapping` / hidutil mapping behavior;
- F5/source HID mapping redesign;
- `VoiceKeyFilter` behavior;
- `HardwareOptionGate` behavior;
- physical/system-mapped trigger ownership;
- synthetic trigger architecture;
- BLEBridge or AudioPipe behavior;
- Persistent Session state semantics;
- trigger-key selection semantics;
- settings/UI behavior;
- diagnostic schema/authority expansion;
- timing constants;
- driver/CoreAudio/TCC/Input Monitoring/Accessibility changes.

No opportunistic cleanup or refactor.

## Gate 4 — focused validation

After GREEN:

1. Run `DisabledShortClassifierTests` and require PASS.
2. Run the smallest existing focused suites covering current persistent-session and trigger runtime semantics. Prefer existing test files; do not add new diagnostics solely for this task.
3. Explicitly verify tests still cover:
   - `.voiceKeyDefault` SHORT behavior unchanged;
   - persistent SHORT classification unchanged;
   - persistent LONG remains audio-only once `persistent_open`;
   - physical/system-mapped trigger path remains the normal production path.

If any focused test fails, STOP. Do not widen the code fix until Web audits the failure.

## Gate 5 — full validation

Run:

1. full Swift test suite;
2. repository self-tests if currently required by `AGENTS.md` / existing project workflow;
3. release build;
4. `git diff --check`;
5. scope audit proving only authorized source/test/control paths changed.

No runtime installation and no user hardware interaction in this task.

## Gate 6 — commit, push, handoff

If all validation passes:

1. commit the minimal candidate on `codex/disabled-short-classifier-regression-fix`;
2. push the branch;
3. verify local HEAD == remote branch HEAD;
4. require clean worktree;
5. do **not** merge;
6. do **not** install;
7. stop for Web independent audit.

## Required completion report

Return exactly the important evidence needed for Web review:

```text
TASK_ID: RO-DISABLED-SHORT-CLASSIFIER-REGRESSION-FIX-001
CONTROL_HEAD:
AUTHORIZED_BRANCH: codex/disabled-short-classifier-regression-fix
WORKTREE: /private/tmp/remoteorbit-disabled-short-classifier-regression-fix
BASELINE_GATE:
WORKTREE_CLEAN_START:

BASELINE_BYPASS_DISABLED:
BASELINE_IMMEDIATE_HOLD_TEST_PRESENT:

RED_TEST_COMMAND:
RED_RESULT:
RED_FAILURES_EXPECTED:

IMPLEMENTATION_SUMMARY:
CHANGED_PATHS:
BYPASS_DISABLED_AFTER_FIX:
HOLD_THRESHOLD_CHANGED: NO
HARDWARE_OPTION_PATH_CHANGED: NO
BLE_AUDIO_PATH_CHANGED: NO
PERSISTENT_SESSION_SEMANTICS_CHANGED: NO

FOCUSED_DISABLED_TESTS:
FOCUSED_PERSISTENT_TRIGGER_TESTS:
FULL_SWIFT_TEST:
SELF_TESTS:
RELEASE_BUILD:
DIFF_CHECK:
SCOPE_AUDIT:

USER_REPRODUCTION_PERFORMED: NO
RUNTIME_INSTALLED: NO

FINAL_HEAD:
REMOTE_HEAD:
LOCAL_REMOTE_MATCH:
FINAL_WORKTREE_CLEAN:
FINAL_STATE: WAITING_FOR_INDEPENDENT_WEB_MINIMAL_FIX_AUDIT
```

## Web acceptance boundary

Web will independently inspect the exact branch diff and returned test evidence. Only after Web explicitly accepts the candidate may the installed runtime be replaced for one controlled hardware acceptance:

```text
SHORT Disabled + fast click → Doubao Session must not open
SHORT Disabled + true LONG → remote voice must still start after classifier threshold
```

If the first condition still fails, do not expand this patch. Resume the paused B4 external event-plane investigation with the remaining external mechanism classified unresolved.
