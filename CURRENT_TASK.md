# RemoteOrbit Current Task

## Current task — RECEIVER-B REPLAY-UP ACKNOWLEDGED RESTORE CORRECTIVE

- **Status:** WEB AUDIT PASS / USER RECEIVER-B HARDWARE GATE AUTHORIZED / MERGE FORBIDDEN
- **Task ID:** `RO-DUAL-RECEIVER-B-UP-REPLAY-ACK-CORRECTIVE-028`
- **Implementation base:** `458e28d91b5ff748613bb88f5b89212d660279c7`
- **Product implementation / installed source:** `f938b919e288a481f5eacaf9aad9c254dcf0cffe`
- **Final corrective branch HEAD:** `85bb2e12cad41198e5a27d9e610cbdb30b01d357`
- **Authorized branch:** `codex/dual-receiver-b-up-replay-ack-fix`
- **Authorized worktree:** `/private/tmp/remoteorbit-dual-receiver-b-up-replay-ack-fix`
- **Merge:** FORBIDDEN

## Accepted defect and corrective contract
The observed stuck Receiver-B failure was caused by the copied Right Option UP being reposted at `.cghidEventTap`, then being swallowed by B->A reconfiguration suppression before downstream delivery.

Task 028 correction is accepted by independent source audit:

```text
capture mapped B UP
-> retain copied event
-> output drain
-> register pending replay-UP ownership
-> post copied B UP
-> copied event re-enters VoiceKeyFilter
-> exact fingerprint matches pending replay
-> PASS event unchanged
-> acknowledge replay component
-> after all expected components pass, enqueue B->A restore
-> restore primary A mapping/filter
```

Identity/ordering constraints verified in source:
- gesture-scoped pending owner;
- keyCode + event type + original Quartz timestamp component fingerprint;
- wrong/stale/unrelated/duplicate component cannot acknowledge;
- pending replay remains active hardware ownership and blocks reconfiguration;
- acknowledgement is evaluated before `reconfiguration_suppress`;
- matching replay passes unchanged;
- restore is initiated only after replay acknowledgement;
- stop/supersede/HID-removal invalidate pending replay ownership;
- no fixed delay, flags rewrite, source rewrite, tap relocation, second event tap, or normal synthetic B-UP.

## Automated evidence
Local executor reported:

```text
VoiceKeyFilterTests: 16/16
DualReceiverVoiceTransactionTests: 20/20
VoiceTriggerRuntimeTests: 53/53
VoicePressCoordinatorTests: 38/38
Full Swift: 394/394
Self-tests: 3/3
Release build/package: PASS
Signature verification: PASS
git diff --check: PASS
Scope audit: PASS
```

Independent Web did not rerun the local Swift/build commands. It independently audited remote lineage/diff/source and found no scope blocker for the first hardware gate.

TDD caveat: the initial RED was compile-time because the required pending replay/ack seams were absent, rather than a behavioral test reaching the old race. Preserve this note. The prior Task-027 real runtime trace remains the behavioral evidence of the old defect.

## Authorized next action — one user hardware sample only
User performs exactly one natural Receiver-B gesture:

```text
first tap: quick press/release
second press: immediately LONG
speak
release normally
```

Observe:

```text
FIRST_TAP_OPENS_A: expected NO
FIRST_TAP_OPENS_B: expected NO
SECOND_LONG_OPENS_B: expected YES
SECOND_LONG_OPENS_A: expected NO
B_CLOSES_ON_PHYSICAL_RELEASE: expected YES
DUPLICATE_TEXT: expected NO
STUCK_STATE: expected NO
```

Do not deliberately slow the second press.

## Stop boundary
If any expected item fails:
- STOP immediately;
- do not repeat to replace the failed sample;
- preserve logs;
- no code/settings/mapping/restart changes;
- no Set C;
- no merge.

If the one sample passes:
- still do not Set C or merge;
- perform read-only evidence capture for that exact sample;
- verify `REPLAY_UP_PENDING -> REPLAY_UP_POSTED -> REPLAY_UP_PASS_ACK` and absence of matching replay-UP `reconfiguration_suppress`;
- verify B->A restore succeeds and final mapping/filter phase returns to A / `primaryReady` / idle;
- return evidence to Web before expanding to 5/5 Receiver-B stability acceptance.
