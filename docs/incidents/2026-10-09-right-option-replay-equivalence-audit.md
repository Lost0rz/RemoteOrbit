# Task 027 — Right Option physical-vs-replay equivalence audit

This note records a read-only source/evidence audit. Product code, tests, runtime, mappings, settings, drivers, and installed app are not authorized to change in this task.

## Accepted boundary

- Task 025 proved a true Receiver-B transaction completed internally, including mapped Right Option DOWN/UP ownership, output drain, gate close, `MOMENTARY_COMPLETE`, and B->A restore.
- Task 026 proved a direct physical Right Option hold opens Receiver B and physical release immediately closes it.
- Accepted classification: `REMOTEORBIT_REPLAY_NOT_EXTERNALLY_EQUIVALENT_TO_PHYSICAL_RIGHT_OPTION`.

## Source findings

### Capture/replay
`VoiceKeyFilter` runs a head-insert `.cghidEventTap` for keyDown/keyUp/flagsChanged. During mapped-trigger ownership it suppresses the original matching event and stores `event.copy()`.

For a long hardware transaction:

1. mapped DOWN component(s) are copied/suppressed;
2. first PCM calls `releaseDeferredOption`;
3. `.hardwareReplay` posts the copied DOWN event(s) at `.cghidEventTap`;
4. physical remote release arms the held-release owner;
5. mapped UP component(s) are copied/suppressed;
6. output drain calls `releaseHeldHardwareOption`;
7. copied UP event(s) are posted at `.cghidEventTap`;
8. only after this call does the controller enqueue the B->A restore check.

Normal hardware replay does not construct a new synthetic modifier event and does not add `Key.syntheticMarker`. Emergency balancing UP remains a fallback only when no copied UP exists.

### Key identity
Right Option uses:

```text
CG keyCode = 61
HID usage = 0xE6
hidutil destination = 0x7000000E6
generic flag = maskAlternate
device-side flag = NX_DEVICERALTKEYMASK
```

Left Option uses keyCode 58 / HID usage 0xE2 and the left-side device flag. The normal replay functions are otherwise shared and parameterized by `momentaryVoiceTriggerKey`.

### Symmetry
A and B use the same source-level replay path. DOWN and UP use the same copy-and-post mechanism, but their lifecycle is intentionally asymmetric: DOWN is replayed at first PCM while UP is held until physical release plus output drain.

### Restore ordering
Program order proves the B-UP `post(.cghidEventTap)` call occurs before the controller schedules B->A restoration. It does not prove the external receiver has consumed the posted UP before mapping restoration starts.

### Tests
Existing `DualReceiverVoiceTransactionTests` model copied mapped events using `captureDeferredHardwareOptionEdgeForTesting(... copied: true)` and validate ownership/callback ordering. They do not post a real captured CGEvent through the downstream macOS event system or verify Receiver-B behavior. `VoiceKeyFilterTests` cover recognition/suppression/ownership but not physical-vs-replay downstream equivalence. `VoiceBoundaryOrderingTests` cover diagnostic callback ordering, not Quartz event equivalence.

### Existing diagnostics
`MAPPED_TRIGGER_EVENT` already records keyCode, event type, raw flags, synthetic-marker classification, gate/action, observer uptime and raw Quartz timestamp. It does not currently record all event-source PID/state, keyboard type or other provenance fields.

## Required answers

```text
IS_REPLAY_THE_ORIGINAL_COPIED_CGEVENT: YES (a copy of the original CGEvent; not identical object identity)
DOWN_UP_REPLAY_SYMMETRIC: PARTIAL
A_B_REPLAY_CODEPATH_IDENTICAL: YES at source level
CAN_MAPPING_RESTORE_RACE_EXTERNAL_B_UP: UNKNOWN
CURRENT_TESTS_PROVE_EXTERNAL_EVENT_EQUIVALENCE: NO
ROOT_CAUSE_PROVEN_FROM_CODE_ALONE: NO
```

## Next minimum validation
Before adding instrumentation, use existing logs only:

- frozen Task-025 true-B snapshot;
- current logs containing the already-completed Task-026 direct physical Right Option hold/release.

Compare component count/order, type, keyCode, flags, timestamps, and the captured/replayed action sequence. If the basic event shape differs, the difference is already actionable evidence. If it matches but source/provenance fields are absent, only then consider a small passive observer in a separate authorized task.
