# CURRENT_STATUS

Last updated: 2026-10-07
State: SINGLE-IME COLLISION RESOLVED / CROSS-RECEIVER SESSION OWNERSHIP ACTIVE
Repository: `Lost0rz/RemoteOrbit`

This file is the authority for mutable current project state. Historical detail remains preserved in Git history.

## Control-plane integrity

- Previous control HEAD: `e30a8db084d4487144644b6e10f6b2444efe3948`.
- Candidate branch remains `codex/disabled-short-classifier-regression-fix` at exact HEAD `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`.
- Installed candidate remains PID `79232`, source HEAD `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`, executable SHA-256 `a033e86a92b02175a498bba3232c5ae8b72719caef781cb74c3187e8e64ed017` unless a later task records otherwise.
- Candidate remains unmerged.

## Single-input-method incident resolved

The user identified the root cause of the prior unwanted fast-click Session opening in Doubao: Doubao has two independent shortcut semantics — click/toggle Session and hold-to-talk — and both had been bound to Left Option. A brief Left Option from the remote could therefore legitimately activate the click/toggle Session even when RemoteOrbit classified the physical gesture as SHORT and never promoted it to LONG.

Separating the two Doubao shortcuts removes that unwanted fast-click activation. Treat the single-input-method shortcut-collision investigation as complete unless the symptom returns under separated shortcuts.

The separate PR #14 Disabled-SHORT classifier regression remains real and the candidate fix remains relevant: `bypassesShortClassification = false`.

## New user-observed multi-input-method scenario

The user now reports a distinct configuration involving two different input receivers:

```text
Receiver A / Doubao persistent-style shortcut = Left Option
Receiver B / another input method shortcut     = Right Option

Remote short intended to activate Left Option / Receiver A
Remote long intended to activate Right Option / Receiver B
```

The user observes that the two visible voice conversations still interfere or "fight".

This is a new scope. Do not reuse the single-input-method shortcut-collision diagnosis as the explanation.

## Existing state-machine assumption

Current source architecture models one persistent voice-session owner. When a press begins while the persistent Session is already open, `VoicePressCoordinator` selects:

```text
remoteSegmentTriggerPolicy = audioOnly
```

rather than `momentaryTrigger`.

On LONG confirmation in this state, the coordinator attempts to suppress the mapped momentary hardware trigger and keep the current persistent receiver as the session owner. In other words, current architecture assumes:

```text
SHORT opens persistent receiver A
LONG while A remains open -> audio-only continuation into A
```

It does NOT model a cross-receiver handoff:

```text
SHORT opens receiver A
LONG -> transfer ownership from A to separate receiver B
```

## Current interpretation

The two-input-method conflict is therefore most likely one of two classes:

1. **State-model / ownership mismatch:** Receiver A remains persistently open while the user expects LONG to activate independent Receiver B. Two external receivers can then compete for focus/session/audio semantics.
2. **Suppression failure or trigger leakage:** while RemoteOrbit internally selects `audioOnly`, the Right Option momentary path still reaches Receiver B, producing an unintended second active receiver.

These two cases must be separated with one fresh existing-diagnostics capture before any behavior change.

## Next diagnostic boundary

Use existing diagnostics only; add no probes yet.

Fresh sequence to capture:

```text
initial: no visible receiver Session open
1. one SHORT -> Receiver A / Left Option opens
2. verify RemoteOrbit internal session_mode becomes persistent_open
3. exactly one LONG while A is still visibly open
4. user reports which receiver/dialogs are visible and which one reacts
```

For the LONG gesture, extract at minimum:

```text
GESTURE_CLASSIFIED
session_mode
remoteSegmentTriggerPolicy
PERSISTENT_SEGMENT_BEGIN
persistent owner key
momentary configured key
OPTION_GATE / suppression outcome
MAPPED_TRIGGER_EVENT for right_option
synthetic trigger events
AUDIO_START / AUDIO_FIRST / AUDIO_STOP
frontmost/input-source transitions if already available
```

Decision:

- `audioOnly` + no Right Option event + Receiver B does not activate => current architecture is behaving as designed; product requirement must decide whether cross-receiver handoff is desired.
- `audioOnly` but Right Option reaches Receiver B => suppression/ownership bug; isolate exact edge before fixing.
- internal mode is not `persistent_open` after SHORT => persistent ownership state is already drifting and that becomes the first bug to address.

No source change is authorized before this capture.
