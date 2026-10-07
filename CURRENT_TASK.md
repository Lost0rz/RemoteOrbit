# RemoteOrbit Current Task

## Current task — DUAL-RECEIVER HOLD-GESTURE ARCHITECTURE DESIGN

- **Status:** HOLD / USER INTERACTION CONTRACT APPROVAL REQUIRED
- **Task ID:** `RO-DUAL-RECEIVER-GESTURE-ARCHITECTURE-016`
- **Candidate branch:** `codex/disabled-short-classifier-regression-fix`
- **Candidate HEAD:** `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`
- **Source mutation:** FORBIDDEN
- **New probes:** FORBIDDEN
- **Hardware experiment:** FORBIDDEN until the interaction contract is selected
- **Rebuild/reinstall:** FORBIDDEN
- **Merge:** FORBIDDEN

## Why this supersedes the prior cross-receiver capture

The user clarified a hard hardware constraint: the Xiaomi remote microphone produces useful audio only while the physical microphone button is held. Therefore a two-receiver product cannot treat one receiver as a tap-only audio path and the other as the hold path if both are expected to receive Xiaomi remote audio.

The previous `RO-CROSS-RECEIVER-SESSION-OWNERSHIP-015` capture is superseded as the immediate task. It may still be useful later for a regression sample, but the product contract must be chosen first.

## Accepted source-audit facts

1. `VoicePressCoordinator` has one persistent owner model: `idle | persistentOpen`.
2. When a gesture starts while `persistentOpen`, the policy becomes `audioOnly`, and the current implementation suppresses the momentary mapped trigger. The LONG is designed to continue the same persistent receiver, not select a second receiver.
3. RemoteOrbit cannot authoritatively observe whether an external IME voice UI/session was manually or independently closed; persistent ownership is internal.
4. Repeated Persistent LONG segments intentionally reuse the same external Session without an explicit external trigger transaction per segment. This is a plausible architecture risk for duplicate/repeated composition, but current diagnostics do not prove the external text-commit cause.
5. The generic `ButtonGestureRecognizer` already supports single tap, double tap, long press, and a second-tap long represented by `clickCount = 2`.
6. The microphone button does not currently use that generic gesture path when remote-microphone LONG is enabled; it is routed directly to `VoicePressCoordinator`.
7. Current device-scoped HID mapping has one active mapped trigger target at a time. A per-gesture receiver choice is therefore not a settings-only change.

## Candidate interaction contracts

### Option A — one microphone button, two hold gestures

```text
Direct LONG                  -> Receiver A
Double-tap, hold second down -> Receiver B
```

Both receivers use independent momentary voice transactions. No external persistent Session is kept alive between utterances.

Required architectural property:
- receiver selection must resolve before the selected receiver sees its trigger;
- the unselected receiver must receive no trigger edge;
- first remote PCM remains the authorization boundary for the selected receiver trigger where practical;
- release/output drain balances only that transaction.

This is the preferred contract when one-button UX is the highest priority, but it requires redesign of microphone gesture routing and trigger ownership.

### Option B — explicit receiver selector + one microphone LONG

```text
Separate remote control selects Receiver A or B while idle
Microphone LONG -> currently selected receiver
```

No external persistent Session is kept alive between utterances.

This is the preferred contract when reliability/minimum implementation risk is the highest priority because receiver identity is known before microphone down and the existing physical/system mapped trigger architecture can largely be preserved.

### Option C — Persistent A plus LONG handoff to B

```text
SHORT -> keep Receiver A externally open
LONG -> suspend/close A, run Receiver B, optionally restore A
```

Not recommended as the default architecture. RemoteOrbit does not own authoritative external IME Session state, so coordinating two external Session owners adds avoidable state drift and composition/transaction risk.

## Recommended architecture principle

For a two-receiver workflow, model every spoken hold as exactly one explicit `VoiceTransaction` with one receiver owner and one balanced trigger/audio lifetime.

Conceptually:

```text
VoiceTransaction
- transaction_id
- receiver_id
- gesture_kind
- trigger_key
- physical_press_id
- trigger ownership
- first-PCM authorization
- audio route lifetime
- release/output-drain completion
```

Do not use `persistentOpen` as global authority for the dual-receiver mode.

A single-receiver Persistent mode may remain as a separate optional product mode if desired, but it must not be the ownership model for two independent receivers.

## Evidence status of historical problems

### Persistent Session exits when LONG begins

Current source intends the opposite: while internally `persistentOpen`, LONG is `audioOnly` and should leave the Session open. If the external receiver visibly exits, current diagnostics can prove the internal policy and trigger/gate edges but cannot prove the receiver's own Session transition. External/internal ownership drift or trigger leakage are plausible; exact historical cause is not proven.

### Repeated text after segmented Persistent LONGs

Current source intentionally sends multiple audio-only segments into one long-lived external Persistent Session without a fresh external transaction boundary per hold. This is a plausible contributor to receiver recomposition/duplicate commits. Exact duplicate-text causality is not proven because RemoteOrbit does not observe the receiver's composition/commit stream.

The abandoned PR #16 explored per-segment transaction isolation, which supports treating transaction boundaries as a real design concern, but it is not an accepted implementation and must not be revived wholesale.

## User decision required

Choose the interaction contract before implementation planning:

- **A** — direct LONG = Receiver A; double-tap + hold second = Receiver B.
- **B** — select Receiver A/B first with another control; microphone LONG uses the selected receiver.

Option C is not recommended.

After the user selects A or B, write the architecture spec and implementation plan. Do not modify product source before that approval.

## Current executor instruction

If local AI fetches this task now, return only:

`HOLD_FOR_DUAL_RECEIVER_GESTURE_DESIGN_APPROVAL`
