# RemoteOrbit Current Task

## Current task — SYSTEM-MAPPED DUAL-RECEIVER USER SET B ACCEPTANCE

- **Status:** SET A PASS / USER SET B AUTHORIZED
- **Task ID:** `RO-DUAL-RECEIVER-SYSTEM-MAPPED-IMPLEMENTATION-023`
- **Control parent:** `bf5579fc43f2efbe627dec03f4d0b52182a2848f`
- **v2 branch:** `codex/dual-receiver-system-mapped-routing-v2`
- **v2 HEAD:** `e1e6fe0bf76e245c4237978600b117b5b8e2a83e`
- **Installed source:** `50a20174632dc105fb670a9b83e3f6feaa8e9f9b`
- **Merge:** FORBIDDEN

## Accepted Set A
Five Direct-LONG samples passed user and runtime acceptance:

```text
A hardware path = 5/5
B trigger = 0/5
normal synthetic trigger edges = 0
first PCM before A replay = 5/5
release/drain complete = 5/5
final target = left_option
final phase = primaryReady
final transaction = none
```

## Set B procedure
The user performs exactly five natural attempts:

```text
quick first tap
immediately second press and hold
speak briefly
release normally
```

For each attempt observe:

```text
first tap opens A? expected NO
first tap opens B? expected NO
second long opens B? expected YES
A opens during second long? expected NO
release closes B normally? expected YES
duplicate/stuck state? expected NO
```

Do not slow the gesture artificially to wait for mapping readiness. Use a natural quick tap then second long.

If an attempt does not open B, record the exact attempt number and symptom. Do not replace it with a retry for acceptance counting.

## Read-only evidence after user attempts
After the five attempts, the local executor may inspect diagnostics only. It must return per-attempt:

```text
gesture_id
first_up_to_secondary_ready_ms
A_to_B_apply_ms
second_down_ready_before_edge
second_down_gap_ms
mapped_trigger_key
hardware_gate_begin
classification
first_pcm_before_replay
normal_synthetic_trigger_edge_count
release_drain_completed
B_to_A_apply_ms
final_mapping_target
final_mapping_phase
final_transaction
```

Also classify any failed attempt explicitly as one of the observed mechanisms, including `B_MAPPING_NOT_READY_FAIL_CLOSED` if the second DOWN beat readiness.

## Prohibitions
No product/test edits, settings changes, build/install/restart, receiver shortcut changes, executor-generated remote gestures, Set C, or merge.

## Stop
After five Set-B attempts and read-only evidence collection, return to Web and stop. Do not proceed to Set C automatically.
