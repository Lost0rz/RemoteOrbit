# RemoteOrbit Current Task

## Current task — DUAL-RECEIVER MOMENTARY ROUTING IMPLEMENTATION THROUGH EARLY HARDWARE GATE

- **Status:** WAITING FOR USER EARLY HARDWARE ACCEPTANCE
- **Task ID:** `RO-DUAL-RECEIVER-MOMENTARY-ROUTING-019`
- **Previous task:** `RO-DUAL-RECEIVER-MOMENTARY-ROUTING-018` — IMPLEMENTATION PLAN AUDITED
- **Design spec:** `docs/superpowers/specs/2026-10-08-dual-receiver-momentary-voice-routing-design.md`
- **Implementation plan:** `docs/superpowers/plans/2026-10-08-dual-receiver-momentary-routing.md`
- **Audited plan HEAD:** `6415c6baccae75b220391568d77b546c5cbbefe8`
- **Classifier corrective source:** `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`
- **Authorized branch:** `codex/dual-receiver-momentary-routing-v1`
- **Authorized worktree:** `/private/tmp/remoteorbit-dual-receiver-momentary-routing-v1`
- **Merge:** FORBIDDEN

## Gate 10 completed — stop for user acceptance

Implementation source HEAD `ef29186e25c64cd4d1d7209cb2a41f95c51d4a11` passed the required focused suites, full Swift suite (355 tests), project self-tests, release build, and diff check. Its pushed remote branch matched before runtime replacement.

The exact candidate is installed at `/Applications/RemoteOrbit.app` and running as PID `46412`:

```text
Source marker: ef29186e25c64cd4d1d7209cb2a41f95c51d4a11
Executable SHA-256: 328e66f7d60fbf7c5a5f8330d32ecb133bf34c00e3ae1fb065e70633835734bb
Version/build: 0.2.13 / 42
Bundle ID: com.lost0rz.RemoteOrbit
Code identity: Ad Hoc; designated requirement identifier com.lost0rz.RemoteOrbit
```

Current settings: Receiver A=`left_option`; Receiver B=`Off` because its independent preference is absent; Persistent=`left_option`; effective global and Codex microphone SHORT binding=`Disabled`. With B Off, the app remains in legacy single-receiver mode and the device F5-to-Left-Option mapping remains present. The executor made no receiver-shortcut changes. The user must choose a distinct Receiver B key in RemoteOrbit settings before exercising B routing.

The existing app was gracefully quit before replacement; no driver, CoreAudio, LaunchAgent, TCC, Accessibility, or Input Monitoring change was made. `open -a` returned Launch Services `kLSNoExecutableErr`; the verified installed bundle executable was launched directly and its process identity was verified. Stop here for user-operated early hardware acceptance. Do not execute Tasks 11 or 12.

## Product contract

```text
Direct LONG                   -> Receiver A
Quick first tap + second LONG -> Receiver B
Quick single tap              -> no action

A initial key = Left Option
B initial key = Right Option
LONG = 350 ms
DOUBLE WINDOW = 300 ms
```

Dual mode uses independent momentary transactions only. Persistent Session is not receiver authority.

## Mandatory Web audit amendments to the plan

These requirements override any ambiguous implementation reading of the audited plan.

### Amendment A — no second long-press classifier

The new voice-specific classifier is the sole semantic classifier in dual mode.

When it resolves A or B, enter the existing voice transaction lifecycle via an explicit already-classified hold API/seam. Do not feed the classified press back through the legacy 300 ms `VoicePressCoordinator.keyDown` classifier.

Required regression:

```text
classification at ~350 ms
-> transaction activation begins immediately from classified-hold entry
-> no additional ~300 ms wait
```

Legacy single-receiver behavior remains unchanged.

### Amendment B — mapping clear must succeed before dual activation

Entering dual mode requires the device-scoped F5 receiver mapping clear operation to succeed through the runtime mapping seam.

A clear failure must produce:

```text
DUAL_MODE_UNAVAILABLE
BLE_ACTIVATION = 0
A_TRIGGER = 0
B_TRIGGER = 0
RAW_F5_FALLBACK = 0
```

Do not rely solely on cached/in-memory `RemoteVoiceKeyMapping.isEnabled` after a failed command. Do not restore pre-classification receiver mapping as fallback.

## Gate 0 — freshness, isolated workspace, preserve existing local dirt

1. `git fetch origin --prune`.
2. Read latest `AGENTS.md`, `CURRENT_STATUS.md`, this task, design spec, and implementation plan from authoritative `origin/main`.
3. Verify canonical remote identity.
4. Verify the current `origin/main` is the implementation authority supplied by Web. A docs/control-only successor is acceptable only if task ID, contract, plan and authorization are unchanged; otherwise STOP and reconcile.
5. Inspect `git worktree list` and the reported existing canonical checkout read-only.
6. If the canonical checkout still has a pre-existing dirty `HIDMonitor.swift`, record path/status/hash/diff metadata read-only. Do NOT clean, stash, reset, checkout, copy from, or overwrite it.
7. The only implementation workspace is `/private/tmp/remoteorbit-dual-receiver-momentary-routing-v1`. Recreate/rebind it from current authoritative `origin/main` only if necessary and only without touching unrelated worktrees.
8. Worktree must be clean before product mutation.

## Gate 1 — adopt only the accepted classifier corrective

Follow implementation-plan Task 1 exactly, with one stricter rule: do not replace whole current-main files blindly.

Use candidate HEAD `172427957fd18a2b5827edd1cb1c4bddb6a5b7db` only as the source of the accepted Disabled-SHORT behavior/test hunks.

Required RED then GREEN:

```sh
swift test --package-path remote-orbit --filter DisabledShortClassifierTests
swift test --package-path remote-orbit --filter VoicePressCoordinatorTests
```

After GREEN, prove the baseline corrective diff is limited to the accepted classifier behavior/test and commit it separately.

STOP on unrelated candidate overwrite or broader behavior change.

## Gates 2-9 — execute audited plan with TDD

Execute plan Tasks 2 through 9 in order. Use RED -> smallest GREEN -> focused regressions -> coherent commit for each task.

Required boundaries remain:

- pure `DualReceiverVoiceGestureRecognizer`, fake scheduler/monotonic timing, no sleeps;
- generic `ButtonGestureRecognizer` unchanged;
- single `VoiceOptionTrigger` owner with explicit transaction key;
- no receiver hidutil mapping before dual classification;
- existing `HIDMonitor` + one existing `EventSuppressor` only;
- mapping-clear failure fail-closed per Amendment B;
- first DOWN/pre-second-window may only prewarm transport;
- classified A/B must use the already-classified hold entry per Amendment A;
- `activateVoiceInput()` only after classification;
- selected trigger DOWN only on first decoded PCM;
- no PCM -> zero receiver edges;
- release/drain/loss/disconnect balance only the captured selected key;
- secondary trigger stored independently from Persistent trigger;
- secondary Off preserves legacy path;
- SHORT must be Disabled and A != B for dual mode.

Do not redesign BLE codec, driver, tail timing, Persistent Session semantics, diagnostic authority, packaging, TCC, or non-microphone generic gestures.

## Gate 9.5 — automated candidate validation before runtime mutation

Before build/install, all changed focused suites must pass. At minimum run:

```sh
swift test --package-path remote-orbit --filter DisabledShortClassifierTests
swift test --package-path remote-orbit --filter DualReceiverVoiceGestureRecognizerTests
swift test --package-path remote-orbit --filter DualReceiverVoiceModeTests
swift test --package-path remote-orbit --filter DualReceiverVoiceSettingsTests
swift test --package-path remote-orbit --filter DualReceiverVoiceTransactionTests
swift test --package-path remote-orbit --filter VoicePressCoordinatorTests
swift test --package-path remote-orbit --filter VoiceOptionTriggerTests
swift test --package-path remote-orbit --filter EventSuppressorTests
swift test --package-path remote-orbit --filter RemoteVoiceKeyMappingTests
swift test --package-path remote-orbit --filter BLEBridgeTests
swift test --package-path remote-orbit --filter VoiceTriggerRuntimeTests
swift test --package-path remote-orbit --filter VoicePersistentSessionTests
swift test --package-path remote-orbit
./remote-orbit/run-self-tests.sh
swift build --package-path remote-orbit -c release
git diff --check
```

Also audit exact changed paths against the plan and confirm:

```text
GENERIC_BUTTON_GESTURE_THRESHOLD_CHANGED = NO
PERSISTENT_SESSION_SEMANTICS_CHANGED = NO
SECOND_HID_OWNER_ADDED = NO
SECOND_DIAGNOSTIC_AUTHORITY_ADDED = NO
PRECLASSIFICATION_A_OR_B_MAPPING = NO
DUAL_CLASSIFIER_DOUBLE_WAIT = NO
MAPPING_CLEAR_FAILURE_FALLBACK = NO
```

Commit/push exact implementation HEAD and verify local/remote match before runtime replacement.

## Gate 10 — authorized early test runtime preparation

Only after Gate 9.5 PASS:

Allowed:
- build/package the exact implementation candidate using existing repository scripts;
- replace `/Applications/RemoteOrbit.app` with that exact candidate;
- restart only RemoteOrbit as required to run it;
- verify installed/running identity.

Forbidden:
- driver replacement/restart;
- CoreAudio restart;
- TCC/Accessibility/Input Monitoring changes;
- receiver shortcut changes;
- generic system remapping outside RemoteOrbit's runtime transition;
- user hardware gestures performed by executor;
- merge.

Record:

```text
SOURCE_HEAD
REMOTE_BRANCH_HEAD
LOCAL_REMOTE_MATCH
APP_PATH
EXECUTABLE_SHA256
CFBundleShortVersionString
CFBundleVersion
BUNDLE_ID
CODE_IDENTITY
RUNNING_PID
CURRENT_A_TRIGGER
CURRENT_B_TRIGGER
DUAL_MODE_ELIGIBILITY
REMOTE_F5_MAPPING_STATE
```

Then STOP and return exactly:

`READY_FOR_USER_EARLY_HARDWARE_ACCEPTANCE`

The user will perform:

```text
5 x direct LONG
5 x quick-first-tap + second LONG
5 x quick single tap
```

No source correction is authorized during that acceptance stop.

## Hardware decision boundary

If the user's hardware result later shows classified synthetic Left/Right Option is not reliably accepted by either real receiver, return:

`SYNTHETIC_RECEIVER_TRIGGER_NOT_ACCEPTED`

and stop construction. Do not restore pre-classification hidutil mapping.

If the early hardware gate passes, Web will authorize the remaining Task 11 polish/full validation and Task 12 final acceptance in a separate transition.

## Required implementation handoff before user hardware test

Return:

```text
TASK_ID: RO-DUAL-RECEIVER-MOMENTARY-ROUTING-019
CONTROL_HEAD:
IMPLEMENTATION_BASE:
IMPLEMENTATION_BRANCH: codex/dual-receiver-momentary-routing-v1
IMPLEMENTATION_WORKTREE: /private/tmp/remoteorbit-dual-receiver-momentary-routing-v1
FINAL_HEAD:
REMOTE_HEAD:
LOCAL_REMOTE_MATCH:
CLASSIFIER_CORRECTIVE_ADOPTED:
TASK_2_CLASSIFIER: PASS/STOP
TASK_3_TRIGGER_OWNER: PASS/STOP
TASK_4_F5_PARKING: PASS/STOP
TASK_5_DUAL_AUTHORITY: PASS/STOP
TASK_6_PREWARM_INTEGRATION: PASS/STOP
TASK_7_FIRST_PCM_OWNER: PASS/STOP
TASK_8_RELEASE_OWNERSHIP: PASS/STOP
TASK_9_SETTINGS: PASS/STOP
WEB_AMENDMENT_A_NO_DOUBLE_WAIT: PASS/STOP
WEB_AMENDMENT_B_MAPPING_CLEAR_FAIL_CLOSED: PASS/STOP
FOCUSED_TESTS:
FULL_SWIFT_TEST:
SELF_TESTS:
RELEASE_BUILD:
DIFF_CHECK:
SCOPE_AUDIT:
APP_PATH:
EXECUTABLE_SHA256:
APP_VERSION_BUILD:
BUNDLE_ID:
RUNNING_PID:
CANONICAL_PREEXISTING_DIRT_PRESERVED:
MERGED: NO
FINAL_STATE: READY_FOR_USER_EARLY_HARDWARE_ACCEPTANCE
```

Do not proceed to plan Task 11 or Task 12 in this execution.
