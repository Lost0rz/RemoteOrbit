# Dual-Receiver Mapping Latency Gate

Date: 2026-10-08
Task: `RO-DUAL-RECEIVER-MAPPING-LATENCY-GATE-022`
State: evidence-only prerequisite before v2 implementation

## Goal

Measure the real process-level latency of the existing device-scoped `hidutil` mapping when switching the Xiaomi remote microphone F5 source between Receiver A (Left Option) and Receiver B (Right Option).

This gate answers only whether the corrected dynamic system-mapped design has enough timing headroom to fit inside the already-observed first-UP -> second-DOWN interval.

## Why this gate exists

Closed hardware gesture evidence measured natural inter-press gaps of approximately `74.476–239.547 ms`.

The corrected design is otherwise based entirely on previously working mechanisms:

- parameterized `RemoteVoiceKeyMapping`;
- system-mapped modifier events;
- `VoiceKeyFilter` / `HardwareOptionGate` ownership;
- first-PCM replay;
- release/drain balancing.

The unresolved question is only the actual `hidutil --set` duration on the target machine.

## Measurement boundary

The measured duration must include:

```text
process launch
-> /usr/bin/hidutil property --matching ... --set ...
-> process exit
```

Use a monotonic clock. This mirrors the synchronous process boundary used by `RemoteVoiceKeyMapping.setEnabled(_:target:)`.

Do not add a synchronous readback to the measured critical path. Readback is only for pre/post restoration verification.

## Frozen mappings

```text
matching = {"VendorID":0x2717,"ProductID":0x32B8}
source = 0x70000003E
A destination = 0x7000000E2
B destination = 0x7000000E6
```

## Procedure

1. Record the exact pre-test mapping.
2. Create a temporary evidence directory under `/private/tmp`.
3. Perform 5 warm-up A->B/B->A pairs; all must exit 0.
4. Perform 50 measured A->B and 50 measured B->A transitions, alternating sequentially.
5. Record every duration and exit status.
6. Compute min/median/p90/p95/p99/max for each direction.
7. Compute A->B max and p95 margins against the observed 74.476 ms minimum user gap.
8. Restore the exact pre-test mapping in cleanup/finally.
9. Verify semantic restoration with a fresh readback.
10. Return evidence to Web. Do not self-authorize implementation.

## No product mutation

This gate must not modify repository source/tests, rebuild or reinstall RemoteOrbit, restart the app, alter receiver shortcuts, press the remote, change TCC, touch the audio driver/CoreAudio, install virtual-HID providers, or merge anything.

## Web decision after evidence

Web will classify the result as one of:

```text
MAPPING_LATENCY_GATE_PASS
MAPPING_LATENCY_GATE_MARGINAL
MAPPING_LATENCY_GATE_FAIL
```

Only PASS authorizes creation/execution of the v2 product implementation branch.
