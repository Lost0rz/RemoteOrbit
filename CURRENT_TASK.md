# RemoteOrbit Current Task

## Current task — SYSTEM-MAPPED DUAL-RECEIVER IMPLEMENTATION PLAN REVIEW

- **Status:** PLAN READY / USER REVIEW REQUIRED BEFORE PRODUCT MUTATION
- **Task ID:** `RO-DUAL-RECEIVER-SYSTEM-MAPPED-ROUTING-021`
- **Previous task:** `RO-DUAL-RECEIVER-SYSTEM-MAPPED-TRIGGER-020` — DESIGN DIRECTION ACCEPTED / PLAN WRITTEN
- **Rejected prior backend:** normal dual CGEvent synthetic trigger — `SYNTHETIC_RECEIVER_TRIGGER_NOT_ACCEPTED`
- **Superseded direction:** CoreHID/Karabiner/virtual-HID provider review — SUPERSEDED / NOT NEEDED
- **Final design:** `docs/superpowers/specs/2026-10-08-dual-receiver-system-mapped-trigger-design-final.md`
- **Implementation plan:** `docs/superpowers/plans/2026-10-08-dual-receiver-system-mapped-routing.md`
- **Preserved implementation branch:** `codex/dual-receiver-momentary-routing-v1`
- **Preserved branch HEAD:** `c90edbf73ad9b0642fa344734571c0e806c0eb73`
- **Preserved product HEAD:** `ef29186e25c64cd4d1d7209cb2a41f95c51d4a11`
- **Planned v2 branch:** `codex/dual-receiver-system-mapped-routing-v2`
- **Planned v2 worktree:** `/private/tmp/remoteorbit-dual-receiver-system-mapped-routing-v2`
- **Product/test source mutation:** FORBIDDEN until user approves this plan
- **Runtime install/restart:** FORBIDDEN until implementation reaches the plan's hardware gate
- **Receiver shortcut changes:** FORBIDDEN
- **Provider/system-extension install:** FORBIDDEN / NOT PART OF DESIGN
- **Merge:** FORBIDDEN

## Accepted product contract

```text
Direct LONG                   -> Receiver A
Quick first tap + second LONG -> Receiver B
Quick single tap              -> no action

A initial key = Left Option
B initial key = Right Option
LONG = 350 ms
DOUBLE WINDOW = 300 ms
```

Both A and B are independent momentary transactions. Persistent Session is not receiver authority.

## Independent source audit result

### Existing mapping capability

`RemoteVoiceKeyMapping` already maps the remote microphone F5 usage to any supported `VoiceTriggerKey` through `mappingJSON(for:)`.

Supported destinations already include:

```text
Left Option
Right Option
Left Control
Right Control
Left Command
Right Command
```

Left Option is the default target, not a hard-coded mechanism.

### Existing safe reconfiguration seam

`VoiceKeyFilter.beginVoiceTriggerReconfiguration(from:to:)` already suppresses:

```text
raw remote F5
old trigger key code
new trigger key code
```

while a runtime key transition is in progress.

`configureVoiceTriggerKey(_:)` rejects target changes while hardware or synthetic ownership is active.

### Existing first-PCM hardware path

The original hardware-mapped long-hold path already uses:

```text
captured mapped DOWN
-> wait for real remote audio / first PCM
-> onHardwareOptionGateLongReady
-> release mapped DOWN
```

and preserves mapped UP through physical release/output drain.

Therefore the corrected dual implementation should reuse this exact path for both A and B rather than create another trigger backend.

## Frozen corrected architecture

### Idle / A-ready

```text
F5 mapping = A
filter target = A
mapping phase = PRIMARY_READY
```

### Direct LONG A

```text
physical F5 DOWN
-> mapped A edge captured/deferred
-> direct hold >= 350ms
-> classify A
-> activate remote audio
-> first PCM
-> release captured mapped A DOWN
-> physical release + drain
-> release captured mapped A UP
```

### First quick release arms B

```text
first mapped A edge(s) discarded
-> Receiver A sees nothing
-> begin guarded A -> B trigger reconfiguration
-> hidutil --set F5 -> B on existing mapping queue
-> configure filter target B
-> end suppression guard
-> SECONDARY_READY
```

### B readiness definition

Do not block the 74–240ms natural inter-press gap on a second synchronous readback process.

`B_MAPPING_READY` requires:

```text
hidutil --set B exit = 0
filter target = B
reconfiguration suppression safely ended
```

Existing asynchronous HID readback remains diagnostic. A mismatch later locks dual mode and converges to A before the next gesture.

Every A->B/B->A transition records monotonic apply latency.

### Second physical press

Only `SECONDARY_READY` may admit the second DOWN.

If DOWN arrives while B is still arming/restoring/unavailable:

```text
FAIL CLOSED
A edge exposed = 0
B edge exposed = 0
synthetic edge = 0
BLE activation for that second press = 0
```

Do not buffer/replay an already-held second press after B later becomes ready.

### Second LONG B

```text
second physical F5 DOWN
-> mapped B edge captured/deferred
-> hold >= 350ms
-> classify B
-> activate remote audio
-> first PCM
-> release captured mapped B DOWN
-> physical release + drain
-> release captured mapped B UP
-> only then restore B -> A
```

### No-action paths

First quick tap with no second press:

```text
restore B -> A
cancel prewarm
open neither receiver
```

Second quick tap:

```text
discard B mapped pair
restore B -> A
open neither receiver
```

## Mandatory safety invariants

```text
RAW_HID_OWNER = HIDMonitor only
MAPPED_EDGE_OWNER = VoiceKeyFilter / HardwareOptionGate only
MAPPING_AUTHORITY = RemoteVoiceKeyMapping only
NORMAL_DUAL_SYNTHETIC_TRIGGER = NO
VIRTUAL_HID_PROVIDER = NO
PERSISTENT_SESSION_RECEIVER_AUTHORITY = NO
GENERIC_BUTTON_GESTURE_TIMING_CHANGE = NO
BLE_CODEC_CHANGE = NO
TAIL_DRAIN_RETUNE = NO
```

Mapping transition failure is fail-closed.

B->A restore failure locks the runtime and blocks every new voice gesture until reconciliation.

## Implementation baseline rule

Do not rebuild the accepted 019 feature from current docs-only `main`.

After plan approval:

1. fetch/prune;
2. verify current control HEAD and preserved branch `c90edbf...`;
3. create `codex/dual-receiver-system-mapped-routing-v2` from preserved 019 branch;
4. create isolated worktree `/private/tmp/remoteorbit-dual-receiver-system-mapped-routing-v2`;
5. sync only authoritative CURRENT_STATUS/CURRENT_TASK/final spec/implementation plan from `origin/main`;
6. prove the product baseline still equals preserved 019 product HEAD `ef29186e...` before corrective product edits;
7. preserve the existing canonical dirty `HIDMonitor.swift` read-only; do not clean/stash/reset/copy it.

## Planned implementation tasks

Follow the written plan exactly:

1. v2 baseline/control sync and accepted-suite baseline;
2. dual eligibility keeps A mapping active instead of clearing mapping;
3. gesture recognizer emits first-short / awaiting-second transition;
4. explicit dual mapped-trigger runtime phase state;
5. restore direct A to existing hardware-mapped first-PCM replay path;
6. first quick release -> guarded A->B mapping arm and latency logging;
7. second DOWN before B-ready fails closed and is never buffered;
8. ready second press -> mapped B hardware-gate path, no synthetic;
9. timeout/second-quick/B-complete -> safe B->A restore only after release ownership closes;
10. disconnect/loss/stale completion/readback safety;
11. Settings/legacy regression only; no new UI/provider controls;
12. full automated validation and exact candidate build;
13. sequential user hardware Sets A, B and C, then independent Web audit.

## Hardware acceptance boundary after implementation

### Set A

```text
5 x direct LONG
A opens = 5/5
B opens = 0/5
normal synthetic edges = 0
```

If A fails, STOP before B.

### Set B

```text
5 x natural first-tap + second-LONG
first tap opens neither
accepted second press opens B only
A opens = 0
normal synthetic edges = 0
A_TO_B_APPLY_MS recorded
```

Any second press that beats B readiness must be reported as `B_MAPPING_NOT_READY_FAIL_CLOSED`, not hidden or replayed. If this occurs materially under natural use, STOP for Web timing/UX review.

### Set C

```text
5 x isolated quick tap
A opens = 0
B opens = 0
mapping returns to A
```

After A/B/C, return `WAITING_FOR_INDEPENDENT_WEB_AUDIT`; do not merge.

## Current approval gate

The implementation plan is complete. Local AI must not start product construction until the user approves this plan.

If asked to execute before approval, return:

`HOLD_FOR_SYSTEM_MAPPED_ROUTING_PLAN_APPROVAL`