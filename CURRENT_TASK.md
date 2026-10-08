# RemoteOrbit Current Task

## Current task — SET B CORRECTIVE RELEASE INCIDENT CAPTURE

- **Status:** INCIDENT / READ-ONLY EVIDENCE ONLY
- **Task ID:** `RO-DUAL-RECEIVER-SET-B-RELEASE-INCIDENT-025`
- **Previous corrective:** `RO-DUAL-RECEIVER-MIC-DEBOUNCE-CORRECTIVE-024`
- **Corrective branch HEAD:** `458e28d91b5ff748613bb88f5b89212d660279c7`
- **Installed product source:** `406f1242e7c3bc17b1fa0da43b069a0b2c6874c8`
- **Installed app PID:** reported `5331`
- **Merge:** FORBIDDEN

## User-observed fresh incident
After 024 installation, the user performed exactly one natural Set-B retry:

```text
quick first tap
-> immediate second LONG
-> Receiver B opened normally
-> physical release did not close/end B normally
```

Do not perform another gesture before capture.

## What 024 already established
The previous incident's second physical DOWN had been discarded by legacy 180 ms debounce. 024 changed only the active-dual microphone input policy and added HID-boundary coverage. Automated RED/GREEN showed the 109.810 ms second DOWN reaching the recognizer and classifying B.

The fresh hardware retry opening B is consistent with that upstream defect being corrected. The remaining release failure is a separate incident and its root cause is UNKNOWN.

## Authorized work
Read-only evidence collection only. Locate the single fresh corrective Set-B attempt and return exact event ordering/timing for:

1. first raw F5 DOWN/UP;
2. A->B apply and `FIRST_UP_TO_SECONDARY_READY_MS`;
3. second raw F5 DOWN and proof it was emitted, not debounce-suppressed;
4. mapped Right Option DOWN capture/defer;
5. B HardwareOptionGate begin / long-ready;
6. B classification, AUDIO_START, first PCM, B DOWN replay;
7. second raw F5 UP and whether it was emitted;
8. mapped Right Option UP observation/capture/defer;
9. VoicePress release begin, AUDIO_STOP, tail/drain ownership, output-drain completion;
10. mapped B UP output-drained release / gate close;
11. `MOMENTARY_COMPLETE`;
12. B->A restore request/apply/filter/readback and `B_TO_A_APPLY_MS`;
13. final live F5 mapping, filter target, mapping phase, transaction, hardware gate, BLE state, runtime lock/reconfiguration state.

Also separate `SYNTHETIC_OWNER_*` state events from actual `SYNTHETIC_TRIGGER_DOWN/UP` key edges.

## Classification questions
Return explicit YES/NO/UNKNOWN for:

```text
SECOND_RAW_DOWN_EMITTED
SECOND_RAW_DOWN_DEBOUNCE_SUPPRESSED
B_HARDWARE_GATE_BEGIN
B_CLASSIFIED
B_DOWN_REPLAYED
SECOND_PHYSICAL_UP_OBSERVED
SECOND_RAW_UP_EMITTED
MAPPED_B_UP_OBSERVED
B_HARDWARE_GATE_PHYSICAL_UP
OUTPUT_DRAIN_COMPLETED
B_UP_RELEASED_AFTER_DRAIN
MOMENTARY_COMPLETE
B_TO_A_RESTORE_SUCCEEDED
FINAL_MAPPING_IS_A
FINAL_PHASE_PRIMARY_READY
FINAL_TRANSACTION_NONE
RUNTIME_LOCKED_OR_UNAVAILABLE
INTERNAL_RELEASE_COMPLETE
EXTERNAL_B_STILL_OPEN
EXTERNAL_INTERNAL_DIVERGENCE
```

Identify:

```text
LAST_KNOWN_GOOD_EVENT
FIRST_MISSING_OR_DIVERGENT_EVENT
```

Do not label root cause proven unless the ordering directly proves the failed boundary.

## Strict prohibitions

```text
NO further remote gestures
NO Set C
NO settings changes
NO mapping changes
NO app restart
NO build/install
NO source/test edits
NO release/drain fix
NO receiver shortcut changes
NO driver/CoreAudio/TCC changes
NO merge
```

## Required handoff

```text
TASK_ID: RO-DUAL-RECEIVER-SET-B-RELEASE-INCIDENT-025
CONTROL_HEAD:
CORRECTIVE_BRANCH_HEAD: 458e28d91b5ff748613bb88f5b89212d660279c7
INSTALLED_SOURCE_HEAD: 406f1242e7c3bc17b1fa0da43b069a0b2c6874c8
RUNNING_PID:

USER_REPORT:
EVIDENCE_WINDOW:
GESTURE_ID:

FIRST_UP_TO_SECONDARY_READY_MS:
A_TO_B_APPLY_MS:
SECOND_DOWN_GAP_MS:
SECOND_RAW_DOWN_EMITTED:
SECOND_RAW_DOWN_DEBOUNCE_SUPPRESSED:
SECOND_DOWN_READY_BEFORE_EDGE:

MAPPED_B_DOWN_OBSERVED:
B_HARDWARE_GATE_BEGIN:
B_HARDWARE_GATE_LONG_READY:
B_CLASSIFIED:
FIRST_PCM_BEFORE_REPLAY:
B_DOWN_REPLAYED:

SECOND_PHYSICAL_UP_OBSERVED:
SECOND_RAW_UP_EMITTED:
MAPPED_B_UP_OBSERVED:
B_HARDWARE_GATE_PHYSICAL_UP:

VOICE_PRESS_RELEASE_BEGIN:
AUDIO_STOP:
OUTPUT_DRAIN_BEGIN:
OUTPUT_DRAIN_COMPLETED:
B_UP_RELEASED_AFTER_DRAIN:
B_HARDWARE_GATE_CLOSED:
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
VOICE_TRIGGER_RUNTIME_LOCKED:
VOICE_TRIGGER_RECONFIGURATION_IN_PROGRESS:
RUNTIME_LOCKED_OR_UNAVAILABLE:

SYNTHETIC_OWNER_STATE_EVENTS:
SYNTHETIC_TRIGGER_DOWN_COUNT:
SYNTHETIC_TRIGGER_UP_COUNT:

INTERNAL_RELEASE_COMPLETE:
EXTERNAL_B_STILL_OPEN: USER_REPORTED_YES
EXTERNAL_INTERNAL_DIVERGENCE:

LAST_KNOWN_GOOD_EVENT:
FIRST_MISSING_OR_DIVERGENT_EVENT:
ROOT_CAUSE: UNKNOWN unless directly proven by this fresh ordering evidence

PRODUCT_SOURCE_CHANGED: NO
TEST_SOURCE_CHANGED: NO
APP_RESTARTED: NO
REMOTE_GESTURES_PERFORMED_BY_EXECUTOR: NO
MERGED: NO

FINAL_STATE: SET_B_CORRECTIVE_RELEASE_EVIDENCE_READY_FOR_WEB_AUDIT
```

Stop after capture. Do not repair.
