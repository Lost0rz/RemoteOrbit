# Dual-Receiver System-Mapped Routing — Latency Gate Addendum

Date: 2026-10-08
Task transition: `RO-DUAL-RECEIVER-MAPPING-LATENCY-GATE-022` -> `RO-DUAL-RECEIVER-SYSTEM-MAPPED-IMPLEMENTATION-023`

This addendum is authoritative where it narrows or corrects the earlier implementation plan.

## Spec reference correction

The implementation plan header references the earlier draft design path. Executors must instead treat this file as the authoritative spec:

`docs/superpowers/specs/2026-10-08-dual-receiver-system-mapped-trigger-design-final.md`

The draft design path is historical only.

## Gate 022 result

Real process-level `/usr/bin/hidutil --set` measurements on the same Xiaomi device match and A/B destinations:

```text
A->B 50/50 success
min     4.721000 ms
median  5.428063 ms
p90     6.076817 ms
p95     6.137273 ms
p99     6.488425 ms
max     6.698084 ms

B->A 50/50 success
min     4.774709 ms
median  5.326646 ms
p90     6.190333 ms
p95     6.389208 ms
p99     6.621409 ms
max     6.703750 ms
```

Prior natural first-UP -> second-DOWN minimum: `74.476 ms`.

Worst measured A->B process margin: `67.777916 ms`.

Decision: `MAPPING_LATENCY_GATE_PASS`.

Pre-test `UserKeyMapping` was empty; post-test mapping was restored to empty with semantic match. No source/test/runtime/shortcut/hardware-gesture mutation occurred.

## Production readiness rule

The latency gate measured only the process boundary. Production `SECONDARY_READY` still requires all three:

```text
hidutil --set B returned exit 0
AND filter target == B
AND reconfiguration suppression ended safely
```

Implementation must log:

```text
A_TO_B_APPLY_MS
B_TO_A_APPLY_MS
FIRST_UP_TO_SECONDARY_READY_MS
```

A second physical DOWN is admitted only if `SECONDARY_READY` already existed before that DOWN. If not, fail closed and do not buffer/replay the press.

Do not add synchronous `hidutil --get` to the critical double-tap path. Existing asynchronous readback remains diagnostic evidence.

## Baseline / branch clarification

Use preserved 019 code base `c90edbf73ad9b0642fa344734571c0e806c0eb73` for v2 product construction; sync only current control/spec/plan/addendum documents from authoritative main before product mutation.

The reported local branch `codex/v0211-nonseize-hid-audit` is not authority for this task and must remain untouched unless separately attributed.

The pre-existing canonical dirty `remote-orbit/Sources/RemoteOrbit/KeyMapping/HIDMonitor.swift` remains protected and must not be cleaned, stashed, reset, restored or copied into v2.

## Hardware boundary

After implementation-plan Tasks 2-12, full automated validation and exact candidate install, STOP before user gestures at:

`READY_FOR_USER_SYSTEM_MAPPED_SET_A`

Do not automatically continue to Set B/C or merge.
