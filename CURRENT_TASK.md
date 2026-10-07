# RemoteOrbit Current Task

## Current task — RO-INCIDENT-20261004-01 / USER A DISABLED FAST-CLICK ACCEPTANCE

- **Status:** ACTIVE / READY_FOR_USER_A
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
- **User A:** AUTHORIZED
- **User B:** FORBIDDEN until A passes and Web authorizes B

## Accepted readiness

Journal readiness is closed and the exact candidate remains installed.

Momentary trigger reconciliation passed using the effective running-app/runtime authority:

```text
SHORT = Disabled
MOMENTARY_EFFECTIVE = left_option
PERSISTENT = left_option
INPUT_SOURCE = com.bytedance.inputmethod.doubaoime.pinyin
HID_MAPPING_TARGET = left_option
HID_VERIFY = MATCH
```

A separate suite-domain readback may still disagree for momentary/legacy. Record that discrepancy if observed, but do not treat it as a blocker while the running app value, UI, HID mapping readback and filter configuration agree on Left Option.

## Gate 0 — final read-only pre-A check

1. `git fetch origin --prune`.
2. Verify live `origin/main` exactly equals the control HEAD containing this task.
3. Verify `origin/codex/disabled-short-classifier-regression-fix` exactly equals `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`.
4. Read `AGENTS.md`, `CURRENT_STATUS.md`, and this `CURRENT_TASK.md` from live `origin/main`.
5. Verify installed PID/runtime identity remains exact.
6. Verify read-only immediately before A:
   - SHORT = Disabled;
   - effective momentary trigger = `left_option`;
   - persistent trigger = `left_option`;
   - input source = `com.bytedance.inputmethod.doubaoime.pinyin`;
   - effective HID mapping/readback target = `left_option`.
7. Do not modify settings or restart.

If these remain true, return:

```text
READY_FOR_USER_A — perform one fast click now
```

## Gate 1 — User A: exactly one Disabled fast click

Starting with no visible Doubao Session open:

1. User performs **one normal fast physical click/release** of the remote voice key; do not hold it.
2. User reports only whether a Doubao Session visibly opened.
3. Immediately capture the exact matching gesture/log window.

A valid sample must be below the existing 300 ms hold threshold and classified `short`.

Required evidence fields:

```text
bypasses_short_classification=false
GESTURE_CLASSIFIED=short
session_mode=idle
HOLD_PROMOTION=0
hardware gate begin=1
hardware gate cancel=1
hardware gate short replay=0
mapped trigger edge=0
synthetic trigger edge=0
```

If press duration >= 300 ms, mark `INVALID_FOR_A` and allow exactly one retry. Do not change settings or code.

## Gate 2 — decision and seal

If valid A has:

```text
A_CLASSIFICATION=short
A_DOUBAO_SESSION_OPEN=NO
```

seal the evidence and return:

`A_PASS_READY_FOR_USER_B`

Do not perform LONG until Web authorizes B.

If valid A has:

```text
A_CLASSIFICATION=short
A_DOUBAO_SESSION_OPEN=YES
```

seal the evidence and stop at:

`CLASSIFIER_FIXED_EXTERNAL_MECHANISM_REMAINS`

Do not perform B and do not edit code.

## Required report

```text
TASK_ID: RO-DISABLED-SHORT-HARDWARE-A-007
CONTROL_HEAD:
CANDIDATE_HEAD: 172427957fd18a2b5827edd1cb1c4bddb6a5b7db
CANDIDATE_REMOTE_MATCH:
INSTALLED_PID:
INSTALLED_SOURCE_HEAD:
INSTALLED_SHA256:
SHORT:
MOMENTARY_EFFECTIVE:
PERSISTENT:
INPUT_SOURCE_BEFORE_A:
HID_MAPPING_TARGET_BEFORE_A:
DIAGNOSTIC_READINESS: PASS

A_PERFORMED:
A_SAMPLE_VALID:
A_GESTURE_ID:
A_DURATION_MS:
A_BYPASS:
A_CLASSIFICATION:
A_SESSION_MODE:
A_HOLD_PROMOTION:
A_GATE_BEGIN:
A_GATE_CANCEL:
A_GATE_SHORT_REPLAY:
A_MAPPED_TRIGGER:
A_SYNTHETIC_TRIGGER:
A_DOUBAO_SESSION_OPEN:

EVIDENCE_PATHS:
EVIDENCE_HASHES:
APP_RESTARTED: NO
PRODUCT_SOURCE_CHANGED: NO
REBUILD_OR_REINSTALL: NO
MERGED: NO
FINAL_STATE:
```
