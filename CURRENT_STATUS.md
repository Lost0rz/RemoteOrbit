# CURRENT_STATUS

Last updated: 2026-10-08
State: SYSTEM-MAPPED DUAL-RECEIVER PLAN APPROVED / MAPPING LATENCY GATE ACTIVE
Repository: `Lost0rz/RemoteOrbit`

This file is the authority for mutable current project state. Historical detail remains preserved in Git history.

## Control-plane authority

- Previous authoritative main: `b9f7c03325441e5dc3efad894689cdcebca3d81a`.
- Corrected system-mapped design is approved in principle.
- Final design: `docs/superpowers/specs/2026-10-08-dual-receiver-system-mapped-trigger-design-final.md`.
- Implementation plan: `docs/superpowers/plans/2026-10-08-dual-receiver-system-mapped-routing.md`.
- Preserved implementation branch: `codex/dual-receiver-momentary-routing-v1` at `c90edbf73ad9b0642fa344734571c0e806c0eb73`.
- Preserved product HEAD: `ef29186e25c64cd4d1d7209cb2a41f95c51d4a11`.
- Planned v2 branch remains `codex/dual-receiver-system-mapped-routing-v2`.
- Product/test source mutation remains forbidden until the mapping-latency gate is Web-audited.
- Merge remains forbidden.

## Accepted architecture facts

The original working voice-trigger path is:

```text
remote microphone F5
-> device-scoped hidutil mapping
-> configured VoiceTriggerKey
-> system-mapped modifier event
-> VoiceKeyFilter / HardwareOptionGate capture/defer
-> first PCM releases mapped DOWN
-> physical release + drain releases mapped UP
```

Left Option is only the default target. `RemoteVoiceKeyMapping` already supports Left/Right Option, Left/Right Control and Left/Right Command.

The 019 CGEvent synthetic normal trigger backend is rejected by real Receiver-A hardware evidence: 5/5 direct LONG gestures classified and completed their audio lifecycle, but Receiver A opened 0/5.

The corrected dual-receiver design therefore reuses the proven system-mapped trigger path and changes only mapping ownership:

```text
idle: F5 -> A
first quick release: discard A pair, arm F5 -> B
second LONG while B ready: system-mapped B path
B completion / timeout / second quick release: restore F5 -> A
```

No Karabiner/CoreHID/virtual-HID provider is part of the design.

## Product contract

```text
Direct LONG                   -> Receiver A
Quick first tap + second LONG -> Receiver B
Quick single tap              -> no action

A initial key = Left Option
B initial key = Right Option
LONG = 350 ms
DOUBLE WINDOW = 300 ms
```

## Why a latency gate is required before construction

Closed gesture evidence measured natural first-UP -> second-DOWN gaps of approximately:

```text
74.476 ms .. 239.547 ms
```

The corrected architecture requires the existing device-scoped mapping to change from A to B between those two physical presses. The repository proves the mechanism exists, but does not yet prove its real process/apply latency on this machine.

Therefore the only remaining architecture prerequisite is a bounded measurement of the existing `/usr/bin/hidutil property --matching ... --set ...` operation using the same Xiaomi remote match and the existing A/B destinations.

This is not a receiver-compatibility test and does not require product changes.

## Mapping-latency gate contract

Current task: `RO-DUAL-RECEIVER-MAPPING-LATENCY-GATE-022`.

The local executor may, without pressing the remote:

1. record the exact pre-test device mapping;
2. perform warm-up A <-> B mapping changes;
3. measure repeated A->B and B->A `hidutil --set` process durations using a monotonic clock;
4. record termination status and distribution metrics;
5. restore the exact pre-test mapping and verify restoration.

No product/test source edits, build, install, restart, receiver shortcut change, TCC change, audio-driver/CoreAudio change or hardware gesture is authorized.

The executor does not decide whether latency is acceptable. It returns evidence to Web.

Required metrics for A->B and B->A separately:

```text
sample_count
success_count / failure_count
min
median
p90
p95
p99
max
raw sample list
```

The measurement must include full process launch + `hidutil --set` completion, matching the current `RemoteVoiceKeyMapping.setEnabled` synchronization boundary.

## Mapping readiness rule retained

If v2 construction is later authorized:

```text
B_MAPPING_READY =
hidutil --set B exit 0
+ filter target B
+ reconfiguration suppression safely ended
```

Do not add a second synchronous `hidutil --get` to the double-tap critical path. Existing asynchronous readback remains diagnostic evidence.

A second physical DOWN that arrives before B ready must fail closed and must never be buffered or replayed.

## Next transition

After the latency evidence returns, Web will compare the measured A->B distribution against the observed 74.476–239.547 ms user inter-press distribution and decide one of:

```text
MAPPING_LATENCY_GATE_PASS -> authorize v2 product construction
MAPPING_LATENCY_GATE_MARGINAL -> timing/UX review before construction
MAPPING_LATENCY_GATE_FAIL -> reject dynamic hidutil A/B design
```

No product construction starts before that decision.
