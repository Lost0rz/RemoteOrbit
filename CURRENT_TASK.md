# RemoteOrbit Current Task

## Current task — RECEIVER-B REPLAY-UP ACKNOWLEDGED RESTORE CORRECTIVE

- **Status:** USER RECEIVER-B STABILITY 5/5 PASS / FINAL READ-ONLY FIVE-RUN EVIDENCE REVIEW AUTHORIZED / MERGE FORBIDDEN
- **Task ID:** `RO-DUAL-RECEIVER-B-UP-REPLAY-ACK-CORRECTIVE-028`
- **Implementation base:** `458e28d91b5ff748613bb88f5b89212d660279c7`
- **Product implementation / installed source:** `f938b919e288a481f5eacaf9aad9c254dcf0cffe`
- **Final corrective branch HEAD:** `85bb2e12cad41198e5a27d9e610cbdb30b01d357`
- **Authorized branch:** `codex/dual-receiver-b-up-replay-ack-fix`
- **Authorized worktree:** `/private/tmp/remoteorbit-dual-receiver-b-up-replay-ack-fix`
- **Merge:** FORBIDDEN pending final five-run evidence review

## Accepted correction
The stuck Receiver-B failure was caused by the replayed copied Right Option UP being swallowed by B->A reconfiguration suppression before downstream delivery.

Task 028 keeps replay-UP ownership pending until the exact copied event re-enters `VoiceKeyFilter` and reaches the pass path. B->A restore can start only after all expected replay-UP components are acknowledged.

No fixed timing workaround, flag rewrite, event-source rewrite, event-tap relocation, second event tap, or normal synthetic B-UP was introduced.

## Accepted first hardware sample
The first real Receiver-B sample passed externally and internally. Internal evidence showed:

```text
REPLAY_UP_PENDING
-> REPLAY_UP_POSTED
-> REPLAY_UP_PASS_ACK
-> zero matching reconfiguration_suppress
-> B->A restore
-> primaryReady / idle
```

Replay pass acknowledgement occurred before restore begin.

## User five-run stability gate — PASS
The user reports all five authorized natural Receiver-B samples succeeded.

For each RUN_1..RUN_5, user-observed acceptance is:

```text
FIRST_TAP_OPENS_A: NO
FIRST_TAP_OPENS_B: NO
SECOND_LONG_OPENS_B: YES
SECOND_LONG_OPENS_A: NO
B_CLOSES_ON_PHYSICAL_RELEASE: YES
DUPLICATE_TEXT: NO
STUCK_STATE: NO
```

Classification: `USER_RECEIVER_B_STABILITY_5_OF_5 = PASS`.

## Authorized next action — read-only five-run evidence review
Do not perform any additional remote or physical Option gesture.

Use append-safe snapshotting if needed; live log growth alone is not runtime drift. Identify the five successful true-B transactions and return a per-run matrix.

For every run verify:

```text
TRUE_B_TRANSACTION: YES
REPLAY_UP_PENDING: YES
REPLAY_UP_POSTED: YES
REPLAY_UP_PASS_ACK: YES
REPLAY_UP_TIMESTAMP_MATCH: YES
MATCHING_RECONFIGURATION_SUPPRESS_COUNT: 0
REPLAY_UP_ACK_BEFORE_RESTORE: YES
B_TO_A_RESTORE_SUCCEEDED: YES
FINAL_MAPPING: left_option
FINAL_FILTER_TARGET: left_option
FINAL_PHASE: primaryReady
FINAL_TRANSACTION: none
FINAL_HARDWARE_GATE: none
FINAL_BLE_STATE: idle/not streaming
SYNTHETIC_TRIGGER_DOWN_COUNT: 0
SYNTHETIC_TRIGGER_UP_COUNT: 0
```

Also return first-UP -> secondary-ready and second-DOWN-gap timing for each run to prove each sample remained within the accepted natural double-press path.

## Stop boundary
If any of the five runs cannot be cleanly correlated, lacks replay-UP acknowledgement, contains a matching replay-UP `reconfiguration_suppress`, restores A before ACK, fails B->A restore, or ends with residual ownership/runtime state: STOP. Do not repair, retry, Set C, or merge.

If all five pass the internal evidence review: return `TASK028_FIVE_RUN_EVIDENCE = PASS` and stop for final Web acceptance / merge-closeout decision.
