# RemoteOrbit Current Task

## Current task — RO-INCIDENT-20261004-01 / USER A DISABLED FAST-CLICK ACCEPTANCE

- **Status:** ACTIVE / USER A AUTHORIZED
- **Incident ID:** `RO-INCIDENT-20261004-01`
- **Candidate branch:** `codex/disabled-short-classifier-regression-fix`
- **Candidate HEAD:** `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`
- **Installed source HEAD:** `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`
- **Installed executable SHA-256:** `a033e86a92b02175a498bba3232c5ae8b72719caef781cb74c3187e8e64ed017`
- **Installed PID after journal recovery:** `79232`
- **Evidence directory:** `/private/tmp/remoteorbit-disabled-short-hardware-acceptance-20261007`
- **Source mutation:** FORBIDDEN
- **Rebuild/reinstall:** FORBIDDEN
- **Merge:** FORBIDDEN
- **User A:** AUTHORIZED after read-only Doubao confirmation
- **User B:** FORBIDDEN until A passes

## Accepted readiness evidence

The journal blocker is closed:

```text
PREINSTALL_RECORD1_EQUALS_BLOCKED_LIVE_RECORD1: YES
ARCHIVE_HASH_MATCH: YES
STATUS_EXIT: 0
VERIFY_EXIT: 0
QUERY_EXIT: 0
FRESH_LIVE_JOURNAL_STATE: absent/empty
```

Input-source observation during recovery:

```text
BEFORE_RELAUNCH: com.tencent.inputmethod.chatterfly.pinyin
AFTER_RELAUNCH: com.bytedance.inputmethod.doubaoime.pinyin
AGENT_INPUT_SOURCE_CHANGE_COMMAND: NONE
CAUSE_OF_CHANGE: UNKNOWN
```

Do not diagnose or fix that input-source transition in this task. The current post-relaunch source is Doubao, which is the required acceptance environment.

## Gate 0 — exact authority and runtime identity

1. `git fetch origin --prune`.
2. Verify live `origin/main` exactly equals the control HEAD containing this task.
3. Verify `origin/codex/disabled-short-classifier-regression-fix` exactly equals `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`.
4. Read `AGENTS.md`, `CURRENT_STATUS.md`, and this `CURRENT_TASK.md` from live `origin/main`.
5. Verify installed RemoteOrbit still has:
   - source HEAD `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`;
   - executable SHA-256 `a033e86a92b02175a498bba3232c5ae8b72719caef781cb74c3187e8e64ed017`;
   - SHORT = Disabled;
   - momentary/persistent/legacy = `left_option`.
6. Read the active input source once, read-only.
7. Required for A: `com.bytedance.inputmethod.doubaoime.pinyin`.

If the source is not Doubao, STOP and report the actual source. Do not switch it automatically.

No additional diagnostics, source edits, rebuild, reinstall, merge, settings reset, driver/CoreAudio/TCC changes, or synthetic input are allowed.

## Gate 1 — User A: one Disabled fast click

Starting with no visible Doubao Session open:

1. Tell the user: perform **one normal fast physical click/release** of the remote voice key; do not hold it.
2. The user reports only whether a Doubao Session visibly opened.
3. Immediately capture the exact matching gesture/log window.

A valid sample must show release before the existing hold threshold and classification `short`.

Expected candidate evidence:

```text
bypasses_short_classification=false
GESTURE_CLASSIFIED=short
session_mode=idle
no HOLD promotion
hardware gate begins then cancels
no short replay of mapped trigger
no synthetic trigger edge
USER_VISIBLE_DOUBAO_SESSION_OPEN=NO
```

If the press crosses the hold threshold, mark `A_SAMPLE_VALID=NO / INVALID_FOR_A` and allow exactly one retry. Do not change settings or code.

### Decision after A

If valid A shows:

```text
A_CLASSIFICATION=short
A_DOUBAO_SESSION_OPEN=NO
```

then stop and return `A_PASS_READY_FOR_USER_B`. Do not perform LONG until Web authorizes B.

If valid A shows:

```text
A_CLASSIFICATION=short
A_DOUBAO_SESSION_OPEN=YES
```

stop immediately at:

`CLASSIFIER_FIXED_EXTERNAL_MECHANISM_REMAINS`

Do not perform B and do not edit code.

## Gate 2 — evidence seal

After A:

- preserve/hash the exact matching runtime log window;
- record gesture ID, timestamps, duration, classifier result, gate result, mapped/synthetic trigger observations, runtime identity and user-visible result;
- run read-only diagnostics query only if useful for sealing the A sample; do not mutate runtime state;
- do not merge.

## Required report

```text
TASK_ID: RO-DISABLED-SHORT-HARDWARE-A-005
CONTROL_HEAD:
CANDIDATE_HEAD: 172427957fd18a2b5827edd1cb1c4bddb6a5b7db
CANDIDATE_REMOTE_MATCH:
INSTALLED_PID:
INSTALLED_SOURCE_HEAD:
INSTALLED_SHA256:
SETTINGS_PRESERVED:
INPUT_SOURCE_BEFORE_A:
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
PRODUCT_SOURCE_CHANGED: NO
REBUILD_OR_REINSTALL: NO
MERGED: NO
FINAL_STATE:
```
