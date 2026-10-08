# RemoteOrbit Current Task

## Current task — DUAL-RECEIVER SYSTEM-MAPPED TRIGGER DESIGN REVIEW

- **Status:** HOLD / USER DESIGN APPROVAL REQUIRED
- **Task ID:** `RO-DUAL-RECEIVER-SYSTEM-MAPPED-TRIGGER-020`
- **Previous task:** `RO-DUAL-RECEIVER-MOMENTARY-ROUTING-019` — STOPPED / `SYNTHETIC_RECEIVER_TRIGGER_NOT_ACCEPTED`
- **Superseded review:** `RO-REAL-HID-TRIGGER-BACKEND-020` virtual-HID/provider direction — SUPERSEDED
- **Design spec:** `docs/superpowers/specs/2026-10-08-dual-receiver-system-mapped-trigger-design.md`
- **Preserved implementation branch:** `codex/dual-receiver-momentary-routing-v1`
- **Preserved branch HEAD:** `c90edbf73ad9b0642fa344734571c0e806c0eb73`
- **Preserved product HEAD:** `ef29186e25c64cd4d1d7209cb2a41f95c51d4a11`
- **Product source mutation:** FORBIDDEN until design approval and implementation plan audit
- **Provider/system-extension installation:** FORBIDDEN / NOT NEEDED FOR CURRENT DESIGN
- **Receiver shortcut changes:** FORBIDDEN
- **Merge:** FORBIDDEN

## Accepted facts

### Original trigger path worked

Merged PR #13 established the normal trigger path as device-scoped `hidutil` mapping plus hardware/system-mapped modifier ownership, with synthetic trigger only as fallback.

Therefore Receiver A's acceptance of the original system-mapped Left Option path is historical accepted evidence. Do not run a Karabiner/CoreHID compatibility spike for this question.

### Synthetic normal path failed

019 early hardware gate:

```text
A gesture classification: 5/5
remote audio lifecycle: 5/5
synthetic Left Option DOWN/UP: 5/5
Receiver A external open: 0/5
```

Do not continue synthetic Receiver-B acceptance.

## Retained product contract

```text
Direct LONG                   -> Receiver A
Quick first tap + second LONG -> Receiver B
Quick single tap              -> no action

A initial key = Left Option
B initial key = Right Option
LONG = 350 ms
DOUBLE WINDOW = 300 ms
```

## Corrected architecture under review

### A / idle mapping

```text
RemoteVoiceKeyMapping target = A
physical F5
-> system-mapped A edge
-> HardwareOptionGate capture/defer
-> direct-long classification
-> remote audio
-> first PCM
-> captured A DOWN release
-> release/drain
-> captured A UP
```

### First quick tap -> arm B mapping

If first physical press releases before LONG threshold:

```text
capture/discard A edge(s)
-> A external edge = 0
-> request mapping A -> B
-> verify apply/readback
-> B_MAPPING_READY
-> wait for second physical press <= 300 ms
```

No second press:

```text
restore B -> A
verify A_MAPPING_READY
cancel prewarm
return idle
```

### Second physical press -> B

Only if `B_MAPPING_READY` before second raw F5 down:

```text
second physical F5
-> system-mapped B edge
-> HardwareOptionGate capture/defer
-> second hold >= 350 ms
-> classify B
-> remote audio
-> first PCM
-> captured B DOWN release
-> release/drain
-> captured B UP
-> restore B -> A after B ownership completes
```

Second quick release:

```text
discard B edge(s)
restore A
open neither receiver
```

## Safety invariants

- single `HIDMonitor` raw owner;
- single `HardwareOptionGate` / filter mapped-edge owner;
- single `RemoteVoiceKeyMapping` mapping authority;
- no normal A/B CGEvent synthetic trigger;
- no virtual-HID provider/system extension in this design;
- no Persistent Session receiver authority;
- no generic `ButtonGestureRecognizer` timing change;
- no BLE codec/tail/drain redesign;
- mapping transition failure = fail closed;
- second press before `B_MAPPING_READY` = fail that B attempt closed, never leak A and never synthesize B;
- B -> A restore failure blocks the next gesture until reconciliation.

## Preserved 019 implementation to reuse selectively

- Disabled-SHORT corrective;
- pure `DualReceiverVoiceGestureRecognizer`;
- 350/300 timing;
- independent Receiver-B setting;
- already-classified hold entry / no double wait;
- transport prewarm;
- first-PCM authorization;
- release/drain/loss/disconnect ownership;
- fail-closed runtime gating.

Replace only the selected-key synthetic trigger backend with restored system-mapped hardware-edge ownership and A/B mapping transition authority.

## Only new evidence needed during implementation

The receiver's acceptance of the original real/system-mapped path is not the unknown.

The only new timing question is:

`Can A -> B hidutil apply/readback become ready before the second physical press during normal double-hold use?`

Closed gesture evidence gives a natural first-UP -> second-DOWN range of approximately `74.476–239.547 ms`.

Implementation plan must instrument/measure mapping apply/readback latency and keep B fail-closed until verified ready. This measurement belongs inside the implementation task; do not install a new provider or create a separate architecture spike.

## Approval gate

The corrected written design is ready for user review.

Until approved, local AI must not modify product/test code, change runtime settings, change receiver shortcuts, install providers, rebuild/reinstall, perform hardware gestures, or merge.

If asked to implement before approval, return:

`HOLD_FOR_SYSTEM_MAPPED_DUAL_RECEIVER_DESIGN_APPROVAL`