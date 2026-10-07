# CURRENT_STATUS

Last updated: 2026-10-07
State: ACTIVE INCIDENT — CLASSIFIER FIXED / EXTERNAL TRIGGER MECHANISM REMAINS
Repository: `Lost0rz/RemoteOrbit`

This file is the authority for mutable current project state. Historical detail remains preserved in Git history.

## Control-plane integrity

- Previous control HEAD: `4c70273c90f5548ea21e847a7f59d2a84a33a07b`.
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

The earlier ambiguous 17-gesture A window remains preserved but is INVALID for causal acceptance. It is not used to decide this state.

Accepted conclusion:

`CLASSIFIER_FIXED_EXTERNAL_MECHANISM_REMAINS`

This proves the PR #14 Disabled-SHORT immediate-HOLD classifier regression is not sufficient to explain the current visible fast-click Session opening. A valid <300 ms press now classifies SHORT and avoids HOLD/replay/synthetic trigger, yet Doubao still opens.

Do not claim the exact external mechanism is known yet.

## Existing diagnostic capability

Merged PR #18 already provides the required bounded boundary evidence: raw HID report/edge sequence, mapped-trigger CGEvent timestamp/action, HID-vs-fallback correlation, and frontmost-application transition diagnostics. Do not add new probes before using these existing signals.

## Current discriminating hypotheses

Highest-value remaining split:

1. the physical/system HID mapping target itself is required for the external Doubao trigger (for example a modifier edge visible below or outside RemoteOrbit's gate/event-tap observation);
2. the Session opening does not require the configured mapped modifier, leaving pending transport/prewarm, raw/native remote behavior, or another external mechanism as candidates.

The next task is a configuration-only A/B discriminator. No product source change is authorized.

## Candidate merge status

Do not merge the candidate yet. The classifier correction is semantically restored and independently tested, but the user-visible defect remains. Keep the exact candidate installed/unmerged while the external mechanism is isolated.
