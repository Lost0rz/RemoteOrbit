# RemoteOrbit Current Task

## Current task — RECEIVER-B REPLAY-UP ACKNOWLEDGED RESTORE CORRECTIVE

- **Status:** SINGLE HARDWARE SAMPLE + CAUSAL LOG VALIDATION PASS / USER 5x RECEIVER-B STABILITY GATE AUTHORIZED / MERGE FORBIDDEN
- **Task ID:** `RO-DUAL-RECEIVER-B-UP-REPLAY-ACK-CORRECTIVE-028`
- **Implementation base:** `458e28d91b5ff748613bb88f5b89212d660279c7`
- **Product implementation / installed source:** `f938b919e288a481f5eacaf9aad9c254dcf0cffe`
- **Final corrective branch HEAD:** `85bb2e12cad41198e5a27d9e610cbdb30b01d357`
- **Authorized branch:** `codex/dual-receiver-b-up-replay-ack-fix`
- **Authorized worktree:** `/private/tmp/remoteorbit-dual-receiver-b-up-replay-ack-fix`
- **Merge:** FORBIDDEN

## Control publication reconciliation
The intermediate commits `1ac9fbf3571357a2cb5b168d84ccf50c7f3b12ae`, `ec0091d7868c8bc1efea76f39862e7e7e874e163`, and `d08a1cdef85280acac08d7c066537056e1c0b39a` were docs-only partial publications. This commit is the authoritative atomic republication of `CURRENT_STATUS.md` + `CURRENT_TASK.md`; no product/test/runtime code changed in those intermediate commits.

## Accepted defect and correction
The observed stuck Receiver-B failure was caused by the copied Right Option UP being reposted at `.cghidEventTap`, then swallowed by B->A reconfiguration suppression before downstream delivery.

Task 028 correction keeps the copied hardware UP owned until its exact replay re-enters `VoiceKeyFilter` and reaches the pass path. Only after all expected replay-UP components are acknowledged may B->A restore begin.

No fixed delay, flag rewrite, event-source rewrite, event-tap relocation, second event tap, or normal synthetic B-UP is used.

## First real hardware acceptance — PASS
User performed exactly one natural Receiver-B sample and reported:

```text
B opened normally
physical release closed B normally
no stuck state
```

Read-only evidence for gesture `5A66F46A-5817-48E1-9A14-3C903B7AD55D` established:

```text
FIRST_UP_TO_SECONDARY_READY_MS: 22.797
SECOND_DOWN_GAP_MS: 139.672
B_CLASSIFIED: hold
FIRST_PCM_BEFORE_B_DOWN_REPLAY: YES
ORIGINAL_B_UP_CAPTURED: YES
ORIGINAL_B_UP_TIMESTAMP: 11046382134235
REPLAY_UP_PENDING: YES
REPLAY_UP_POSTED: YES
REPLAY_UP_PASS_ACK: YES
REPLAY_UP_ACK_TIMESTAMP: 11046382134235
REPLAY_UP_TIMESTAMP_MATCH: YES
SAME_REPLAY_UP_RECONFIGURATION_SUPPRESS_COUNT: 0
REPLAY_UP_PASS_ACK_BEFORE_RESTORE: YES
B_TO_A_RESTORE_SUCCEEDED: YES
FINAL_F5_MAPPING: left_option
FINAL_FILTER_TARGET: left_option
FINAL_MAPPING_PHASE: primaryReady
FINAL_TRANSACTION: none
FINAL_HARDWARE_GATE: none
FINAL_BLE_STATE: idle / not streaming
SYNTHETIC_TRIGGER_DOWN_COUNT: 0
SYNTHETIC_TRIGGER_UP_COUNT: 0
```

Ordering evidence: replay pass acknowledgement seq 543 occurred before B->A restore begin seq 544.

## Current authorization — 5x Receiver-B stability gate
The user may now perform five natural Receiver-B samples. For each sample:

```text
quick first tap
-> immediate second LONG
-> speak briefly
-> release normally
```

Do not deliberately slow the second press.

Record for each run:

```text
RUN_1..RUN_5
FIRST_TAP_OPENS_A: expected NO
FIRST_TAP_OPENS_B: expected NO
SECOND_LONG_OPENS_B: expected YES
SECOND_LONG_OPENS_A: expected NO
B_CLOSES_ON_PHYSICAL_RELEASE: expected YES
DUPLICATE_TEXT: expected NO
STUCK_STATE: expected NO
```

## Stop boundary
If any run fails any expected item:
- STOP immediately after that first failure;
- do not continue remaining runs;
- do not retry to overwrite the failed sample;
- preserve logs read-only;
- no source/settings/mapping/restart changes;
- no Set C;
- no merge.

If all five pass:
- still do not merge or Set C;
- perform one read-only evidence review across the five runs;
- at minimum confirm each true-B transaction has `REPLAY_UP_PENDING -> REPLAY_UP_POSTED -> REPLAY_UP_PASS_ACK`, zero matching replay-UP `reconfiguration_suppress`, successful B->A restore, and final `primaryReady`/idle;
- return the 5-run result and evidence to Web for final Task-028 acceptance and next-step decision.
