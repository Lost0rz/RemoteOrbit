# RemoteOrbit Current Task

## Current task — REAL HID KEYBOARD TRIGGER BACKEND ARCHITECTURE REVIEW

- **Status:** HOLD / USER ARCHITECTURE APPROVAL REQUIRED
- **Task ID:** `RO-REAL-HID-TRIGGER-BACKEND-020`
- **Previous task:** `RO-DUAL-RECEIVER-MOMENTARY-ROUTING-019` — STOPPED / `SYNTHETIC_RECEIVER_TRIGGER_NOT_ACCEPTED`
- **Preserved implementation branch:** `codex/dual-receiver-momentary-routing-v1`
- **Preserved branch HEAD:** `c90edbf73ad9b0642fa344734571c0e806c0eb73`
- **Preserved product HEAD:** `ef29186e25c64cd4d1d7209cb2a41f95c51d4a11`
- **Product source mutation:** FORBIDDEN until architecture path is approved
- **Runtime/provider installation:** FORBIDDEN until architecture path is approved
- **Receiver shortcut changes:** FORBIDDEN
- **Merge:** FORBIDDEN

## Accepted failure evidence

Receiver A hardware gate result:

```text
5 x direct LONG
gesture classified A: 5/5
remote audio lifecycle: 5/5
synthetic Left Option DOWN/UP: 5/5
Receiver A externally opened: 0/5
```

Final classification:

`SYNTHETIC_RECEIVER_TRIGGER_NOT_ACCEPTED`

Do not test Receiver B on this synthetic-trigger candidate.

## Product contract retained

```text
Direct LONG                   -> Receiver A
Quick first tap + second LONG -> Receiver B
Quick single tap              -> no action

A initial key = Left Option
B initial key = Right Option
LONG = 350 ms
DOUBLE WINDOW = 300 ms
```

Both A and B remain independent momentary transactions. Persistent Session is not receiver authority.

## Architecture correction

The normal trigger backend must present the selected modifier as a **keyboard HID event/report equivalent to a real keyboard key**, not as a CGEvent synthetic modifier.

Rejected:

```text
classified A/B
-> CGEvent synthetic Left/Right Option
```

Required semantic boundary:

```text
raw remote F5
-> park raw F5
-> classify A/B
-> activate remote audio
-> first decoded PCM
-> real virtual-keyboard HID modifier DOWN for selected key
-> stream
-> release + existing output drain
-> matching HID modifier UP
```

## Architecture candidates

### Option A — Native CoreHID `HIDVirtualDevice`

Target long-term architecture.

Required capability:

`com.apple.developer.hid.virtual.device`

Current ad-hoc packaging cannot be assumed to create the device. Do not implement this path until entitlement/provisioning feasibility is established.

### Option B — Existing Karabiner DriverKit VirtualHID provider

Recommended first feasibility spike.

Purpose is not to adopt Karabiner as the final product automatically. It answers one bounded question cheaply:

`Does a macOS virtual HID keyboard Left Option open Receiver A reliably?`

The provider has a real DriverKit virtual keyboard and client/daemon path. Using it may require system-extension installation/approval and privileged daemon execution. Those are explicit side effects and require user approval before execution.

### Option C — Physical keyboard bridge

Fallback only if supported software virtual-HID routes are unavailable.

## Recommended next step — SPIKE ONLY

After user approval, authorize a **bounded feasibility spike** that does not modify RemoteOrbit product code.

Spike question:

`Can an existing real virtual-HID keyboard provider emit Left Option such that Receiver A opens reliably, unlike CGEvent synthetic Option?`

Preferred probe sequence:

1. read-only inspect whether a compatible Karabiner VirtualHID provider/driver/daemon is already installed;
2. if absent, STOP before installation and report the exact dependency/approval needed;
3. if already available and healthy, use its smallest isolated example/client path to emit one Left Option DOWN/UP under explicit user-controlled receiver observation;
4. only after one successful proof, run 5 repeated Left Option momentary trials;
5. do not modify RemoteOrbit source, A/B classifier, BLE code, settings, receiver shortcuts, TCC, audio driver, or CoreAudio;
6. do not leave a modifier held; every probe must be balanced DOWN/UP with cleanup.

Expected spike result labels:

```text
REAL_HID_PROVIDER_UNAVAILABLE
REAL_HID_LEFT_OPTION_REJECTED
REAL_HID_LEFT_OPTION_ACCEPTED_5_OF_5
```

If accepted 5/5, return to Web to write the production trigger-backend design spec. Do not wire the provider into RemoteOrbit during the spike.

## Approval gate

Until the user approves the recommended real-HID feasibility spike, local AI must not install a provider, activate a system extension, run a privileged virtual-HID daemon, emit virtual keyboard events, or modify product source.

Return if asked to proceed without approval:

`HOLD_FOR_REAL_HID_BACKEND_ARCHITECTURE_APPROVAL`
