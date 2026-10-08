# CURRENT_STATUS

Last updated: 2026-10-08
State: SYSTEM-MAPPED DUAL-RECEIVER DESIGN REVIEW
Repository: `Lost0rz/RemoteOrbit`

This file is the authority for mutable current project state. Historical detail remains preserved in Git history.

## Control-plane authority

- Previous architecture review HEAD: `12cad4fb129e80f14b606c642893a7ad4a7fa6f5`.
- Preserved dual-receiver implementation branch: `codex/dual-receiver-momentary-routing-v1`.
- Preserved branch/control HEAD: `c90edbf73ad9b0642fa344734571c0e806c0eb73`.
- Preserved product HEAD: `ef29186e25c64cd4d1d7209cb2a41f95c51d4a11`.
- No merge is authorized.

## Accepted early-hardware result — FACT

The 019 synthetic-trigger candidate failed Receiver A acceptance:

```text
5 x direct LONG
gesture classified A: 5/5
remote audio lifecycle: 5/5
synthetic Left Option DOWN/UP: 5/5
Receiver A externally opened: 0/5
```

Classification remains:

`SYNTHETIC_RECEIVER_TRIGGER_NOT_ACCEPTED`

This rejects CGEvent synthetic modifier as the normal A/B receiver trigger backend. It does not invalidate the accepted gesture classifier, BLE path, first-PCM gate, transaction ownership, or release/drain behavior.

## Historical architecture correction — FACT

Merged PR #13 (`7f6f703fadd5e89c087059d3167c0c4c5253fd6b`) established the working normal voice-trigger path as:

```text
remote microphone F5
-> device-scoped hidutil mapping
-> configured modifier key
-> system-mapped hardware-style modifier event
-> HardwareOptionGate / filter ownership
-> synthetic only as fallback
```

The previous 020 virtual-HID/provider direction is superseded. The product already has a proven system-mapped trigger path; the dual-receiver task only needs to distinguish which mapping owns the next physical press.

## Retained product contract

```text
Direct LONG                   -> Receiver A
Quick first tap + second LONG -> Receiver B
Quick single tap              -> no action

A initial key = Left Option
B initial key = Right Option
LONG_THRESHOLD_MS = 350
DOUBLE_WINDOW_MS   = 300
```

Both A and B remain independent momentary transactions. Persistent Session is not receiver authority.

## Corrected selected architecture

Design spec:

`docs/superpowers/specs/2026-10-08-dual-receiver-system-mapped-trigger-design.md`

### Idle / direct A

```text
F5 mapping = A (Left Option)
physical F5 down
-> system-mapped A edge
-> HardwareOptionGate captures/defer
-> direct hold >= 350 ms
-> remote audio activation
-> first PCM
-> release captured A DOWN
-> stream
-> physical release / drain
-> matching A UP
```

This reuses the original accepted trigger path. No new trigger backend is needed for A.

### First quick tap arms B

If the first press releases before 350 ms:

```text
discard captured A edge(s)
-> Receiver A sees nothing
-> immediately switch device-scoped F5 mapping A -> B
-> verify B mapping apply/readback
-> WAITING_SECOND_PRESS <= 300 ms
```

If no second press arrives, restore B -> A and cancel pending prewarm.

### Second press owns B

If the second physical F5 down arrives while B mapping is verified armed:

```text
physical F5 down
-> system-mapped B (Right Option) edge
-> HardwareOptionGate captures/defer
-> second hold >= 350 ms
-> classify B
-> activate remote audio
-> first PCM
-> release captured B DOWN
-> stream
-> physical release / drain
-> matching B UP
-> restore mapping B -> A after B release ownership completes
```

If second press releases before 350 ms, discard B edge(s), restore A, and open neither receiver.

## Authority / safety invariants

- `HIDMonitor` remains the sole raw HID owner.
- Existing `HardwareOptionGate` / filter remains the sole mapped-edge owner.
- `RemoteVoiceKeyMapping` remains the sole device-scoped mapping authority.
- Normal A/B transactions do not use CGEvent synthetic trigger fallback.
- A -> B and B -> A mapping transitions must be verified through the existing mapping seam.
- If A -> B arm fails, B is unavailable and the gesture fails closed; do not leak A and do not synthesize B.
- If B -> A restore fails, do not accept a new gesture until mapping authority is reconciled.
- Generic `ButtonGestureRecognizer`, BLE codec, tail/drain timing, Persistent Session semantics, and diagnostic authority remain unchanged.

## Reuse from 019

Retain selectively:

- Disabled-SHORT classifier corrective;
- `DualReceiverVoiceGestureRecognizer` 350/300 timing/state model;
- independent Receiver-B preference/settings;
- one semantic classifier only / already-classified hold entry;
- transport-only prewarm;
- first-PCM authorization boundary;
- release/drain/loss/disconnect ownership;
- fail-closed dual-mode runtime gating.

Replace only the normal A/B trigger backend that currently routes selected keys through synthetic `VoiceOptionTrigger` CGEvent.

## Only genuinely new uncertainty

Receiver acceptance of system-mapped Left Option is already historically established and does not need a new provider spike.

The new timing dependency is only whether A -> B mapping apply/readback completes before the user's second physical press. Closed gesture evidence observed first-UP -> second-DOWN gaps of approximately `74.476–239.547 ms`.

Implementation must measure mapping transition latency and gate B on a verified `B_MAPPING_READY` state. If the second press arrives before readiness, fail that B attempt closed rather than leak A or synthesize B.

## Next transition

Current task: `RO-DUAL-RECEIVER-SYSTEM-MAPPED-TRIGGER-020`.

Product source mutation remains forbidden until the user reviews/approves the corrected written design. No Karabiner/CoreHID provider installation or virtual-HID feasibility spike is authorized.