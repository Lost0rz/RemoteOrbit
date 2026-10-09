# RemoteOrbit Current Task

## Current task — RIGHT OPTION PHYSICAL-VS-REPLAY EVENT-SHAPE AUDIT

- **Status:** ACTIVE / SOURCE AUDIT COMPLETE / READ-ONLY EXISTING-LOG COMPARISON AUTHORIZED
- **Task ID:** `RO-DUAL-RECEIVER-RIGHT-OPTION-EVENT-SHAPE-AUDIT-027`
- **Previous task:** `RO-DUAL-RECEIVER-B-EXTERNAL-SEMANTICS-GATE-026` — CLOSED / EXTERNAL SEMANTICS VERIFIED
- **Corrective branch under audit:** `codex/dual-receiver-mic-debounce-corrective`
- **Corrective branch HEAD:** `458e28d91b5ff748613bb88f5b89212d660279c7`
- **Installed source (last local evidence):** `406f1242e7c3bc17b1fa0da43b069a0b2c6874c8`
- **Merge:** FORBIDDEN

## Accepted problem boundary

```text
Physical Right Option hold -> Receiver B opens
Physical Right Option release -> Receiver B immediately closes

RemoteOrbit true B transaction -> internally completes DOWN/UP/drain/gate-close/MOMENTARY_COMPLETE/B->A restore
BUT Receiver B remains open
```

Accepted classification:

`REMOTEORBIT_REPLAY_NOT_EXTERNALLY_EQUIVALENT_TO_PHYSICAL_RIGHT_OPTION`

## Source-audit conclusions

```text
IS_REPLAY_THE_ORIGINAL_COPIED_CGEVENT: YES (event.copy(), not same object identity)
DOWN_UP_REPLAY_SYMMETRIC: PARTIAL
A_B_REPLAY_CODEPATH_IDENTICAL: YES at source level, parameterized by trigger key
CAN_MAPPING_RESTORE_RACE_EXTERNAL_B_UP: UNKNOWN
CURRENT_TESTS_PROVE_EXTERNAL_EVENT_EQUIVALENCE: NO
ROOT_CAUSE_PROVEN_FROM_CODE_ALONE: NO
```

Clarification for `DOWN_UP_REPLAY_SYMMETRIC = PARTIAL`:
- both sides use copied system-mapped events and repost at `.cghidEventTap`;
- DOWN is captured/suppressed then replayed at first PCM;
- UP is captured/suppressed later, held through output drain, then replayed;
- therefore mechanism is shared but lifecycle/timing is intentionally asymmetric.

## Authorized next evidence step
Use only existing evidence. Do not perform a new remote or physical-key gesture unless Web explicitly authorizes one after this comparison.

1. Verify the frozen Task-025 snapshot hashes and extract the true-B mapped Right Option event records.
2. Snapshot the current diagnostic logs read-only and locate the already-performed Task-026 direct physical Right Option hold/release.
3. Compare at minimum:

```text
event_type
key_code
flags raw
generic/device-side flag presence
synthetic_marker
eventSourceUserData if available
cg_event_timestamp_raw
observer_uptime
action/gate_state
component count/order (flagsChanged/keyDown/keyUp)
```

For the Task-025 B sequence, distinguish:

```text
original mapped DOWN captured: defer_down
replayed copied DOWN returning through filter: pass
original mapped UP captured: hold_release
replayed copied UP returning through filter: pass
```

Correlate copied replay records by key/type/flags and identical original Quartz timestamp where the existing log permits it. Do not guess if correlation is ambiguous.

For the physical Right Option sequence, identify the direct pass-through component count/order and flags. The Task-026 user result is already accepted: open YES, release-close YES, stuck NO.

## Required evidence conclusion
Return one of:

```text
BASIC_EVENT_SHAPE_DIFF_PROVEN
BASIC_EVENT_SHAPE_MATCHES_BUT_SOURCE_FIELDS_MISSING
INSUFFICIENT_EXISTING_LOG_EVIDENCE
```

If basic shape matches but source fields are missing, recommend (do not implement) the smallest one-run passive observer needed to capture `eventSourceUnixProcessID`, `eventSourceStateID`, `eventSourceUserData`, keyboard type, event type/keyCode/flags/timestamp, and observation point.

## Strict prohibitions

```text
NO product source edits
NO test edits
NO diagnostic instrumentation edits
NO build/install/restart
NO settings/mapping changes
NO new remote Set-B retry
NO new physical Right Option test
NO Set C
NO release/drain retune
NO HardwareOptionGate redesign
NO BLE/audio changes
NO driver/CoreAudio/TCC changes
NO merge
```

## Stop
Stop after the existing-log comparison and recommendation. Any new instrumentation or corrective product code requires a new explicitly authorized task.
