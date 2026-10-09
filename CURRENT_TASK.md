# RemoteOrbit Current Task

## Current task — TASK 028 MERGE AND CLOSEOUT

- **Status:** FINAL WEB ACCEPTANCE PASS / MERGE AUTHORIZED / CLOSEOUT PENDING
- **Task ID:** `RO-DUAL-RECEIVER-B-UP-REPLAY-ACK-CORRECTIVE-028`
- **Implementation base:** `458e28d91b5ff748613bb88f5b89212d660279c7`
- **Product implementation / installed source:** `f938b919e288a481f5eacaf9aad9c254dcf0cffe`
- **Accepted corrective branch HEAD:** `85bb2e12cad41198e5a27d9e610cbdb30b01d357`
- **Authorized branch:** `codex/dual-receiver-b-up-replay-ack-fix`
- **Authorized worktree:** `/private/tmp/remoteorbit-dual-receiver-b-up-replay-ack-fix`
- **Merge:** AUTHORIZED by user after final 5/5 evidence acceptance

## Accepted correction
The stuck Receiver-B failure was caused by the replayed copied Right Option UP being swallowed by B->A reconfiguration suppression before downstream delivery.

Task 028 keeps the expected replay-UP owned until the exact copied event re-enters `VoiceKeyFilter` and reaches the pass path; only then may B->A restore begin.

## Final acceptance
All required gates passed:

```text
USER_RECEIVER_B_STABILITY: 5/5 PASS
INTERNAL_CORRECTED_ORDERING: 5/5 PASS
TASK028_FIVE_RUN_EVIDENCE: PASS
TASK028_CAUSAL_CORRECTIVE_CONFIRMED: YES
```

Each accepted run proved:
- true B transaction;
- first PCM before B DOWN replay;
- original Right Option UP captured;
- `REPLAY_UP_PENDING`;
- `REPLAY_UP_POSTED`;
- `REPLAY_UP_PASS_ACK` with matching key/type/original Quartz timestamp;
- zero matching replay-UP `reconfiguration_suppress`;
- replay ACK before B->A restore;
- B->A restore success;
- final Left Option / `primaryReady` / no transaction or gate / BLE idle;
- normal synthetic trigger DOWN/UP count 0/0.

## Authorized action
Perform the merge without altering accepted product behavior.

Merge resolution contract:
1. Keep current-main `CURRENT_STATUS.md` and `CURRENT_TASK.md` as control authority.
2. Bring in the accepted product/test tree from corrective branch HEAD `85bb2e12...`.
3. Preserve current-main-only incident/spec/plan documentation.
4. Do not introduce any additional product or diagnostic edits.
5. Create a true merge commit with current authorized main as first parent and `85bb2e12...` as second parent.
6. Fast-forward `main` to that merge commit only if the live main ref still equals the audited authorized control HEAD.

## Post-merge gate
After merge:
- verify the merge parents;
- verify product/test paths exactly match the accepted corrective branch;
- verify current-main-only documentation remains present;
- verify control files remain the merge-authorized versions;
- verify no unexpected paths changed.

If these remote checks pass, publish a direct-child control commit marking:

```text
TASK 028 = CLOSED / ACCEPTED_MAIN
```

That closeout commit may authorize local worktree/branch cleanup. Do not perform release/install/Set C or new hardware testing as part of this merge.
