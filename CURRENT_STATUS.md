# CURRENT_STATUS

Last updated: 2026-10-07
State: ACTIVE INCIDENT — CLASSIFIER FIXED / EXTERNAL TRIGGER MECHANISM REMAINS
Repository: `Lost0rz/RemoteOrbit`

This file is the authority for mutable current project state. Historical detail remains preserved in Git history.

## Control-plane integrity

- Previous control HEAD: `e03495e468342aa1e298a196dcd566797d3caa16`.
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

## Existing diagnostic capability

Merged PR #18 already provides raw HID report/edge sequence, mapped-trigger CGEvent timestamp/action, HID-vs-fallback correlation, and frontmost-application transition diagnostics. Do not add new probes before using these signals.

## Mapped-modifier discriminator correction

The previously proposed Right Option negative control is INVALID because the user reports Right Option has an existing input-method function. Using it would introduce a second semantic effect and make the experiment uninterpretable.

RemoteOrbit supports Left/Right Option, Left/Right Control, and Left/Right Command as trigger targets. At the user's request, the next bounded discriminator will use **Left Control**, but only if the user's physical-keyboard Left Control tap is first confirmed to have no visible Doubao/input-method/other semantic effect.

Current hypotheses remain:

1. the configured system-mapped modifier path is required for the external Doubao trigger;
2. the Session opening does not require the configured mapped modifier, leaving pending transport/prewarm, raw/native remote behavior, or another external mechanism as candidates.

No source change is authorized. Do not merge the candidate yet.
