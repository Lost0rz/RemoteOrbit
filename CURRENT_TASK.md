# RemoteOrbit Current Task

## Current task — SYSTEM-MAPPED DUAL-RECEIVER MAPPING LATENCY GATE

- **Status:** ACTIVE / EVIDENCE COLLECTION ONLY
- **Task ID:** `RO-DUAL-RECEIVER-MAPPING-LATENCY-GATE-022`
- **Previous task:** `RO-DUAL-RECEIVER-SYSTEM-MAPPED-ROUTING-021` — PLAN APPROVED SUBJECT TO LATENCY GATE
- **Final design:** `docs/superpowers/specs/2026-10-08-dual-receiver-system-mapped-trigger-design-final.md`
- **Implementation plan:** `docs/superpowers/plans/2026-10-08-dual-receiver-system-mapped-routing.md`
- **Gate procedure:** `docs/superpowers/plans/2026-10-08-dual-receiver-mapping-latency-gate.md`
- **Preserved implementation branch:** `codex/dual-receiver-momentary-routing-v1`
- **Preserved branch HEAD:** `c90edbf73ad9b0642fa344734571c0e806c0eb73`
- **Preserved product HEAD:** `ef29186e25c64cd4d1d7209cb2a41f95c51d4a11`
- **Product/test source mutation:** FORBIDDEN
- **Build/install/restart:** FORBIDDEN
- **Receiver shortcut changes:** FORBIDDEN
- **Remote hardware gestures:** FORBIDDEN
- **Provider/system-extension install:** FORBIDDEN / NOT NEEDED
- **Merge:** FORBIDDEN

## Purpose

Before v2 product construction, measure the only unresolved timing prerequisite of the corrected design:

`How long does the existing device-scoped hidutil mapping take to switch A <-> B on this machine?`

Observed natural first-UP -> second-DOWN gaps from the closed gesture study were approximately:

```text
74.476 ms .. 239.547 ms
```

The local executor collects evidence only. Web decides PASS/MARGINAL/FAIL after reviewing the distribution.

## Frozen mapping targets

Use the same supported Xiaomi remote device match and destinations already present in `RemoteVoiceKeyMapping`:

```text
matching:
{"VendorID":0x2717,"ProductID":0x32B8}

source:
0x70000003E

A / Left Option destination:
0x7000000E2

B / Right Option destination:
0x7000000E6
```

Do not substitute another device, target or remapper.

## Gate 0 — freshness and current-state capture

1. `git fetch origin --prune`.
2. Read `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md`.
3. Verify authoritative `origin/main` matches the task authority or is a control/docs-only compatible successor with the same Task ID and gate contract.
4. Do not create a product implementation worktree for this gate.
5. Record the currently running RemoteOrbit identity read-only if present.
6. Record the exact pre-test device-scoped `UserKeyMapping` readback for the Xiaomi remote.
7. Save that raw readback to the evidence directory before changing anything.

If mapping state cannot be read safely, STOP.

## Gate 1 — bounded temporary measurement environment

Create only a temporary evidence directory under `/private/tmp`, for example:

```text
/private/tmp/remoteorbit-mapping-latency-gate-022-<timestamp>/
```

A temporary script in that evidence directory is allowed. Do not add it to the repository.

The script must use a monotonic clock and invoke the same external process boundary as production:

```text
/usr/bin/hidutil
property
--matching {"VendorID":0x2717,"ProductID":0x32B8}
--set <mapping JSON>
```

Measure from immediately before process launch through process exit.

Do not use a mocked mapping API for the latency result.

## Gate 2 — warm-up

With no remote hardware operation:

1. apply A;
2. apply B;
3. repeat for 5 A->B / B->A warm-up pairs;
4. require exit status 0 for every warm-up operation.

Warm-up samples are recorded separately and excluded from the primary statistics.

Any nonzero exit status -> STOP, restore pre-test mapping and report.

## Gate 3 — measured samples

Collect exactly:

```text
A->B: 50 measured transitions
B->A: 50 measured transitions
```

Alternate sequentially so each A->B begins from A and each B->A begins from B.

For every operation record:

```text
index
direction
start_monotonic_ns
end_monotonic_ns
duration_ms
exit_status
```

Do not sleep between A->B and its paired B->A unless required for process cleanup. A small fixed pause between pairs is acceptable only if recorded.

Do not press the remote during measurement.

## Gate 4 — statistics

For A->B and B->A separately compute:

```text
sample_count
success_count
failure_count
min_ms
median_ms
p90_ms
p95_ms
p99_ms
max_ms
```

Preserve the raw ordered sample arrays as evidence.

Also report:

```text
A_TO_B_MARGIN_VS_OBSERVED_MIN_MS = 74.476 - A_TO_B_MAX_MS
A_TO_B_P95_MARGIN_VS_OBSERVED_MIN_MS = 74.476 - A_TO_B_P95_MS
```

These margins are descriptive evidence only. The executor must not use them to self-authorize implementation.

## Gate 5 — exact restoration

In a `finally`/cleanup path, restore the exact pre-test mapping state captured in Gate 0.

After restoration:

1. run a fresh `hidutil --get UserKeyMapping` for the same matching device;
2. compare the normalized observed mapping with the pre-test mapping;
3. require exact semantic restoration.

If restoration fails:

```text
FINAL_STATE: STOP_MAPPING_RESTORATION_FAILED
```

Do not continue or attempt product fixes.

## Strict prohibitions

```text
NO repository source/test edits
NO branch/worktree creation for product construction
NO build
NO app reinstall
NO app restart
NO receiver shortcut changes
NO remote button presses
NO BLE/audio test
NO TCC changes
NO audio driver/CoreAudio changes
NO Karabiner/CoreHID/provider work
NO merge
```

## Required handoff

Return:

```text
TASK_ID: RO-DUAL-RECEIVER-MAPPING-LATENCY-GATE-022
CONTROL_HEAD:
REMOTEORBIT_RUNNING_PID:
PRE_TEST_MAPPING_RAW:
PRE_TEST_MAPPING_NORMALIZED:

WARMUP_A_TO_B_COUNT:
WARMUP_B_TO_A_COUNT:
WARMUP_FAILURES:

MEASURED_A_TO_B_COUNT:
A_TO_B_SUCCESS_COUNT:
A_TO_B_FAILURE_COUNT:
A_TO_B_MIN_MS:
A_TO_B_MEDIAN_MS:
A_TO_B_P90_MS:
A_TO_B_P95_MS:
A_TO_B_P99_MS:
A_TO_B_MAX_MS:
A_TO_B_RAW_MS: [...]

MEASURED_B_TO_A_COUNT:
B_TO_A_SUCCESS_COUNT:
B_TO_A_FAILURE_COUNT:
B_TO_A_MIN_MS:
B_TO_A_MEDIAN_MS:
B_TO_A_P90_MS:
B_TO_A_P95_MS:
B_TO_A_P99_MS:
B_TO_A_MAX_MS:
B_TO_A_RAW_MS: [...]

A_TO_B_MARGIN_VS_OBSERVED_MIN_MS:
A_TO_B_P95_MARGIN_VS_OBSERVED_MIN_MS:

POST_TEST_MAPPING_RAW:
POST_TEST_MAPPING_NORMALIZED:
RESTORATION_MATCH: YES/NO

PRODUCT_SOURCE_CHANGED: NO
TEST_SOURCE_CHANGED: NO
APP_RESTARTED: NO
REMOTE_GESTURES_PERFORMED: NO
MERGED: NO

EVIDENCE_DIR:
FINAL_STATE: MAPPING_LATENCY_EVIDENCE_READY_FOR_WEB_AUDIT
```

Do not begin v2 implementation after collecting the numbers.
