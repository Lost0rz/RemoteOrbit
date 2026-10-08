# Dual-Receiver System-Mapped Trigger Design — Final

Date: 2026-10-08
Task: `RO-DUAL-RECEIVER-SYSTEM-MAPPED-ROUTING-021`
State: final design; implementation plan prepared; product mutation not yet authorized

## Problem statement

RemoteOrbit already had a working normal voice-trigger path before the rejected 019 candidate:

```text
Xiaomi remote microphone F5
-> device-scoped hidutil mapping
-> configured modifier key
-> macOS system-mapped modifier event
-> VoiceKeyFilter / HardwareOptionGate capture/defer
-> first PCM authorizes release of mapped DOWN
-> physical release + output drain
-> matching mapped UP
```

Merged PR #13 parameterized the mapping target across Left/Right Option, Control and Command and retained synthetic trigger only as fallback.

The 019 dual-receiver implementation made one architectural mistake: it cleared the device mapping in dual mode and promoted CGEvent synthetic Left/Right Option into the normal post-classification trigger backend. Receiver A rejected that path 5/5 even though gesture classification, BLE activation, first-PCM handling and release/drain all completed.

Therefore the dual-receiver problem is not how to create a new keyboard backend. It is how to preserve the already working system-mapped hardware path while selecting which mapping owns the next physical press.

## Product contract

```text
Direct LONG                   -> Receiver A
Quick first tap + second LONG -> Receiver B
Quick single tap              -> no action

A initial key = Left Option
B initial key = Right Option
LONG_THRESHOLD_MS = 350
DOUBLE_WINDOW_MS   = 300
```

Both A and B are independent momentary transactions. Persistent Session state is not receiver authority.

## Existing capabilities confirmed by source audit

1. `RemoteVoiceKeyMapping.mappingJSON(for:)` already maps remote F5 to any `VoiceTriggerKey`; Left Option is only the default, not a hard-coded mechanism.
2. `RemoteVoiceKeyMapping.setEnabled(_:target:)` executes `/usr/bin/hidutil property --matching ... --set ...` synchronously and returns only after the process exits.
3. `VoiceKeyFilter.beginVoiceTriggerReconfiguration(from:to:)` already suppresses raw F5 plus old and new mapped modifier key codes while a runtime trigger-key transition is in progress.
4. `VoiceKeyFilter.configureVoiceTriggerKey(_:)` refuses to switch while mapped/synthetic ownership is active.
5. Existing hardware long-hold flow already releases the captured mapped DOWN at the first-PCM boundary through `onHardwareOptionGateLongReady`.
6. Existing release/drain ownership already holds mapped UP until physical release/output drain is safe.
7. 019 already provides the accepted 350/300 pure gesture recognizer, transport prewarm, Receiver-B preference/UI, no-double-wait classified hold path and extensive test harnesses.

## Selected runtime design

### 1. Primary-ready / idle

Idle dual mode keeps the real device mapping pointed at A:

```text
remote F5 -> A
filter runtime key = A
mapping phase = PRIMARY_READY
```

For the initial contract A is Left Option.

### 2. Direct LONG -> A

```text
physical F5 DOWN
-> system generates mapped A edge
-> HardwareOptionGate captures/defer
-> 350 ms classifier resolves A
-> activate remote audio
-> first decoded PCM
-> replay captured mapped A DOWN
-> stream
-> physical F5 UP + output drain
-> replay captured mapped A UP
-> remain PRIMARY_READY
```

No normal A transaction calls the keyed synthetic trigger backend.

### 3. First quick tap -> arm B

When the first press releases before 350 ms:

```text
capture/discard first mapped A pair
-> Receiver A sees no edge
-> begin existing trigger-key reconfiguration guard A -> B
-> guard suppresses F5 + A keyCode + B keyCode
-> run hidutil --set F5 -> B on existing serial mapping queue
-> if set exits 0, configure filter runtime key to B
-> end reconfiguration guard
-> mapping phase = SECONDARY_READY
```

The first-UP -> second-DOWN classifier window remains 300 ms.

### 4. What `B_MAPPING_READY` means

Because natural measured first-UP -> second-DOWN gaps were approximately 74.476–239.547 ms, do not make the user wait for a second synchronous `hidutil --get` process before admitting the second press.

`B_MAPPING_READY` is defined as:

```text
hidutil --set B returned exit status 0
AND filter runtime trigger key == B
AND reconfiguration suppression ended safely
```

Existing asynchronous HID readback remains diagnostic evidence. Every A->B/B->A transition records monotonic apply latency.

If asynchronous readback later disproves the active requested mapping, dual mode locks/fails closed and converges to A before admitting another gesture. Stale readback from an older transition generation cannot override newer state.

### 5. Second press admission

If second physical F5 DOWN arrives while `SECONDARY_READY`:

```text
physical second F5 DOWN
-> system generates mapped B edge
-> HardwareOptionGate captures/defer
-> recognizer enters second-press pending
```

If second physical DOWN arrives while B is still arming/restoring/unavailable:

```text
FAIL CLOSED
A external edge = 0
B external edge = 0
synthetic edge = 0
BLE activation for that second press = 0
```

Do not buffer/replay that already-held second press after mapping later becomes ready. Wait for its physical UP, then converge to A.

### 6. Second LONG -> B

```text
SECONDARY_READY
-> second physical F5 DOWN mapped to B
-> HardwareOptionGate capture/defer B
-> second hold >= 350 ms
-> classify B
-> activate remote audio
-> first decoded PCM
-> replay captured mapped B DOWN
-> stream
-> physical release + output drain
-> replay captured mapped B UP
-> only after B mapped-UP ownership safely closes, restore B -> A
-> PRIMARY_READY
```

No normal B transaction calls `VoiceOptionTrigger.sendDown(...key:)`.

### 7. Second quick release / no second press

Second quick release:

```text
discard captured B pair
-> open neither receiver
-> restore mapping/filter B -> A
-> PRIMARY_READY
```

No second press before the 300 ms window expires:

```text
cancel transport prewarm
-> restore B -> A
-> PRIMARY_READY
```

### 8. Restore failure

If B->A mapping or filter restore fails:

```text
mapping phase = UNAVAILABLE / runtime locked
no new prewarm
no A transaction
no B transaction
no synthetic fallback
```

The next gesture is forbidden until runtime authority is reconciled.

## Authority rules

- `HIDMonitor` remains the sole raw HID owner.
- `VoiceKeyFilter` / `HardwareOptionGate` remains the sole mapped-edge owner.
- `RemoteVoiceKeyMapping` remains the sole device-scoped mapping authority.
- The new dual mapping state is orchestration state only; it never invokes a second mapping mechanism.
- Existing serial mapping queue owns A->B/B->A process execution.
- `VoiceOptionTrigger` may remain for legacy/fallback paths but is not the normal dual A/B trigger backend.
- No CoreHID/Karabiner/virtual-HID provider is introduced.

## Preserved 019 work

Reuse selectively from `codex/dual-receiver-momentary-routing-v1`:

- Disabled-SHORT corrective;
- `DualReceiverVoiceGestureRecognizer` and 350/300 timing;
- Receiver-B preference and Settings UI;
- already-classified hold path/no second 300 ms classifier;
- transport prewarm;
- first-PCM authorization boundary;
- release/drain/loss/disconnect cleanup;
- runtime configuration busy gates and fail-closed testing harness.

Replace:

```text
dual active -> clear device mapping
classified A/B -> synthetic selected-key DOWN/UP
```

with:

```text
dual idle -> device mapping A
after first quick UP -> temporary mapping B
A/B classified holds -> existing hardware-mapped gate replay
B lifecycle complete -> restore mapping A
```

## Mapping latency evidence

The implementation must log at minimum:

```text
A_TO_B_APPLY_BEGIN
A_TO_B_APPLY_END
A_TO_B_APPLY_MS
B_TO_A_APPLY_BEGIN
B_TO_A_APPLY_END
B_TO_A_APPLY_MS
SECOND_DOWN_RELATIVE_TO_B_READY_MS
```

If natural B attempts frequently arrive before `B_MAPPING_READY`, stop after hardware evidence and return to Web for timing/UX adjustment. Do not weaken fail-closed behavior and do not fall back to synthetic B.

## Acceptance

### Automated

- direct A uses system-mapped hardware replay and zero normal synthetic edges;
- first short opens neither receiver;
- A->B success/failure/stale completion covered;
- second DOWN before B-ready fails closed;
- B long uses system-mapped hardware replay and zero normal synthetic edges;
- no-second and B-quick-release restore A;
- B long restores A only after B mapped-UP ownership closes;
- restore failure locks runtime;
- disconnect/loss/settings-change regressions pass.

### Hardware sequence

1. 5 x direct LONG -> A 5/5, B 0/5.
2. 5 x natural tap-then-LONG -> first tap opens neither; accepted B attempts open B only; record mapping latency/readiness.
3. 5 x isolated quick tap -> neither receiver opens; mapping returns to A.
4. Only after Web audits these sets may broader alternating A/B acceptance proceed.

## Out of scope

- virtual HID/CoreHID/Karabiner;
- BLE codec or audio-driver changes;
- tail/drain retuning;
- Persistent Session redesign;
- generic button gesture timing;
- diagnostic-authority expansion;
- merge before independent audit.
