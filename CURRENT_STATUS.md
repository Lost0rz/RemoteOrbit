# CURRENT_STATUS

Last updated: 2026-10-08
State: DUAL-RECEIVER GESTURE RECOGNITION ACCEPTED / ROUTING DESIGN READY
Repository: `Lost0rz/RemoteOrbit`

This file is the authority for mutable current project state. Historical detail remains preserved in Git history.

## Control-plane integrity

- Recognition task control HEAD was `97382fba47da784fc85040af205cfbafe42de39b`.
- Candidate branch remains `codex/disabled-short-classifier-regression-fix` at exact HEAD `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`.
- Installed hardware-test baseline during recognition: PID `79232`, source HEAD `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`, executable SHA-256 `a033e86a92b02175a498bba3232c5ae8b72719caef781cb74c3187e8e64ed017`.
- Candidate remains unmerged.

## Closed single-input-method finding

The prior fast-click Doubao anomaly was caused by shortcut collision: Doubao click/toggle mode and hold-to-talk mode were both bound to Left Option. Separating those two receiver semantics removes that specific unwanted fast-click Session activation.

The independent PR #14 Disabled-SHORT classifier regression remains real; the candidate correctly restores normal short/long classification.

## Accepted dual-receiver interaction

```text
Direct LONG                  -> Receiver A
Double-tap, hold second down -> Receiver B
```

Intended eventual receiver triggers:

```text
Receiver A -> Left Option
Receiver B -> Right Option
```

Both receivers should use independent momentary voice transactions. Dual-receiver mode must not depend on a long-lived external Persistent Session.

## Gesture recognition result — ACCEPTED

Task `RO-DUAL-RECEIVER-GESTURE-RECOGNITION-017` completed with `GESTURE_RECOGNITION_STABLE`.

Natural physical samples:

```text
A_DIRECT_LONG:       10 / 10
B_DOUBLE_HOLD:       10 / 10
NO_ACTION_SINGLE_TAP: 5 / 5
```

Observed ranges:

```text
A direct hold:            1813.421 .. 2221.483 ms
B first tap:               145.551 .. 180.196 ms
B first-up -> second-down:  74.476 .. 239.547 ms
B second hold:            1440.032 .. 2175.514 ms
C single tap:              180.995 .. 239.765 ms
```

No unexplained extra HID edges altered classification. The B capture recorded debounce-suppressed edges, but the raw state records matched them and the accepted 10 B gestures remained unambiguous.

Temporary neutral trigger Left Control was validated, used only for timing isolation, and restored to the original Left Option. No product source, receiver shortcut, build, install, restart, or merge occurred.

## Threshold audit

Offline replay showed:

- 200 ms double window is too narrow: only 8/10 B gestures classify correctly; two would fall through as A.
- 250 ms double window classifies all samples but has only `10.453 ms` minimum inter-press margin and is too fragile.
- 300 ms double window classifies all samples with `60.453 ms` minimum inter-press margin.
- 350 ms double window gives more margin but adds another 50 ms to single-tap no-action resolution.
- LONG thresholds 300/350/400 ms all classify every captured sample correctly.

Recommended first implementation constants:

```text
LONG_THRESHOLD_MS = 350
DOUBLE_WINDOW_MS   = 300
```

Rationale: preserves substantial margin while avoiding the unnecessary latency of 400/350. It also aligns the long threshold with the repository's existing generic `ButtonGestureRecognizer` 350 ms contract.

## Architecture constraint for implementation

The microphone button currently bypasses generic advanced gesture routing and enters `VoicePressCoordinator` directly. Existing device-scoped HID mapping also has only one active trigger target at a time.

Therefore implementation is not a settings-only change. It must establish a per-utterance owner before releasing a receiver trigger:

```text
physical gesture
-> classify A_DIRECT_LONG or B_DOUBLE_HOLD
-> select exactly one receiver / trigger key
-> first-PCM authorization
-> emit/hold only the selected receiver trigger
-> release + output drain
-> balanced transaction complete
```

The unselected receiver must receive no trigger edge.

## Historical Persistent issues

The old Persistent model remains unsuitable as authority for dual-receiver mode because:

- RemoteOrbit cannot authoritatively observe external IME Session state;
- a Persistent LONG is currently modeled as audio-only continuation into the existing owner;
- repeated audio-only segments reuse one external Session without explicit per-hold receiver transaction boundaries;
- these properties are plausible contributors to historical visible Session drift and repeated text, although exact external text-commit causality was not proven.

## Next step

Proceed to a bounded architecture/implementation plan for dual-momentary routing using the accepted gesture contract and the recommended `350 ms / 300 ms` timing baseline. Do not merge or replace the installed runtime until implementation has independent code review and hardware acceptance.
