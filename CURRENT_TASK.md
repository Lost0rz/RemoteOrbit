# RemoteOrbit Current Task

## Current task — SET B RELEASE INCIDENT CAPTURE

- **Status:** INCIDENT / READ-ONLY EVIDENCE ONLY
- **Task ID:** `RO-DUAL-RECEIVER-SYSTEM-MAPPED-IMPLEMENTATION-023`
- **Previous phase:** Set A PASS / Set B authorized
- **Incident:** first Set-B attempt opened B, release did not close B, later attempts failed
- **v2 branch:** `codex/dual-receiver-system-mapped-routing-v2`
- **v2 HEAD:** `e1e6fe0bf76e245c4237978600b117b5b8e2a83e`
- **Installed source:** `50a20174632dc105fb670a9b83e3f6feaa8e9f9b`
- **Incident note:** `docs/incidents/2026-10-08-set-b-first-open-no-release.md`
- **Merge:** FORBIDDEN

## User-observed incident

```text
Attempt 1:
quick first tap + second LONG
-> Receiver B opened
-> physical release did not close/end B

Afterward:
subsequent attempts could not open normally
```

Do not infer root cause from the user-visible behavior alone.

## Authorized work
Read-only capture only. No further user/executor gestures are required before capture.

Locate the first Set-B attempt and any already-recorded immediate follow-on attempts. Return exact event ordering and timestamps for:

1. first raw F5 DOWN/UP;
2. A->B mapping apply start/end, `A_TO_B_APPLY_MS`, `FIRST_UP_TO_SECONDARY_READY_MS`;
3. second physical F5 DOWN/UP and `SECOND_DOWN_READY_BEFORE_EDGE`;
4. mapped Right Option DOWN/UP capture/defer/replay/discard;
5. HardwareOptionGate begin / long-ready / release / close;
6. B classification and first PCM;
7. AUDIO_START / AUDIO_STOP;
8. VoicePressCoordinator release/tail/output-drain ownership transitions;
9. `MOMENTARY_COMPLETE` or its absence;
10. B->A restore request/apply/filter update/readback, including `B_TO_A_APPLY_MS`;
11. runtime lock / reconfiguration / unavailable transitions;
12. final F5 mapping, filter target, mapping phase, active transaction, hardware gate and BLE state.

Also record any `SYNTHETIC_OWNER_*` state events separately from actual `SYNTHETIC_TRIGGER_DOWN/UP` edges.

## Classification questions
The capture must distinguish, without fixing:

```text
SECOND_PHYSICAL_UP_OBSERVED: YES/NO
MAPPED_B_UP_OBSERVED: YES/NO
B_HARDWARE_GATE_RELEASED: YES/NO
OUTPUT_DRAIN_COMPLETED: YES/NO
MOMENTARY_COMPLETE: YES/NO
B_TO_A_RESTORE_REQUESTED: YES/NO
B_TO_A_RESTORE_SUCCEEDED: YES/NO
FINAL_MAPPING_IS_A: YES/NO
FINAL_PHASE_PRIMARY_READY: YES/NO
RUNTIME_LOCKED_OR_UNAVAILABLE: YES/NO
EXTERNAL_B_STILL_OPEN_WHILE_INTERNAL_IDLE: YES/NO/UNKNOWN
```

## Strict prohibitions

```text
NO further remote gestures
NO Set C
NO settings changes
NO mapping changes
NO app restart
NO build/install
NO source/test edits
NO behavior fix
NO driver/CoreAudio/TCC changes
NO merge
```

## Required handoff

```text
TASK_ID: RO-DUAL-RECEIVER-SYSTEM-MAPPED-IMPLEMENTATION-023
INCIDENT: SET_B_OPEN_NO_RELEASE
CONTROL_HEAD:
BRANCH_HEAD:
INSTALLED_SOURCE_HEAD:
RUNNING_PID:

USER_REPORT:
EVIDENCE_WINDOW:
GESTURE_ID:

FIRST_UP_TO_SECONDARY_READY_MS:
A_TO_B_APPLY_MS:
SECOND_DOWN_GAP_MS:
SECOND_DOWN_READY_BEFORE_EDGE:

SECOND_PHYSICAL_UP_OBSERVED:
MAPPED_B_DOWN_OBSERVED:
MAPPED_B_UP_OBSERVED:
B_HARDWARE_GATE_BEGIN:
B_HARDWARE_GATE_LONG_READY:
FIRST_PCM_BEFORE_REPLAY:
B_HARDWARE_GATE_RELEASED:

AUDIO_START:
AUDIO_STOP:
OUTPUT_DRAIN_COMPLETED:
MOMENTARY_COMPLETE:

B_TO_A_RESTORE_REQUESTED:
B_TO_A_APPLY_MS:
B_TO_A_RESTORE_SUCCEEDED:

FINAL_F5_MAPPING:
FINAL_FILTER_TARGET:
FINAL_MAPPING_PHASE:
FINAL_TRANSACTION:
FINAL_HARDWARE_GATE:
FINAL_BLE_STATE:
RUNTIME_LOCKED_OR_UNAVAILABLE:

SYNTHETIC_TRIGGER_DOWN_COUNT:
SYNTHETIC_TRIGGER_UP_COUNT:

FOLLOW_ON_FAILED_ATTEMPTS_PRESENT:
FOLLOW_ON_FAILURE_MECHANISM:

ROOT_CAUSE: UNKNOWN unless directly proven by ordering evidence
PRODUCT_SOURCE_CHANGED: NO
TEST_SOURCE_CHANGED: NO
APP_RESTARTED: NO
MERGED: NO

FINAL_STATE: SET_B_RELEASE_INCIDENT_EVIDENCE_READY_FOR_WEB_AUDIT
```

Stop after capture. Do not repair.
