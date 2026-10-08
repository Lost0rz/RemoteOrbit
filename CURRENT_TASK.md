# RemoteOrbit Current Task

## Current task — DUAL-RECEIVER MICROPHONE DEBOUNCE CORRECTIVE

- **Status:** IMPLEMENTED / CANDIDATE INSTALLED / WAITING FOR USER SET B CORRECTIVE RETRY
- **Task ID:** `RO-DUAL-RECEIVER-MIC-DEBOUNCE-CORRECTIVE-024`
- **Previous task:** `RO-DUAL-RECEIVER-SYSTEM-MAPPED-IMPLEMENTATION-023` — SET B INCIDENT / INTERNAL ROOT CAUSE PROVEN
- **Failed v2 HEAD:** `e1e6fe0bf76e245c4237978600b117b5b8e2a83e`
- **Installed failed source:** `50a20174632dc105fb670a9b83e3f6feaa8e9f9b`
- **Authorized branch:** `codex/dual-receiver-mic-debounce-corrective`
- **Authorized worktree:** `/private/tmp/remoteorbit-dual-receiver-mic-debounce-corrective`
- **Merge:** FORBIDDEN

## Current result

The active dual-mode HID policy regression failed before the product edit because `shouldDebounce` remained true and the 109.810 ms second DOWN was suppressed; legacy and generic policy checks passed. The policy correction and HID-policy/debouncer regression are committed in product commit `406f1242e7c3bc17b1fa0da43b069a0b2c6874c8`. The release candidate is installed at `/Applications/RemoteOrbit.app` with that source stamp and is running as PID `5331`. Focused HID policy tests passed 3/3, dual-receiver transaction tests passed 19/19, the full Swift suite passed 387/387, self-tests passed 3/3, the release build succeeded, and `git diff --check` passed. Scope audit found only the two intended product files, the regression test, and these task controls. No remote gestures were performed. The remaining action is the user’s Set B corrective retry.

## Root cause

The failed Set-B attempt had:

```text
first UP -> SECONDARY_READY: 22.737 ms
first UP -> second physical DOWN: 109.810 ms
```

`ButtonEdgeDebouncer.defaultInterval` is `0.18` seconds. The live second F5 DOWN at 109.810 ms was recorded as:

```text
HID_MIC_EDGE_SUPPRESSED reason=debounce
```

The failed candidate source computed advanced gesture ownership as:

```text
button != .microphone && profile.usesAdvancedGestures
```

so the microphone remained on the legacy debounce path even while active dual-receiver recognition needed the intentional second press inside the 300 ms window.

The mapped Right Option event then passed with `gate_state=none`; no B HardwareOptionGate begin or B classification occurred. Follow-on attempts reproduced the same input-layer suppression. This proves the internal root cause for the B transaction failure.

## Test gap

`DualReceiverVoiceTransactionTests` calls `controller.handleDualReceiverMicrophoneEdge(...)` directly through its harness and bypasses `HIDMonitor` / `ButtonEdgeDebouncer`. Existing transaction tests therefore do not cover the failing boundary.

## Corrective scope and acceptance

TDD RED was recorded before product mutation at the HID input-policy/debouncer boundary with the observed timing:

```text
first accepted microphone DOWN
first accepted microphone UP
109.810 ms later second microphone DOWN
```

Expected in active dual mode: second DOWN is emitted to the dual-receiver recognizer, not suppressed by legacy debounce.

Also prove:

```text
legacy microphone mode keeps existing debounce behavior
non-microphone single-shot behavior is unchanged
repeatable/advanced generic buttons are unchanged
```

The smallest policy correction makes only active dual-receiver microphone input bypass the conflicting legacy `ButtonEdgeDebouncer` layer, using explicit dual-mode ownership semantics without changing the global debounce interval.

## Strict non-goals

```text
NO global ButtonEdgeDebouncer interval change
NO generic ButtonGestureRecognizer timing/behavior change
NO dual 350/300 timing change
NO mapping architecture change
NO HardwareOptionGate redesign
NO B release/drain retune
NO BLE codec/tail change
NO Persistent Session change
NO synthetic normal trigger
NO HIDMonitor ownership duplication
NO driver/CoreAudio/TCC change
NO unrelated cleanup/refactor
```

The external receiver remaining open in the failed sample is not yet a separately proven defect after the input-layer failure; do not add a second speculative fix.

## Validation

Required focused RED->GREEN coverage must include the HID policy/debouncer boundary and existing dual-receiver transaction suites. Then run:

```sh
swift test --package-path remote-orbit
./remote-orbit/run-self-tests.sh
swift build --package-path remote-orbit -c release
git diff --check
```

Scope audit must confirm only the intended input-policy/test correction plus task control files changed.

Only after all automated validation passes may the executor build/package/install the exact corrective candidate and restart RemoteOrbit only.

Do not perform remote gestures. Stop at:

`READY_FOR_USER_SET_B_CORRECTIVE_RETRY`

## Required handoff

```text
TASK_ID: RO-DUAL-RECEIVER-MIC-DEBOUNCE-CORRECTIVE-024
CONTROL_HEAD:
BASE_HEAD: e1e6fe0bf76e245c4237978600b117b5b8e2a83e
BRANCH:
WORKTREE:
FINAL_HEAD:
REMOTE_HEAD:
LOCAL_REMOTE_MATCH:

ROOT_CAUSE_PROVEN: YES
RED_HID_BOUNDARY_TEST:
GREEN_HID_BOUNDARY_TEST:
LEGACY_MIC_DEBOUNCE_REGRESSION:
NON_MIC_REGRESSION:
DUAL_TRANSACTION_REGRESSION:
FULL_SWIFT_TEST:
SELF_TESTS:
RELEASE_BUILD:
DIFF_CHECK:
SCOPE_AUDIT:

GLOBAL_DEBOUNCE_INTERVAL_CHANGED: NO
GENERIC_GESTURE_CHANGED: NO
DUAL_350_300_CHANGED: NO
MAPPING_ARCHITECTURE_CHANGED: NO
RELEASE_DRAIN_CHANGED: NO
CANONICAL_DIRTY_HIDMONITOR_TOUCHED: NO

APP_PATH:
INSTALLED_SOURCE_HEAD:
EXECUTABLE_SHA256:
APP_VERSION_BUILD:
BUNDLE_ID:
RUNNING_PID:

REMOTE_GESTURES_PERFORMED: NO
MERGED: NO
FINAL_STATE: READY_FOR_USER_SET_B_CORRECTIVE_RETRY
```
