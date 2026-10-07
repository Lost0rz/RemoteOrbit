# RemoteOrbit Current Task

## Current task — RO-INCIDENT-20261004-01 / MAPPED-TRIGGER DEPENDENCY DISCRIMINATION

- **Status:** ACTIVE / LEFT-CONTROL NEGATIVE CONTROL REQUIRED
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

## Goal

Discriminate whether the visible Doubao Session opening depends on the configured system-mapped modifier while keeping classifier, pending transport/prewarm, candidate binary, input method, and remote hardware unchanged.

Right Option is explicitly disallowed as a control because the user reports it has an existing input-method function.

At the user's request, the control key is **Left Control**, but it may be used only after a physical-keyboard Left Control tap is confirmed to have no visible Doubao/input-method/other semantic effect.

## Gate 0 — exact runtime and evidence audit

1. `git fetch origin --prune`.
2. Verify live `origin/main` exactly equals the control HEAD containing this task.
3. Verify candidate remote exact HEAD `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`.
4. Read `AGENTS.md`, `CURRENT_STATUS.md`, and this task from live `origin/main`.
5. Verify runtime identity/hash remains exact.
6. Verify SHORT remains Disabled and input source is Doubao.
7. Read the sealed fresh-A `analysis.json` and appended diagnostics; record exact `MAPPED_TRIGGER_EVENT` count/actions for gesture `66EAAC65-0704-482C-B01B-4F89F3DE0E19` rather than assuming zero.
8. Verify diagnostics remain readable.

STOP for runtime/source/hash/control mismatch. Do not edit code.

## Gate 1 — establish Left Control as a negative control

Before changing RemoteOrbit, ask the user to ensure no Doubao Session is open, then tap the **physical keyboard Left Control once**. Do not use the remote.

User reports whether that single tap:

- opens Doubao Session;
- switches input method;
- causes any other visible semantic action.

If any such effect occurs:

`LEFT_CONTROL_NOT_VALID_NEGATIVE_CONTROL`

STOP. Do not change RemoteOrbit settings.

If no effect occurs:

`LEFT_CONTROL_NEGATIVE_CONTROL=PASS`

Continue.

## Gate 2 — change only RemoteOrbit momentary target

Using the normal RemoteOrbit settings UI, the user changes only:

```text
Momentary trigger: Left Option -> Left Control
```

Keep unchanged:

- SHORT = Disabled;
- persistent trigger = Left Option;
- Doubao input source;
- candidate binary/source;
- all timing/classifier logic;
- pending transport/prewarm;
- driver/CoreAudio/TCC;
- legacy compatibility value unless the normal UI updates it incidentally; record but do not manually edit it.

Do not restart the app.

Read-only verify effective runtime/HID mapping target is now `left_control` and HID readback/filter configuration agrees.

## Gate 3 — fresh append-only baseline

Create a new evidence subdirectory. Do not clear/rotate logs.

Record exact append-only baselines for diagnostic journal and app/voice logs: timestamp, byte size/offset, record count, last sequence if available, last gesture ID/event timestamp, and hashes/metadata needed to prove the boundary.

Only after baseline is sealed return:

`READY_FOR_LEFT_CONTROL_REMOTE_A — perform exactly one fast remote click/release; do not LONG or repeat.`

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

If invalid/multiple gestures: STOP at `CONTROL_SAMPLE_INVALID`.

### Decision

If physical Left Control has no semantic effect and the valid remote sample mapped to Left Control has `DOUBAO_SESSION_OPEN=NO`, return:

`MAPPED_MODIFIER_DEPENDENCY_SUPPORTED`

This supports dependence on the mapped modifier path, but does not yet identify the exact event plane.

If the valid remote sample still has `DOUBAO_SESSION_OPEN=YES`, return:

`LEFT_OPTION_MAPPING_NOT_REQUIRED`

Then prioritize pending transport/prewarm, raw/native remote behavior, or another external mechanism.

Do not perform LONG and do not edit source.

## Gate 5 — restore original acceptance configuration

After evidence is sealed, use the normal RemoteOrbit settings UI to restore only:

```text
Momentary trigger: Left Control -> Left Option
```

Read-only verify effective HID mapping is again Left Option. Do not restart the app.

## Required report

```text
TASK_ID: RO-MAPPED-TRIGGER-DEPENDENCY-011
CONTROL_HEAD:
CANDIDATE_HEAD:
INSTALLED_PID:
INSTALLED_SOURCE_HEAD:
INSTALLED_SHA256:
FRESH_A_MAPPED_TRIGGER_EVENT_COUNT:
FRESH_A_MAPPED_TRIGGER_ACTIONS:
LEFT_CONTROL_KEYBOARD_CONTROL_PERFORMED:
LEFT_CONTROL_KEYBOARD_DOUBAO_OPEN:
LEFT_CONTROL_KEYBOARD_INPUT_SWITCH:
LEFT_CONTROL_KEYBOARD_OTHER_EFFECT:
LEFT_CONTROL_NEGATIVE_CONTROL:
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
