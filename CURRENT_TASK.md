# RemoteOrbit Current Task

## Current task — DUAL-RECEIVER MOMENTARY ROUTING DESIGN

- **Status:** READY FOR ARCHITECTURE / IMPLEMENTATION PLAN
- **Task ID:** `RO-DUAL-RECEIVER-MOMENTARY-ROUTING-018`
- **Previous task:** `RO-DUAL-RECEIVER-GESTURE-RECOGNITION-017` — CLOSED / `GESTURE_RECOGNITION_STABLE`
- **Candidate branch:** `codex/disabled-short-classifier-regression-fix`
- **Candidate HEAD:** `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`
- **Product source mutation:** NOT YET AUTHORIZED
- **Rebuild/reinstall/restart:** NOT YET AUTHORIZED
- **Merge:** FORBIDDEN

## Accepted product contract

```text
Direct LONG                  -> Receiver A -> Left Option
Double-tap, hold second down -> Receiver B -> Right Option
Quick single tap             -> no action
```

Both A and B are independent momentary voice transactions. Dual-receiver mode must not depend on external Persistent Session state.

## Accepted timing baseline

Recognition hardware evidence supports:

```text
LONG_THRESHOLD_MS = 350
DOUBLE_WINDOW_MS   = 300
```

These are the recommended first implementation values, not immutable product constants.

Why:
- 200 ms double window failed 2/10 B samples.
- 250 ms passed but had only 10.453 ms minimum inter-press margin.
- 300 ms passed all samples with 60.453 ms minimum inter-press margin.
- 350 ms LONG has large margin for both direct and second holds and matches the generic recognizer's existing long threshold.
- 400/350 adds avoidable latency without changing recognition correctness on the captured sample.

## Required architecture properties

1. One physical microphone gesture creates exactly one `VoiceTransaction`.
2. Transaction owner is either Receiver A or Receiver B, never both.
3. The unselected receiver receives no mapped or synthetic trigger edge.
4. Receiver ownership must resolve before trigger release to the external input method.
5. Remote audio remains hold-bound and first-PCM-gated where practical.
6. Physical release + output drain must balance only the selected receiver trigger.
7. A quick single tap must expire to no action after the double window.
8. No Persistent Session state is used as dual-receiver authority.
9. Existing PR #14 classifier corrective remains independent and must not be regressed.

## Source facts to account for

- The generic `ButtonGestureRecognizer` already supports long and second-tap long (`clickCount = 2`) but the microphone path bypasses it when remote microphone LONG is active.
- `VoicePressCoordinator` currently owns microphone SHORT/LONG, BLE route, first PCM, trigger gate, release, and output drain.
- Device-scoped `hidutil` mapping currently points the remote microphone F5 usage at one active trigger key at a time.
- Therefore dual-receiver routing cannot be implemented by settings alone. Pre-classification trigger leakage must be prevented.

## Design work required before construction

Produce a bounded implementation design that compares at least:

### Design A — microphone-specific gesture classifier inside / adjacent to VoicePressCoordinator

Keep voice-specific ownership, BLE and drain semantics together. Add a first-tap pending state and second-hold path that selects receiver B while direct hold selects A.

### Design B — adapt/reuse generic ButtonGestureRecognizer classification for microphone, then hand the classified hold into a voice transaction owner

Reuse existing gesture timing semantics but do not let generic action injection own voice trigger/audio lifetime.

For each design, audit:
- trigger leakage risk with current hidutil mapping;
- first-PCM authorization ordering;
- how Left Option vs Right Option is emitted after classification;
- release/up balancing;
- rapid repress and tail-drain interaction;
- BLE reconnect/loss handling;
- required changes to Settings/schema;
- migration of existing single-receiver behavior;
- testability and regression surface.

## Implementation boundary

Do not start product-source edits until the design chooses one trigger-ownership mechanism that guarantees the unselected receiver sees no pre-classification edge.

The preferred design should minimize new state and preserve existing proven BLE/audio drain behavior.

## Verification plan required in the implementation design

At minimum specify RED/GREEN tests for:

```text
single tap -> no trigger
A direct hold -> Left Option only
B double-hold -> Right Option only
A never emits Right Option
B never emits Left Option
first tap of B emits neither receiver trigger
first PCM gates selected trigger
release/drain emits exactly one balanced up for selected receiver
no trigger under failed/no-audio path
rapid re-press does not cross receiver ownership
transport loss cannot leave either trigger stuck
```

Hardware acceptance after build must separately verify A and B against two real receiver shortcuts.

## Executor instruction

Until a concrete implementation card replaces this task, local AI should perform read-only design/audit only and must not edit product source.
