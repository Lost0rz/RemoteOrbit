# RemoteOrbit Current Task

## Current task — DUAL-RECEIVER HOLD-GESTURE RECOGNITION STABILITY

- **Status:** ACTIVE / HARDWARE TIMING CAPTURE AUTHORIZED
- **Task ID:** `RO-DUAL-RECEIVER-GESTURE-RECOGNITION-017`
- **Candidate branch:** `codex/disabled-short-classifier-regression-fix`
- **Candidate HEAD:** `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`
- **Source mutation:** FORBIDDEN
- **New probes:** FORBIDDEN
- **Rebuild/reinstall:** FORBIDDEN
- **Restart:** FORBIDDEN unless runtime is absent; otherwise STOP and report
- **Merge:** FORBIDDEN

## Selected interaction contract

The user approved:

```text
Direct LONG                  -> Receiver A
Double-tap, hold second down -> Receiver B
```

Eventual intended receiver triggers are:

```text
Receiver A -> Left Option
Receiver B -> Right Option
```

Do not connect those real receiver shortcuts during this task. This task tests physical gesture recognizability only.

## Goal

Determine whether the Xiaomi remote microphone button can reliably distinguish, under natural user operation:

```text
A_DIRECT_LONG
B_DOUBLE_HOLD
NO_ACTION_SINGLE_TAP
```

Use only existing raw HID / voice diagnostics. Do not change product behavior or add instrumentation.

## Important source facts

- Generic `ButtonGestureRecognizer` already models second-tap long with `clickCount = 2`.
- Its current constants are `longPressThreshold = 0.35 s` and `doubleTapWindow = 0.25 s`.
- Current microphone voice path bypasses the generic recognizer and uses `VoicePressCoordinator`, whose hold threshold is 0.30 s.
- These constants are comparison points only. This task must measure real user timing first and classify captured timings offline.

## Gate 0 — freshness and isolation

1. `git fetch origin --prune`.
2. Read latest `AGENTS.md`, `CURRENT_STATUS.md`, and this task from `origin/main`.
3. Verify candidate/runtime identity and existing diagnostic readability.
4. Verify no visible Receiver A/B voice Session is open.
5. Record the actual current receiver shortcuts and RemoteOrbit trigger settings without changing the receiver applications.
6. Establish a neutral RemoteOrbit momentary trigger for this timing-only test.

Preferred neutral key is `Left Control`, but it is not automatically trusted. First ask the user to physically tap Left Control once with the remote untouched and report whether either receiver opens, input source switches, or any other meaningful action occurs.

If physical Left Control has any receiver/system semantic that makes it unsafe as a neutral trigger:

```text
NEUTRAL_TRIGGER_UNAVAILABLE
```

STOP.

If neutral, use the normal RemoteOrbit UI only to temporarily set the momentary trigger to Left Control. Keep SHORT Disabled. Do not alter Receiver A/B shortcut settings. Verify HID mapping/readback/filter target = Left Control.

Record the original RemoteOrbit momentary trigger for restoration.

## Gate 1 — fresh append-only baseline

Create a fresh evidence directory under the existing RemoteOrbit incident evidence root.

Do not clear or rotate logs.

Record/hash:

```text
wall-clock baseline
runtime PID/source HEAD/binary SHA
voice log path/size/record count/last seq
app log path/size/line count/last relevant timestamp
raw HID last report sequence
SHORT binding
original momentary trigger
neutral momentary trigger
```

Then return only:

`READY_FOR_GESTURE_SET_A — perform 10 natural direct LONG holds, one at a time; speak nothing; pause about 1 second between attempts.`

## Gate 2 — A_DIRECT_LONG capture

User performs 10 natural direct LONG holds.

Do not coach the user to hit a precise millisecond threshold. The goal is natural operation.

For each attempt identify the raw physical microphone down/up edges and derive:

```text
sample_index
raw_down_sequence
raw_up_sequence
press_duration_ms
extra_edges
debounce_suppressed_edges
```

Reject the set if attempts cannot be unambiguously segmented from raw HID edges.

Seal/hash the A boundary.

Return only:

`READY_FOR_GESTURE_SET_B — perform 10 natural double-holds: quick first tap/release, then press again and keep the second press held LONG; speak nothing; pause about 1 second between attempts.`

## Gate 3 — B_DOUBLE_HOLD capture

User performs 10 natural double-hold gestures.

For each attempt derive:

```text
sample_index
first_down_sequence
first_up_sequence
second_down_sequence
second_up_sequence
first_press_duration_ms
first_up_to_second_down_ms
second_press_duration_ms
total_gesture_duration_ms
extra_edges
debounce_suppressed_edges
```

The first tap must be physically short and the second press physically long. Do not use current app classification as the authority; raw HID timing is the authority for this recognition study.

Seal/hash the B boundary.

Return only:

`READY_FOR_GESTURE_SET_C — perform 5 natural quick single taps only; do not perform a second press; pause about 1 second between attempts.`

## Gate 4 — NO_ACTION_SINGLE_TAP capture

User performs 5 natural quick single taps.

For each derive:

```text
sample_index
raw_down_sequence
raw_up_sequence
press_duration_ms
unexpected_second_down_within_350ms
extra_edges
debounce_suppressed_edges
```

Seal/hash the C boundary.

## Gate 5 — offline threshold replay

Do not change the live app.

Replay only the captured physical timing samples against this matrix:

```text
LONG_THRESHOLD_MS = 250, 300, 350, 400
DOUBLE_WINDOW_MS   = 200, 250, 300, 350
```

Classification contract:

```text
A_DIRECT_LONG:
- no completed short-tap prefix waiting inside the double window
- first/only press duration >= LONG_THRESHOLD_MS

B_DOUBLE_HOLD:
- first press duration < LONG_THRESHOLD_MS
- second down begins <= DOUBLE_WINDOW_MS after first up
- second press duration >= LONG_THRESHOLD_MS

NO_ACTION_SINGLE_TAP:
- first press duration < LONG_THRESHOLD_MS
- no second down <= DOUBLE_WINDOW_MS
- resolves to no action after the double window expires
```

For each threshold pair report:

```text
A_correct / 10
B_correct / 10
C_correct / 5
false_A
false_B
unclassified
minimum_A_long_margin_ms
minimum_B_first_tap_short_margin_ms
minimum_B_double_gap_margin_ms
minimum_B_second_long_margin_ms
```

Where margins are distances from the selected thresholds; negative means the intended sample crosses the boundary.

Prefer a threshold pair that gives perfect intended classification AND meaningful margin. Do not pick a pair merely because it happens to classify all 25 samples at a knife-edge.

Also report empirical distributions:

```text
A press duration: min / median / p90 / max
B first press: min / median / p90 / max
B first-up -> second-down gap: min / median / p90 / max
B second press: min / median / p90 / max
C press duration: min / median / p90 / max
```

## Gate 6 — restore test isolation setting

Using normal RemoteOrbit UI only, restore the original momentary trigger exactly.

Verify HID mapping/readback/filter target matches the restored key.

Do not restart.

## Decision

Return `GESTURE_RECOGNITION_STABLE` only if:

1. all 10 A samples can be classified as A;
2. all 10 B samples have one short first press + one qualifying second long press;
3. all 5 C samples resolve to no action;
4. there are no unexplained raw HID extra edges that alter classification;
5. at least one practical threshold pair has positive, non-trivial margin on A hold, B first-tap shortness, B inter-press gap, and B second hold.

If exact classification is possible only with a narrow/fragile double window or natural B samples repeatedly straddle the chosen window, return:

`DOUBLE_HOLD_GESTURE_MARGIN_INSUFFICIENT`

If raw HID reports themselves contain inconsistent/phantom edges that prevent reliable segmentation, return:

`RAW_HID_GESTURE_BOUNDARY_UNSTABLE`

Do not implement receiver routing in this task.

## Required final report

```text
TASK_ID: RO-DUAL-RECEIVER-GESTURE-RECOGNITION-017
CONTROL_HEAD:
CANDIDATE_HEAD:
INSTALLED_PID:
INSTALLED_SOURCE_HEAD:
INSTALLED_SHA256:

ORIGINAL_MOMENTARY_TRIGGER:
NEUTRAL_TRIGGER:
NEUTRAL_TRIGGER_VALIDATED:
NEUTRAL_TRIGGER_RESTORED:

A_SAMPLE_COUNT:
A_DURATIONS_MS:
A_EXTRA_EDGE_COUNT:

B_SAMPLE_COUNT:
B_FIRST_PRESS_DURATIONS_MS:
B_INTERPRESS_GAPS_MS:
B_SECOND_PRESS_DURATIONS_MS:
B_EXTRA_EDGE_COUNT:

C_SAMPLE_COUNT:
C_DURATIONS_MS:
C_UNEXPECTED_SECOND_EDGE_COUNT:

THRESHOLD_MATRIX_RESULT:
BEST_THRESHOLD_PAIR:
BEST_PAIR_MARGINS:

PRODUCT_SOURCE_CHANGED: NO
NEW_PROBES_ADDED: NO
REBUILD_OR_REINSTALL: NO
APP_RESTARTED: NO
RECEIVER_SHORTCUTS_CHANGED: NO
MERGED: NO

FINAL_STATE:
```
