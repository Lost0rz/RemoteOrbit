# RemoteOrbit Current Task

## Current task — RIGHT OPTION PHYSICAL-VS-REPLAY EVENT-SHAPE SOURCE AUDIT

- **Status:** ACTIVE / READ-ONLY CODE FORENSICS
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

## Authorized work
Detailed read-only source/evidence audit only.

Inspect the exact product implementation and tests for:

1. `VoiceKeyFilter` mapped-trigger event tap handling;
2. `HardwareOptionGate` ownership/resolution;
3. storage/copying of captured mapped DOWN and UP events;
4. replay/post implementation for the copied mapped DOWN and UP;
5. event `type`, key code, modifier flags, source/state/PID-related fields, userData marker, timestamp, and target event tap;
6. DOWN/UP symmetry;
7. A (`left_option`) versus B (`right_option`) symmetry;
8. ordering of physical UP, mapped B-UP capture, output-drain completion, B-UP replay/exposure, gate close, and B->A mapping/filter restoration;
9. tests that exercise the real event-filter/replay seam versus tests that only assert internal callbacks/state.

Use existing source/history/evidence only. Do not mutate diagnostics to collect more fields in this task.

## Required conclusions
Return a source-backed matrix that separates:

- **FACT** — directly established by source/history/current evidence;
- **INFERENCE** — strongly supported but not observed externally;
- **HYPOTHESIS** — requires a new validation.

Explicitly answer:

```text
IS_REPLAY_THE_ORIGINAL_COPIED_CGEVENT: YES/NO/PARTIAL
DOWN_UP_REPLAY_SYMMETRIC: YES/NO/PARTIAL
A_B_REPLAY_CODEPATH_IDENTICAL: YES/NO/PARTIAL
CAN_MAPPING_RESTORE_RACE_EXTERNAL_B_UP: YES/NO/UNKNOWN
CURRENT_TESTS_PROVE_EXTERNAL_EVENT_EQUIVALENCE: YES/NO
ROOT_CAUSE_PROVEN_FROM_CODE_ALONE: YES/NO
```

If `ROOT_CAUSE_PROVEN_FROM_CODE_ALONE = NO`, define the smallest next validation. Prefer a one-run, read-only comparison of a physical Right Option sequence against a RemoteOrbit B replay sequence. State exactly which CGEvent fields must be captured and why. Do not implement that validation yet.

## Strict prohibitions

```text
NO product source edits
NO test edits
NO diagnostic instrumentation edits
NO build/install/restart
NO settings/mapping changes
NO remote Set-B retry
NO Set C
NO release/drain retune
NO HardwareOptionGate redesign
NO BLE/audio changes
NO driver/CoreAudio/TCC changes
NO merge
```

## Stop
Stop after the read-only audit and recommendation. Any diagnostic implementation or corrective code requires a new explicitly authorized task.
