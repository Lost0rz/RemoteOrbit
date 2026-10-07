# RemoteOrbit Current Task

## Current task — RO-INCIDENT-20261004-01 / MOMENTARY TRIGGER RECONCILIATION BEFORE USER A

- **Status:** ACTIVE / ONE SETTING RECONCILIATION REQUIRED
- **Incident ID:** `RO-INCIDENT-20261004-01`
- **Candidate branch:** `codex/disabled-short-classifier-regression-fix`
- **Candidate HEAD:** `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`
- **Installed source HEAD:** `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`
- **Installed executable SHA-256:** `a033e86a92b02175a498bba3232c5ae8b72719caef781cb74c3187e8e64ed017`
- **Installed PID:** `79232`
- **Evidence directory:** `/private/tmp/remoteorbit-disabled-short-hardware-acceptance-20261007`
- **Source mutation:** FORBIDDEN
- **Rebuild/reinstall/restart:** FORBIDDEN
- **Merge:** FORBIDDEN
- **User A:** BLOCKED only until momentary trigger is restored to Left Option and verified
- **User B:** FORBIDDEN until A passes

## Why the previous Gate 0 stopped

Observed runtime settings were:

```text
SHORT = Disabled
MOMENTARY = right_option
PERSISTENT = left_option
LEGACY = right_option
INPUT_SOURCE = com.bytedance.inputmethod.doubaoime.pinyin
```

Independent source audit shows that the device-scoped HID mapping target is the current **momentary** trigger key. Idle remote voice also uses the momentary-trigger policy. Therefore `momentary=right_option` changes the causal environment and must be restored before A.

`legacy=right_option` is not a blocker: legacy is not the current HID mapping authority. Persistent is already correct and is not to be changed.

## Gate 0 — exact authority and runtime identity

1. `git fetch origin --prune`.
2. Verify live `origin/main` exactly equals the control HEAD containing this task.
3. Verify `origin/codex/disabled-short-classifier-regression-fix` exactly equals `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`.
4. Read `AGENTS.md`, `CURRENT_STATUS.md`, and this `CURRENT_TASK.md` from live `origin/main`.
5. Verify installed RemoteOrbit still has the exact candidate source HEAD and executable SHA-256 above.
6. Verify SHORT remains Disabled.
7. Read current momentary, persistent and legacy settings plus current input source.
8. No hardware remote gesture yet.

STOP only for candidate identity/hash mismatch, SHORT no longer Disabled, persistent no longer `left_option`, input source no longer Doubao, or control/ref mismatch.

Do **not** STOP because legacy is `right_option`.

## Gate 1 — user changes only momentary trigger

Ask the user to use the normal RemoteOrbit settings UI and change only:

```text
Momentary trigger: Right Option → Left Option
```

Do not change:

- SHORT binding;
- persistent trigger;
- legacy compatibility value;
- input method;
- any UserDefaults via shell;
- source, driver, CoreAudio, TCC, Accessibility or Input Monitoring.

Do not restart the app.

The executor must not perform the UI change on the user's behalf unless the user explicitly requests computer-control interaction. Default action is to wait for the user to report the setting change is complete.

## Gate 2 — read-only verification after user change

After the user reports completion, verify read-only:

```text
SHORT = Disabled
MOMENTARY = left_option
PERSISTENT = left_option
INPUT_SOURCE = com.bytedance.inputmethod.doubaoime.pinyin
INSTALLED_SOURCE_HEAD = 172427957fd18a2b5827edd1cb1c4bddb6a5b7db
INSTALLED_SHA256 = a033e86a92b02175a498bba3232c5ae8b72719caef781cb74c3187e8e64ed017
```

Also verify the effective device-scoped HID mapping/readback now targets Left Option. Use existing read-only diagnostics/log/readback only; do not reapply hidutil manually merely to satisfy the check.

Record legacy as observed. It may remain `right_option` and is not a failure condition.

Run `diagnostics verify` and `diagnostics query --limit 1` read-only if needed to confirm journal readiness remains intact.

If all required conditions pass, return exactly:

```text
READY_FOR_USER_A
```

Do not perform User A automatically.

## Gate 3 — User A after READY only

After Web/user supplies the physical action:

1. starting with no visible Doubao Session open, user performs one normal fast click/release of the remote voice key;
2. user reports whether Doubao Session visibly opened;
3. capture exact matching gesture/log window.

A valid sample must be below the 300 ms hold threshold and classified `short`.

Expected candidate evidence:

```text
bypasses_short_classification=false
GESTURE_CLASSIFIED=short
session_mode=idle
no HOLD promotion
hardware gate begins then cancels
no short replay
no synthetic trigger edge
USER_VISIBLE_DOUBAO_SESSION_OPEN=NO
```

If valid A opens Doubao Session, STOP at `CLASSIFIER_FIXED_EXTERNAL_MECHANISM_REMAINS` and do not perform B.

If valid A does not open Doubao Session, stop at `A_PASS_READY_FOR_USER_B` and do not perform LONG until Web authorizes B.

## Required reconciliation report

```text
TASK_ID: RO-MOMENTARY-TRIGGER-RECONCILIATION-006
CONTROL_HEAD:
CANDIDATE_HEAD: 172427957fd18a2b5827edd1cb1c4bddb6a5b7db
INSTALLED_PID:
INSTALLED_SOURCE_HEAD:
INSTALLED_SHA256:
SHORT:
MOMENTARY_BEFORE:
MOMENTARY_AFTER:
PERSISTENT:
LEGACY_OBSERVED:
INPUT_SOURCE:
HID_MAPPING_TARGET_AFTER:
DIAGNOSTIC_READINESS:
APP_RESTARTED: NO
SOURCE_MUTATION: NO
REBUILD_OR_REINSTALL: NO
MERGED: NO
HARDWARE_ACTION_A_OR_B: NOT PERFORMED
FINAL_STATE:
```
