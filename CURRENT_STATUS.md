# CURRENT_STATUS

Last updated: 2026-10-08
State: DUAL-RECEIVER GESTURE RECOGNITION STABILITY TEST ACTIVE
Repository: `Lost0rz/RemoteOrbit`

This file is the authority for mutable current project state. Historical detail remains preserved in Git history.

## Control-plane integrity

- Previous control HEAD: `98198d4e4aac6f4e233cbb1b1367ce2984c79d3d`.
- Candidate branch remains `codex/disabled-short-classifier-regression-fix` at exact HEAD `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`.
- Installed candidate remains the current hardware-test baseline unless a later task records otherwise.
- Candidate remains unmerged.
- No product source mutation is authorized by the current recognition-only task.

## Closed single-input-method finding

The prior fast-click Doubao anomaly is explained by receiver shortcut collision: Doubao's click/toggle mode and hold-to-talk mode were both bound to Left Option. Separating those receiver semantics removes that specific unwanted fast-click Session activation.

The independent PR #14 Disabled-SHORT classifier regression remains real; the candidate still correctly restores normal short/long classification.

## Selected dual-receiver product interaction

The user selected the one-button dual-hold interaction contract:

```text
Direct LONG                  -> Receiver A
Double-tap, hold second down -> Receiver B
```

Intended eventual receiver mapping:

```text
Receiver A -> Left Option
Receiver B -> Right Option
```

Both receivers are intended to use independent momentary voice transactions. No external persistent Session should be required for the dual-receiver workflow.

## Why recognition stability is tested before implementation

The Xiaomi remote microphone provides useful audio only while the physical microphone button is held. The two receiver gestures therefore both need a hold phase.

Before redesigning trigger ownership, first determine whether the physical gesture vocabulary itself is reliably distinguishable with the user's natural operation. This test must use existing HID diagnostics and must not yet route Left/Right Option into either real receiver.

## Existing gesture infrastructure fact

The repository already contains a generic `ButtonGestureRecognizer` supporting:

```text
singleTap
doubleTap
longPress
repeatStep
```

A second tap that is held long is representable as a long event with `clickCount = 2`.

Current generic constants are:

```text
longPressThreshold = 0.35 s
doubleTapWindow    = 0.25 s
```

The microphone voice path does not currently use this generic recognizer when remote-microphone LONG is enabled. It is routed directly into `VoicePressCoordinator`, whose current hold threshold is 0.30 s.

Therefore the existing constants are comparison points only. The recognition test should collect real physical timing distributions first instead of assuming either threshold set is optimal.

## Recognition-only test model

Collect natural physical microphone-button samples using existing raw HID diagnostics only.

Classes:

```text
A_DIRECT_LONG
- one physical down
- held long
- one physical up
- no qualifying first tap prefix

B_DOUBLE_HOLD
- first physical down/up is a short tap
- second physical down begins within a candidate double-tap window
- second press is held long
- second physical up ends the gesture

NO_ACTION_SINGLE_TAP
- one short down/up
- no second down inside the double-tap window
```

Initial sample target:

```text
10 x A_DIRECT_LONG
10 x B_DOUBLE_HOLD
5  x NO_ACTION_SINGLE_TAP
```

For every sample derive from raw HID edges:

```text
first_press_duration_ms
first_up_to_second_down_ms (B only)
second_press_duration_ms (B only)
total_gesture_duration_ms
raw report/edge sequence continuity
unexpected extra edges / debounce suppression
```

Then replay the captured timings offline against a small threshold matrix rather than changing live behavior:

```text
candidate long threshold:   250 / 300 / 350 / 400 ms
candidate double window:    200 / 250 / 300 / 350 ms
```

The goal is not merely 100% classification on 25 samples. Prefer a threshold pair with visible timing margin from the user's natural distributions, especially for B's first-up -> second-down gap.

## Safety / isolation for this test

Do not allow the recognition test to exercise actual Receiver A/B shortcuts.

Preferred test configuration:

```text
SHORT action: Disabled
momentary mapping: a verified neutral trigger such as Left Control
persistent behavior: not used
Receiver A/B visible Sessions: closed
```

Before using a neutral key, verify that a physical press of that key does not open/switch either receiver. If no verified neutral trigger is available, STOP rather than run the timing test against Left/Right Option receiver shortcuts.

Temporary normal-UI trigger reconfiguration is allowed only for test isolation and must be restored after capture. No source edits, rebuild, reinstall, restart, new probes, driver changes, input-method shortcut changes, or merge are authorized.

## Acceptance criteria for the gesture vocabulary

`GESTURE_RECOGNITION_STABLE` requires all of:

1. all intended A samples can be classified as A without needing knowledge of external receiver state;
2. all intended B samples contain exactly one short first tap followed by one long second press;
3. all intentional single taps resolve to no-action and do not alias A or B;
4. raw HID edges are complete and no repeated/debounced phantom edges alter the intended class;
5. at least one practical threshold pair has non-trivial margin from the observed timing distributions rather than classifying only at a knife-edge boundary.

If samples classify only by using a very narrow double window or several natural B samples cross the window boundary, return `DOUBLE_HOLD_GESTURE_MARGIN_INSUFFICIENT` and adjust UX/threshold design before touching voice trigger ownership.

## Architectural work after recognition passes

Only after the gesture vocabulary is accepted should implementation design proceed for:

```text
recognized receiver owner
-> selected trigger key
-> first-PCM authorization
-> one balanced momentary trigger transaction
-> release/output drain
-> transaction complete
```

The unselected receiver must receive no trigger edge. `persistentOpen` must not be the ownership authority for this dual-receiver mode.
