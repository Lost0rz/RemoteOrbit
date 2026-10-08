# CURRENT_STATUS

Last updated: 2026-10-08
State: SYSTEM-MAPPED DUAL-RECEIVER IMPLEMENTATION PLAN READY FOR USER REVIEW
Repository: `Lost0rz/RemoteOrbit`

This file is the authority for mutable current project state. Historical detail remains preserved in Git history.

## Control-plane authority

- Synthetic dual-receiver candidate remains unmerged.
- Preserved implementation branch: `codex/dual-receiver-momentary-routing-v1`.
- Preserved branch/control HEAD: `c90edbf73ad9b0642fa344734571c0e806c0eb73`.
- Preserved product HEAD: `ef29186e25c64cd4d1d7209cb2a41f95c51d4a11`.
- New corrected design: `docs/superpowers/specs/2026-10-08-dual-receiver-system-mapped-trigger-design-final.md`.
- New implementation plan: `docs/superpowers/plans/2026-10-08-dual-receiver-system-mapped-routing.md`.
- Product mutation remains forbidden until the user reviews/approves the plan.
- Merge remains forbidden.

## Accepted failure evidence

019 early hardware gate:

```text
5 x direct LONG
gesture classified A: 5/5
remote audio lifecycle: 5/5
synthetic Left Option DOWN/UP: 5/5
Receiver A externally opened: 0/5
```

Classification:

`SYNTHETIC_RECEIVER_TRIGGER_NOT_ACCEPTED`

This rejects CGEvent synthetic modifier as the normal dual-receiver trigger backend only. Gesture recognition, BLE activation, first-PCM timing, transaction identity and release/drain remain reusable.

## Historical trigger architecture — accepted fact

Merged PR #13 established the working normal path as:

```text
remote microphone F5
-> device-scoped hidutil mapping
-> configured VoiceTriggerKey
-> system-mapped modifier event
-> VoiceKeyFilter / HardwareOptionGate capture/defer
-> first PCM releases mapped DOWN
-> physical release + drain releases mapped UP
```

Left Option is the default target, not a hard-coded mapping mechanism. Current `VoiceTriggerKey` / `RemoteVoiceKeyMapping` already support Left/Right Option, Control and Command.

The prior virtual-HID/Karabiner direction is superseded and is not part of the current plan.

## Re-audit findings

### Existing capabilities that make the corrected design feasible

1. `RemoteVoiceKeyMapping.mappingJSON(for:)` already parameterizes F5 -> any supported `VoiceTriggerKey`.
2. `RemoteVoiceKeyMapping.setEnabled(_:target:)` synchronously waits for `/usr/bin/hidutil --set` to exit and exposes an injected mapping seam in `AppController` tests.
3. `VoiceKeyFilter.beginVoiceTriggerReconfiguration(from:to:)` already suppresses raw F5 plus old/new mapped key codes during a runtime target transition.
4. `VoiceKeyFilter.configureVoiceTriggerKey(_:)` rejects target changes while mapped/synthetic ownership is active.
5. Existing hardware long-hold path already releases a captured mapped DOWN at first PCM through `onHardwareOptionGateLongReady`.
6. Existing hardware release/drain path already owns the mapped UP until safe release.
7. The accepted 019 branch already contains the 350/300 pure classifier, Receiver-B preference/UI, transport prewarm, no-double-wait classified hold entry and broad test harnesses.

### Corrected architecture

Idle dual mode keeps the device mapping on Receiver A:

```text
F5 -> A (initially Left Option)
```

Direct LONG:

```text
physical F5
-> mapped A edge captured
-> 350 ms A classification
-> remote audio
-> first PCM
-> replay captured A DOWN
-> release/drain
-> replay captured A UP
```

First quick tap:

```text
discard captured A pair
-> begin guarded A -> B mapping transition
-> hidutil --set F5 -> B
-> configure filter target B
-> B_MAPPING_READY
```

Second LONG is admitted only if `B_MAPPING_READY` existed before second physical DOWN:

```text
second physical F5
-> mapped B edge captured
-> 350 ms B classification
-> first PCM
-> replay captured B DOWN
-> release/drain
-> replay captured B UP
-> restore B -> A after B mapped-UP ownership closes
```

No second press or second quick release restores A without opening either receiver.

## B mapping readiness rule

Natural measured first-UP -> second-DOWN gaps were approximately `74.476–239.547 ms`.

Do not add a second synchronous `hidutil --get` to the critical double-tap interval.

`B_MAPPING_READY` means:

```text
hidutil --set B returned exit 0
AND filter runtime target == B
AND reconfiguration suppression ended safely
```

Existing asynchronous HID readback remains diagnostic evidence. A later readback mismatch locks dual mode and converges to A before another gesture. Mapping apply latency is measured and logged for every A->B/B->A transition.

If the second physical DOWN arrives before B-ready, that B attempt fails closed. It is never buffered/replayed after mapping becomes ready, and it never falls back to synthetic B.

## Safety invariants

- one raw HID owner: `HIDMonitor`;
- one mapped-edge owner: `VoiceKeyFilter` / `HardwareOptionGate`;
- one mapping authority: `RemoteVoiceKeyMapping`;
- no normal A/B CGEvent synthetic trigger;
- no virtual-HID provider/system extension;
- no Persistent Session receiver authority;
- no generic button gesture timing change;
- no BLE codec/tail/drain redesign;
- mapping transition failure = fail closed;
- B->A restore failure blocks new gestures until reconciliation.

## Construction baseline

The next implementation should preserve the already-tested 019 product work rather than rebuild it from `main`.

Authorized code base after plan approval:

```text
codex/dual-receiver-momentary-routing-v1
c90edbf73ad9b0642fa344734571c0e806c0eb73
```

Create a new isolated v2 branch/worktree from that preserved code base, then sync only current authoritative control/spec/plan files from `origin/main` before product mutation.

Planned branch/worktree:

```text
codex/dual-receiver-system-mapped-routing-v2
/private/tmp/remoteorbit-dual-receiver-system-mapped-routing-v2
```

The pre-existing canonical `HIDMonitor.swift` local modification remains protected and must not be cleaned/stashed/reset/copied into this work.

## Hardware acceptance after implementation

1. Set A: 5 direct LONGs -> A 5/5, B 0/5, system-mapped hardware path, zero normal synthetic edges.
2. Set B: 5 natural tap-then-LONGs -> first tap opens neither; accepted second presses open B only; record A->B mapping latency/readiness.
3. Set C: 5 isolated quick taps -> neither opens; mapping returns to A.
4. Web independently audits these results before any broader alternating soak or merge.

## Next transition

Current task: `RO-DUAL-RECEIVER-SYSTEM-MAPPED-ROUTING-021`.

Implementation plan is complete and awaits user review. No product code mutation, rebuild/reinstall, hardware gesture or merge is authorized yet.