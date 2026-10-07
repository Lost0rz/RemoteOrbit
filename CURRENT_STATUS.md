# CURRENT_STATUS

Last updated: 2026-10-07
State: ACTIVE INCIDENT — CLASSIFIER FIXED / EXTERNAL TRIGGER MECHANISM REMAINS
Repository: `Lost0rz/RemoteOrbit`

This file is the authority for mutable current project state. Historical detail remains preserved in Git history.

## Control-plane integrity

- Previous control HEAD: `f5196526cde10ad66f64eb0ec960e24617bffe94`.
- Candidate branch remains `codex/disabled-short-classifier-regression-fix` at exact HEAD `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`.
- Candidate source is unchanged and unmerged.
- Installed candidate remains the active incident runtime unless a later task records otherwise.
- User B / LONG remains forbidden.

## Valid fresh User A result

Fresh-baseline A produced exactly one physical remote voice gesture:

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

The earlier ambiguous 17-gesture A window remains preserved but is INVALID for causal acceptance.

Accepted conclusion:

`CLASSIFIER_FIXED_EXTERNAL_MECHANISM_REMAINS`

The PR #14 Disabled-SHORT immediate-HOLD regression is real and corrected by the candidate, but it is not sufficient to explain the visible fast-click Session opening. Do not claim the exact external mechanism is known.

## Fresh-A mapped-trigger evidence

Gate 0 re-read of the sealed Fresh A evidence established:

```text
FRESH_A_MAPPED_TRIGGER_EVENT_COUNT: 0
FRESH_A_MAPPED_TRIGGER_ACTIONS: none
```

This further narrows the observed candidate-visible event path, but it still does not prove that no modifier edge exists below or outside the current RemoteOrbit observation plane.

## Existing diagnostic capability

Merged PR #18 already provides raw HID report/edge sequence, mapped-trigger CGEvent timestamp/action, HID-vs-fallback correlation, and frontmost-application transition diagnostics. Do not add new probes before using these signals.

## Mapped-modifier discriminator

Right Option is explicitly disallowed because the user reports it has an existing input-method function.

RemoteOrbit supports Left/Right Option, Left/Right Control, and Left/Right Command as trigger targets. At the user's request, the bounded discriminator uses **Left Control**, but only if the user's physical-keyboard Left Control tap is first confirmed to have no visible Doubao/input-method/other semantic effect.

## Input-source readback reconciliation

Latest Gate 0 observed conflicting input-source signals:

- HIToolbox selected-source list included Doubao;
- realtime TIS query returned `com.apple.keylayout.ABC` while also reporting an input-source service connection error.

A TIS result accompanied by its own service/connection failure is not authoritative evidence that ABC is truly active. For this bounded hardware experiment, when realtime TIS is unhealthy, the user's direct visual confirmation of the currently active menu-bar input method is accepted as the input-source authority.

Therefore:

- if the user visually confirms the menu-bar active input method is Doubao, Gate 0 may continue;
- if the menu bar shows another input method, STOP and do not perform the Left Control control;
- do not switch input methods merely to satisfy the diagnostic readback disagreement unless the user explicitly chooses to restore Doubao.

Record the conflicting machine readbacks and the user's visual confirmation in the evidence report. Do not expand this into a separate input-source diagnostics project during the current incident.

Current hypotheses remain:

1. the configured system-mapped modifier path is required for the external Doubao trigger;
2. the Session opening does not require the configured mapped modifier, leaving pending transport/prewarm, raw/native remote behavior, or another external mechanism as candidates.

No source change is authorized. Do not merge the candidate yet.
