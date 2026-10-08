# Dual-Receiver System-Mapped Trigger Design

Date: 2026-10-08
Task: RO-DUAL-RECEIVER-SYSTEM-MAPPED-TRIGGER-020
State: draft for user review

## Problem correction

The original accepted RemoteOrbit voice-trigger path was already working with a device-scoped `hidutil` mapping from the Xiaomi remote microphone F5 usage to a real macOS modifier key, with `HardwareOptionGate`/filter ownership and synthetic injection only as fallback. The rejected 019 candidate incorrectly replaced this proven normal trigger backend with CGEvent synthetic Left/Right Option for dual-receiver mode. Receiver A rejected that synthetic path 5/5.

The dual-receiver problem is therefore not how to synthesize a keyboard. It is how to preserve the proven system-mapped hardware path while choosing A vs B.

## Product contract

```text
Direct LONG                   -> Receiver A
Quick first tap + second LONG -> Receiver B
Quick single tap              -> no action

A = Left Option initially
B = Right Option initially
LONG = 350 ms
DOUBLE WINDOW = 300 ms
```

## Selected design

Keep the device-scoped remote F5 mapping as the normal trigger source.

### Idle / direct-A state

```text
remote F5 mapping = A (Left Option)
raw F5 down
-> system-mapped A edge exists
-> HardwareOptionGate captures/defers it
-> 350 ms direct-hold classification
-> remote audio activation
-> first PCM
-> release captured A DOWN
-> stream
-> physical release / drain
-> matching captured A UP
```

No new trigger backend is created for A.

### First quick tap / B-arm state

If the first press releases before 350 ms:

```text
captured A down/up = discard; Receiver A sees no edge
immediately switch device-scoped F5 mapping A -> B
enter WAITING_SECOND_PRESS for <= 300 ms
```

If no second press arrives in the window:

```text
restore mapping B -> A
cancel transport prewarm
return idle
```

### Second press / B transaction

If second raw F5 down arrives while the B mapping is successfully armed:

```text
system maps the physical second press to B (Right Option)
HardwareOptionGate captures/defers the B edge
second hold reaches 350 ms
-> classify B
-> activate remote audio
-> first PCM
-> release captured B DOWN
-> stream
-> physical release / drain
-> matching captured B UP
-> restore mapping B -> A only after B release ownership is complete
```

If the second press releases before 350 ms:

```text
discard captured B down/up
restore mapping B -> A
no receiver opens
```

## Authority and fail-closed rules

- `HIDMonitor` remains the sole raw HID owner.
- Existing `HardwareOptionGate`/filter remains the sole mapped-edge owner.
- `RemoteVoiceKeyMapping` remains the sole device-scoped mapping authority.
- No normal A/B transaction uses `VoiceOptionTrigger` synthetic CGEvent.
- Mapping transitions must be verified through the existing injected/testable mapping seam.
- If A->B arm fails, do not accept the second press as B and do not emit synthetic fallback.
- If B->A restore fails, do not start a new gesture until the mapping is reconciled; fail closed.
- Do not change generic `ButtonGestureRecognizer`, BLE codec, tail/drain timing, Persistent Session semantics, or diagnostic authority.

## Reused 019 implementation

Retain conceptually and selectively from `codex/dual-receiver-momentary-routing-v1`:

- Disabled-SHORT classifier corrective;
- `DualReceiverVoiceGestureRecognizer` 350/300 timing/state model;
- independent Receiver-B preference/settings;
- already-classified hold entry (no second 300 ms wait);
- transport-only prewarm;
- first-PCM authorization boundary;
- release/drain/loss/disconnect transaction cleanup;
- fail-closed dual-mode runtime gating.

Reject/replace only the 019 normal trigger backend that routes A/B through `VoiceOptionTrigger.sendDown(...key:)` synthetic CGEvent.

## One genuinely new uncertainty

The original A hardware/system-mapped path is already historically accepted and does not need re-proving as a concept.

The only new timing dependency is whether the device-scoped `hidutil` mapping can switch from A to B during the natural first-UP -> second-DOWN gap. The closed gesture test observed B inter-press gaps of approximately 74.476-239.547 ms.

Implementation should measure mapping apply/readback latency and gate B on a verified mapping-ready state. This is not a receiver-compatibility spike and does not require a new HID provider. If the second physical DOWN arrives before B mapping is verified ready, fail that B attempt closed rather than leak A or synthesize B.

## Acceptance sequence

1. Automated tests prove mapping authority/state transitions, stale callbacks, timeout restore, B quick-release discard, and no synthetic normal path.
2. Hardware gate A: direct LONG 5/5 opens A using the restored original system-mapped path.
3. Hardware gate B: double-hold 5/5 opens B only; first tap opens neither.
4. Quick single 5/5 opens neither and mapping returns to A.
5. Only after these pass proceed to full A/B/A/B and cleanup acceptance.
