# CURRENT_STATUS

Last updated: 2026-10-08
State: ARCHITECTURE REDESIGN HOLD — REAL HID KEYBOARD TRIGGER BACKEND
Repository: `Lost0rz/RemoteOrbit`

This file is the authority for mutable current project state. Historical detail remains preserved in Git history.

## Control-plane authority

- Authoritative `main` before this transition: `edcb4817f9ff9ae3400882f22ec61ec689f7fbaa`.
- Dual-receiver implementation branch: `codex/dual-receiver-momentary-routing-v1`.
- Branch/control HEAD reported at early hardware gate: `c90edbf73ad9b0642fa344734571c0e806c0eb73`.
- Product implementation HEAD installed for the gate: `ef29186e25c64cd4d1d7209cb2a41f95c51d4a11`.
- Installed candidate identity reported for the gate: `/Applications/RemoteOrbit.app`, version `0.2.13` build `42`, Bundle ID `com.lost0rz.RemoteOrbit`, executable SHA-256 `328e66f7d60fbf7c5a5f8330d32ecb133bf34c00e3ae1fb065e70633835734bb`, PID `46412`.
- No merge is authorized.

## Early hardware gate result — FACT

Task `RO-DUAL-RECEIVER-MOMENTARY-ROUTING-019` stopped at the first Receiver-A real-hardware gate with:

`SYNTHETIC_RECEIVER_TRIGGER_NOT_ACCEPTED`

User performed five direct-LONG A attempts. All five gestures:

- classified as direct hold at approximately 362–368 ms;
- started remote audio;
- recorded synthetic Left Option DOWN and matching UP;
- completed AUDIO_STOP, output drain, and momentary transaction cleanup;
- reported `remote_routed=true`;
- did **not** open Receiver A externally: 0/5 accepted.

Therefore the new gesture classifier, BLE/audio activation, first-PCM transaction path, release/drain balance, and selected-key ownership were exercised, but the external receiver did not accept the CGEvent synthetic modifier path as its trigger.

Do not run Receiver-B hardware acceptance on this candidate. Do not proceed to plan Tasks 11/12.

## Historical architecture reconciliation — FACT

Merged PR #13 (`7f6f703fadd5e89c087059d3167c0c4c5253fd6b`) established the accepted configurable voice-trigger architecture as:

- parameterized device-scoped HID mapping;
- parameterized filter/runtime authority;
- synthetic trigger as fallback.

The previously accepted normal path was therefore a hardware/system-mapped HID modifier, not CGEvent synthetic modifier as the primary receiver owner.

The 019 design incorrectly promoted the synthetic fallback class into the normal post-classification dual-receiver trigger backend. The 5/5 Receiver-A rejection confirms that this backend is unsuitable for the tested receiver.

## Preserved implementation from 019

Do not discard the 019 branch wholesale. The following architecture remains useful and should be retained for the next design unless contradicted by new evidence:

```text
Direct LONG                   -> Receiver A
Quick first tap + second LONG -> Receiver B
Quick single tap              -> no action
LONG_THRESHOLD_MS             = 350
DOUBLE_WINDOW_MS              = 300
```

Also retain conceptually:

- pure microphone-specific A/B classifier;
- one semantic classifier only in dual mode;
- F5 parking before receiver selection;
- transport-only prewarm during pending classification;
- explicit per-transaction receiver key ownership;
- first decoded PCM as trigger-DOWN authorization boundary;
- existing release/tail/output-drain ownership;
- independent Receiver-B preference;
- fail-closed behavior when safe trigger ownership cannot be established.

Only the **receiver trigger backend** is now rejected:

```text
CGEvent synthetic modifier as normal A/B trigger owner = REJECTED
```

## Current platform feasibility — verified externally

Apple CoreHID provides `HIDVirtualDevice`, which can emulate a keyboard and dispatch HID input reports to the system. This matches the desired semantic boundary: after A/B classification and first PCM, RemoteOrbit can emit a keyboard HID modifier DOWN and later the matching UP.

However, CoreHID virtual-device creation requires the restricted entitlement:

`com.apple.developer.hid.virtual.device`

RemoteOrbit's current local candidate is ad-hoc signed and does not have an Apple-issued provisioning profile containing that entitlement. Direct CoreHID/IOHIDUserDevice virtual-device construction therefore cannot be assumed testable in the current packaging/signing model.

A mature existing alternative is `pqrs-org/Karabiner-DriverKit-VirtualHIDDevice`, which provides a macOS virtual keyboard recognized like physical hardware through a DriverKit system extension and a daemon/client protocol. It supports macOS 13–26, but requires installation/activation of the system extension and a privileged daemon/client integration. Treat this as an external-provider option, not an invisible library substitution.

## Architecture options now under review

### A — Native CoreHID `HIDVirtualDevice`

Preferred long-term product architecture if the required entitlement can be obtained and incorporated into the signing/provisioning model.

Pros:
- first-party Apple API;
- direct keyboard HID report ownership inside RemoteOrbit;
- no third-party runtime dependency;
- clean A/B transaction boundary after classification.

Blocker:
- restricted entitlement/provisioning; current ad-hoc package cannot validate it as-is.

### B — Karabiner DriverKit VirtualHID provider

Preferred immediate feasibility path if the goal is to validate that a real virtual-HID keyboard modifier is accepted by the receiver before investing in entitlement/distribution work.

Pros:
- known real virtual keyboard device recognized by macOS;
- currently supports macOS 13–26;
- can validate Left Option acceptance independently of CGEvent.

Costs:
- system extension installation/approval;
- privileged daemon/client boundary;
- third-party dependency and protocol-version management;
- not automatically the final product architecture.

### C — External physical USB/BLE keyboard bridge

Strongest hardware equivalence but highest operational/product cost. Keep only as fallback if supported virtual-HID routes are unavailable.

## Current recommendation

Use a **two-stage strategy**:

1. First run a bounded real-HID feasibility spike using an existing virtual-HID provider (prefer Karabiner DriverKit VirtualHID if available/acceptable) to answer only: `virtual HID Left Option -> does Receiver A open 5/5?`.
2. If that passes, freeze the receiver requirement as `real HID keyboard report required` and decide production backend:
   - native CoreHID after entitlement/provisioning is available; or
   - an explicitly managed DriverKit/provider architecture if native entitlement is not practical.

Do not rework the A/B classifier or BLE transaction path until this trigger-backend feasibility question is answered.

## Next transition

New task: `RO-REAL-HID-TRIGGER-BACKEND-020`.

Product source mutation remains forbidden until the user approves the trigger-backend architecture path. No additional receiver hardware test is authorized on the synthetic candidate.
