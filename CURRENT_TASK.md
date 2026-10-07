# RemoteOrbit Current Task

## Current task — RO-INCIDENT-20261004-01 / FRESH-BASELINE USER A RETRY

- **Status:** ACTIVE / FRESH BASELINE REQUIRED BEFORE USER A
- **Incident ID:** `RO-INCIDENT-20261004-01`
- **Candidate branch:** `codex/disabled-short-classifier-regression-fix`
- **Candidate HEAD:** `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`
- **Installed source HEAD:** `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`
- **Installed executable SHA-256:** `a033e86a92b02175a498bba3232c5ae8b72719caef781cb74c3187e8e64ed017`
- **Installed PID:** `79232`
- **Evidence root:** `/private/tmp/remoteorbit-disabled-short-hardware-acceptance-20261007`
- **Source mutation:** FORBIDDEN
- **Restart/rebuild/reinstall:** FORBIDDEN
- **Merge:** FORBIDDEN
- **User A:** BLOCKED until fresh baseline is armed
- **User B:** FORBIDDEN until valid fresh A passes and Web authorizes B

## Prior A sample disposition

The 22:24:38–22:25:28 +08:00 window contained 17 gestures (13 short, 4 hold). Because the user performed multiple extra checks, the report that Doubao Session did not open cannot be uniquely associated with one gesture.

Therefore:

```text
PRIOR_A_SAMPLE_VALID: NO
PRIOR_A_FINAL_STATE: A_SAMPLE_INVALID_AMBIGUOUS_WINDOW
POST_HOC_SELECTION_FOR_PASS: FORBIDDEN
```

Preserve that evidence unchanged. Do not delete or reuse one of its gestures as a decisive A sample.

## Gate 0 — authority and runtime identity

1. `git fetch origin --prune`.
2. Verify live `origin/main` exactly equals the control HEAD containing this task.
3. Verify candidate remote exactly equals `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`.
4. Read `AGENTS.md`, `CURRENT_STATUS.md`, and this `CURRENT_TASK.md` from live `origin/main`.
5. Verify the existing installed runtime remains:
   - PID still the same running candidate unless macOS independently changed it; if PID changed, STOP and report rather than restart;
   - source HEAD exactly `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`;
   - executable SHA-256 exactly `a033e86a92b02175a498bba3232c5ae8b72719caef781cb74c3187e8e64ed017`.
6. Verify read-only:
   - SHORT = Disabled;
   - effective momentary trigger = `left_option`;
   - persistent trigger = `left_option`;
   - input source = `com.bytedance.inputmethod.doubaoime.pinyin`;
   - effective HID mapping/readback target = `left_option`;
   - diagnostic readiness still usable.
7. Do not change settings or perform a remote gesture.

STOP only for a real mismatch in the effective runtime conditions above. Do not stop merely because the separate suite-domain compatibility readback differs.

## Gate 1 — arm a fresh append-only baseline

Without clearing, rotating, truncating, restarting or mutating any live evidence source, create a new evidence subdirectory such as:

`fresh-user-a-008-<timestamp>`

Immediately before asking the user to act, record read-only baseline anchors for every source that will be used to identify the gesture.

For the DiagnosticAuthority journal, record where available:

- live path;
- existence;
- byte size;
- SHA-256 of current complete file if present;
- record count;
- last sequence number;
- last gesture ID;
- last event timestamp.

For the app/voice log used for gesture correlation, record where available:

- live path/source;
- byte size or equivalent cursor/offset;
- last timestamp;
- last gesture ID / last relevant event marker.

Also record:

- baseline wall-clock timestamp with timezone;
- PID/source HEAD/binary SHA;
- SHORT/effective momentary/persistent/input source/HID target.

Write these anchors into the evidence directory and hash the baseline metadata file.

PASS condition:

```text
FRESH_BASELINE_ARMED: YES
```

Only then tell the user exactly:

`READY_FOR_FRESH_USER_A — perform exactly one fast click/release now; do not LONG or repeat.`

Then stop and wait for the user's physical action/report.

## Gate 2 — capture only append-after-baseline evidence

After the user reports the one fast click and whether Doubao Session visibly opened:

1. capture only records/log content appended after the Gate 1 baseline offsets/sequence anchors;
2. do not use pre-baseline gestures to satisfy the sample;
3. correlate the new physical HID down/up pair to the new gesture ID;
4. count new physical voice gestures after baseline.

A valid sample requires:

```text
NEW_PHYSICAL_VOICE_GESTURE_COUNT: 1
A_DURATION_MS: < 300
A_BYPASS: false
A_CLASSIFICATION: short
A_SESSION_MODE: idle
A_HOLD_PROMOTION: 0
A_GATE_BEGIN: 1
A_GATE_CANCEL: 1
A_GATE_SHORT_REPLAY: 0
A_SYNTHETIC_TRIGGER: 0
```

Report mapped-trigger observations exactly as seen; expected candidate result is no mapped trigger replay/edge reaching the product path.

If no new physical gesture or more than one appears after the baseline, mark:

`A_SAMPLE_INVALID_FRESH_WINDOW`

and STOP. Do not infer pass/fail.

If duration >= 300 ms, mark:

`A_SAMPLE_INVALID_THRESHOLD`

and STOP. Do not infer pass/fail.

## Gate 3 — decision and evidence seal

For a valid fresh sample:

If:

```text
A_CLASSIFICATION=short
A_DOUBAO_SESSION_OPEN=NO
```

seal/hashes the exact append-only evidence and return:

`A_PASS_READY_FOR_USER_B`

Do not perform B.

If:

```text
A_CLASSIFICATION=short
A_DOUBAO_SESSION_OPEN=YES
```

seal/hashes the evidence and return:

`CLASSIFIER_FIXED_EXTERNAL_MECHANISM_REMAINS`

Do not perform B and do not edit code.

## Required report

```text
TASK_ID: RO-DISABLED-SHORT-HARDWARE-A-FRESH-008
CONTROL_HEAD:
CANDIDATE_HEAD: 172427957fd18a2b5827edd1cb1c4bddb6a5b7db
INSTALLED_PID:
INSTALLED_SOURCE_HEAD:
INSTALLED_SHA256:
SHORT:
MOMENTARY_EFFECTIVE:
PERSISTENT:
INPUT_SOURCE:
HID_MAPPING_TARGET:
DIAGNOSTIC_READINESS:

FRESH_BASELINE_ARMED:
BASELINE_TIMESTAMP:
BASELINE_JOURNAL_PATH:
BASELINE_JOURNAL_SIZE:
BASELINE_JOURNAL_RECORD_COUNT:
BASELINE_LAST_SEQUENCE:
BASELINE_LAST_GESTURE_ID:
BASELINE_APP_LOG_CURSOR:
BASELINE_METADATA_PATH:
BASELINE_METADATA_SHA256:

A_PERFORMED:
NEW_PHYSICAL_VOICE_GESTURE_COUNT:
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
