# RemoteOrbit Current Task

## Current task — RO-INCIDENT-20261004-01 / MAPPED-TRIGGER DEPENDENCY DISCRIMINATION

- **Status:** ACTIVE / CONFIGURATION-ONLY A/B
- **Incident ID:** `RO-INCIDENT-20261004-01`
- **Candidate branch:** `codex/disabled-short-classifier-regression-fix`
- **Candidate HEAD:** `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`
- **Installed source HEAD:** must remain `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`
- **Installed executable SHA-256:** must remain `a033e86a92b02175a498bba3232c5ae8b72719caef781cb74c3187e8e64ed017`
- **Evidence root:** `/private/tmp/remoteorbit-disabled-short-hardware-acceptance-20261007`
- **Source mutation:** FORBIDDEN
- **Rebuild/reinstall/restart:** FORBIDDEN
- **Merge:** FORBIDDEN
- **LONG/User B:** FORBIDDEN

## Accepted fact from fresh User A

Exactly one post-baseline remote gesture was observed:

```text
GESTURE_ID: 66EAAC65-0704-482C-B01B-4F89F3DE0E19
RAW_HID_DOWN_UP_MS: 210.171
BYPASSES_SHORT_CLASSIFICATION: false
CLASSIFICATION: short
SESSION_MODE: idle
GATE_BEGIN: 1
GATE_CANCEL: 1
GATE_SHORT_REPLAY: 0
HOLD_PROMOTION: 0
SYNTHETIC_TRIGGER_DOWN_UP: 0
USER_VISIBLE_DOUBAO_SESSION_OPEN: YES
```

Decision: `CLASSIFIER_FIXED_EXTERNAL_MECHANISM_REMAINS`.

Do not reinterpret the earlier ambiguous 17-gesture window as acceptance evidence.

## Goal

Discriminate whether the visible Doubao Session opening requires the configured system-mapped **Left Option** target while keeping classifier, pending transport/prewarm, candidate binary, input method, and remote hardware unchanged.

This is not a fix. It is one bounded configuration-only causal experiment using already-merged diagnostics.

## Gate 0 — exact runtime and evidence audit

1. `git fetch origin --prune`.
2. Verify live `origin/main` exactly equals the control HEAD containing this task.
3. Verify candidate remote exact HEAD `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`.
4. Read `AGENTS.md`, `CURRENT_STATUS.md`, and this task from live `origin/main`.
5. Verify runtime identity/hash remains exact.
6. Verify SHORT remains Disabled and input source is Doubao.
7. Verify the sealed fresh-A directory exists and read `analysis.json` plus appended voice diagnostics. Record, do not infer, the exact `MAPPED_TRIGGER_EVENT` count/actions for gesture `66EAAC65-0704-482C-B01B-4F89F3DE0E19`.
8. Verify diagnostics remain readable.

STOP for runtime/source/hash/control mismatch. Do not edit code.

## Gate 1 — establish Right Option as a negative Doubao control

Before changing RemoteOrbit, ask the user to perform one normal **physical keyboard Right Option tap** while no Doubao Session is open.

The user reports only whether Doubao Session opens.

- If Right Option opens Doubao Session: STOP at `RIGHT_OPTION_NOT_VALID_NEGATIVE_CONTROL`. Do not change RemoteOrbit settings; Web will select another control key.
- If Right Option does not open Doubao Session: record `RIGHT_OPTION_NEGATIVE_CONTROL=PASS` and continue.

Do not use the remote in this gate.

## Gate 2 — change only RemoteOrbit momentary target

Using the normal RemoteOrbit settings UI, the user changes only:

```text
Momentary trigger: Left Option -> Right Option
```

Keep unchanged:

- SHORT = Disabled;
- persistent trigger = Left Option;
- Doubao input source;
- candidate binary/source;
- all timing/classifier logic;
- pending transport/prewarm;
- driver/CoreAudio/TCC;
- legacy compatibility value unless the normal app UI updates it incidentally; record but do not manually edit it.

Do not restart the app.

Read-only verify effective runtime/HID mapping target is now `right_option` and HID readback/filter configuration agrees.

## Gate 3 — fresh append-only baseline

Create a new evidence subdirectory.

Without clearing/rotating logs, record exact append-only baselines for diagnostic journal and app/voice logs:

- wall-clock timestamp;
- byte size/offset;
- record count;
- last sequence if available;
- last gesture ID/event timestamp;
- SHA-256/metadata needed to prove pre/post boundary.

Only after baseline is sealed return:

`READY_FOR_RIGHT_OPTION_REMOTE_A — perform exactly one fast remote click/release; do not LONG or repeat.`

## Gate 4 — exactly one remote fast-click control

After the user performs one fast remote click and reports whether Doubao Session opened, analyze only records appended after the fresh baseline.

Required valid sample:

```text
NEW_PHYSICAL_VOICE_GESTURE_COUNT = 1
duration < 300 ms
bypasses_short_classification = false
classification = short
session_mode = idle
HOLD_PROMOTION = 0
gate begin = 1
gate cancel = 1
gate short replay = 0
synthetic trigger down/up = 0
```

Record exact mapped-trigger events/actions rather than assuming zero.

If the sample is invalid or multiple gestures appear: STOP at `CONTROL_SAMPLE_INVALID`.

### Decision

If Right Option is confirmed not to trigger Doubao from the physical keyboard, and the valid remote control sample with RemoteOrbit mapped to Right Option has:

```text
DOUBAO_SESSION_OPEN = NO
```

return:

`MAPPED_MODIFIER_DEPENDENCY_SUPPORTED`

Interpretation: changing only the mapped modifier removed the visible effect while classifier/prewarm remained. This strongly localizes the remaining mechanism to the system-mapped modifier path. Do not claim the exact event plane yet.

If the valid Right-Option remote sample still has:

```text
DOUBAO_SESSION_OPEN = YES
```

return:

`MAPPED_LEFT_OPTION_NOT_REQUIRED`

Interpretation: Left Option mapping is not necessary for the visible Session opening; next analysis should prioritize pending transport/native remote/other external mechanisms.

Do not perform LONG and do not edit source in either case.

## Gate 5 — restore original acceptance configuration

After evidence is sealed, use the normal RemoteOrbit settings UI to restore only:

```text
Momentary trigger: Right Option -> Left Option
```

Read-only verify effective HID mapping is again Left Option. Do not restart the app.

## Required report

```text
TASK_ID: RO-MAPPED-TRIGGER-DEPENDENCY-009
CONTROL_HEAD:
CANDIDATE_HEAD:
INSTALLED_PID:
INSTALLED_SOURCE_HEAD:
INSTALLED_SHA256:
FRESH_A_MAPPED_TRIGGER_EVENT_COUNT:
FRESH_A_MAPPED_TRIGGER_ACTIONS:
RIGHT_OPTION_KEYBOARD_CONTROL_PERFORMED:
RIGHT_OPTION_KEYBOARD_DOUBAO_OPEN:
RIGHT_OPTION_NEGATIVE_CONTROL:
MOMENTARY_BEFORE:
MOMENTARY_CONTROL:
HID_MAPPING_CONTROL:
FRESH_BASELINE_SEALED:
REMOTE_CONTROL_PERFORMED:
CONTROL_SAMPLE_VALID:
CONTROL_GESTURE_ID:
CONTROL_DURATION_MS:
CONTROL_BYPASS:
CONTROL_CLASSIFICATION:
CONTROL_SESSION_MODE:
CONTROL_HOLD_PROMOTION:
CONTROL_GATE_BEGIN:
CONTROL_GATE_CANCEL:
CONTROL_GATE_SHORT_REPLAY:
CONTROL_MAPPED_TRIGGER_EVENTS:
CONTROL_SYNTHETIC_TRIGGER:
CONTROL_DOUBAO_SESSION_OPEN:
MOMENTARY_RESTORED:
HID_MAPPING_RESTORED:
APP_RESTARTED: NO
PRODUCT_SOURCE_CHANGED: NO
REBUILD_OR_REINSTALL: NO
MERGED: NO
LONG_PERFORMED: NO
FINAL_STATE:
```
