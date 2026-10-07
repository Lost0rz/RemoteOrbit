# CURRENT_STATUS

Last updated: 2026-10-07
State: ACTIVE INCIDENT — USER A PRIOR SAMPLE INVALID / FRESH BASELINE REQUIRED
Repository: `Lost0rz/RemoteOrbit`

This file is the authority for mutable current project state. Historical detail remains preserved in Git history.

## Control-plane integrity

- Previous control HEAD: `f095963ce3d40f926210f4be39b6674f96f84c7f`.
- Candidate branch remains `codex/disabled-short-classifier-regression-fix` at exact HEAD `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`.
- Candidate source is unchanged and unmerged.
- Prior B4 external event-plane investigation remains PAUSED.

## Installed exact candidate / accepted readiness

```text
INSTALLED_RUNTIME_PID: 79232
INSTALLED_SOURCE_HEAD: 172427957fd18a2b5827edd1cb1c4bddb6a5b7db
INSTALLED_SHA256: a033e86a92b02175a498bba3232c5ae8b72719caef781cb74c3187e8e64ed017
SHORT_BINDING: Disabled
MOMENTARY_EFFECTIVE: left_option
PERSISTENT_TRIGGER: left_option
CURRENT_INPUT_SOURCE: com.bytedance.inputmethod.doubaoime.pinyin
HID_MAPPING_TARGET: left_option
DIAGNOSTIC_READINESS: PASS
APP_RESTARTED_AFTER_RECONCILIATION: NO
SOURCE_MUTATION: NO
REBUILD_OR_REINSTALL: NO
MERGED: NO
```

The separate suite-domain preference discrepancy remains recorded but is not the effective runtime authority for this acceptance.

## Prior User A attempt — INVALID / preserved

The user intentionally performed multiple additional remote gestures while checking whether LONG behavior reproduced. The captured 22:24:38–22:25:28 +08:00 window therefore contains 17 gestures and cannot uniquely associate the user-visible report `Doubao Session did not open` with one specific gesture.

Observed in that ambiguous window:

```text
TOTAL_GESTURES: 17
SHORT_CLASSIFICATIONS: 13
HOLD_CLASSIFICATIONS: 4
BYPASSES_SHORT_CLASSIFICATION_FALSE: 17/17
USER_VISIBLE_DOUBAO_SESSION_OPEN_REPORTED: NO
A_SAMPLE_VALID: NO
DECISION_FROM_THIS_WINDOW: NONE
```

Preserved evidence:

```text
raw-window.jsonl SHA256: cf0da5ce35a7be4f7449c2ec4f9dc77d675692ab15362762299065972edd1f87
app-log-window.log SHA256: 203eb0897ad92050d9a55ae9b4ac0c0eee2a45edf5ca3c200fe673331b8ac529
candidate-summary.json SHA256: 4ce81c73c7023f528e87f57472b3eeac9a34e03cf254350fa86db9a9289ffaa0
```

This window must not be mined post hoc for a passing A sample. It is retained only as non-decisive evidence that classifier bypass remained disabled across repeated gestures.

## Fresh User A policy

A new User A is authorized only after a fresh append-only baseline is armed on the existing runtime.

Do not clear, rotate, truncate, restart, rebuild or reinstall merely to create the baseline.

The executor must first record read-only baseline anchors immediately before asking the user to act, including where available:

- diagnostic journal path, byte size, hash and last record/sequence/gesture identifier;
- app log path, byte size and last timestamp/gesture identifier;
- exact runtime PID/source SHA/binary SHA;
- SHORT, effective momentary, persistent, input source and HID mapping target.

After the executor reports `READY_FOR_FRESH_USER_A`, the user performs exactly one normal fast physical click/release and reports whether Doubao Session visibly opened.

Only records appended after the baseline anchors may be used for the decision. A valid sample must contain exactly one new physical voice gesture, be below the 300 ms threshold, and classify `short`.

Decision:

- valid fresh A + Session does NOT open => `A_PASS_READY_FOR_USER_B`;
- valid fresh A + Session opens => `CLASSIFIER_FIXED_EXTERNAL_MECHANISM_REMAINS`;
- zero or more than one new physical gesture, or duration >= 300 ms => fresh A invalid; do not infer pass/fail.

User B remains forbidden until a valid fresh A passes and Web explicitly authorizes B.
