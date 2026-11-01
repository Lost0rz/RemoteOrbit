# Task 045B Domain 2 — Legacy Voice Persisted Preference Authority

Date: 2026-11-01
Audit basis: `main@1ba1f142a20a1da7a6ad7e6494d2126bc738c327`
Status: `AUDIT_COMPLETE / FROZEN_FOR_IMPLEMENTATION`

## Design question

Can the obsolete Persistent-session and Receiver-B persisted preferences be retired independently from their historical runtime state machines, without changing the current LONG-only microphone contract or forcing a broad runtime rewrite?

## Verified constraints

- The production RC003 microphone path is Gate A direct voice. Application mapping and the historical short/long classifier do not participate in the production microphone DOWN/UP path, and HID button-down policy is evaluated with Dual mode forced to `.legacy`.
- `VoiceInputProfileStore` is the retained user configuration authority. When no profile ID exists it seeds only from the old momentary trigger; Persistent and Receiver-B keys are deliberately ignored.
- AppStorage still creates/reads/writes a Persistent preference and a Receiver-B preference. Its old migration can create a Persistent preference from the generic legacy trigger.
- `restoreVoiceTriggerRuntime()` still reads those two preferences and hydrates historical runtime state, despite the direct production microphone path not using them.
- After Domain 1, product UI no longer calls the Persistent/Receiver-B reconfiguration entry points. Those methods are historical runtime/test seams.
- Persistent and Dual state machines still have substantial ownership/timing/safety tests. Deleting them together with storage would cross a materially larger runtime boundary.

## Selected option

Retire the **persisted preference authority only** in Domain 2.

The launched product will stop reading, creating, restoring, and writing Persistent-session and Receiver-B preferences. Existing historical UserDefaults bytes are not actively deleted; they become inert and therefore cannot compete with the selected `VoiceInputProfile` while remaining available for rollback to an older binary.

The old Persistent/Dual state machines and their runtime-only current-state values remain for later dedicated domains. Runtime-only configuration seams may stay where needed for deterministic tests, but they must no longer persist retired product preferences.

## Rejected alternatives

### Delete persistence and both state machines together

Rejected because it combines storage authority retirement with ownership/timing state-machine retirement. That would widen the change into Dual mapping transactions, Persistent toggle semantics, and a large safety-test surface, violating serial domain cleanup.

### Keep the preferences because the runtime code still has matching fields

Rejected because this preserves hidden legacy product authority after its product surface has already been retired. A stale Receiver-B or Persistent value should not continue influencing launched-product startup.

### Actively delete old UserDefaults values

Not selected for Domain 2. Ignoring obsolete values fully removes their authority with less irreversible user-data mutation and preserves rollback compatibility. Physical preference-byte cleanup can be considered separately if it ever has operational value.

## Ownership and compatibility implications

`KEEP`:

- `VoiceInputProfileStore.selectedProfileIDKey` and selected profile persistence;
- `RemoteOrbit.voiceTriggerKey` and `RemoteOrbit.momentaryVoiceTriggerKey` only as compatibility/migration projection for the retained profile/direct trigger authority;
- current direct voice trigger runtime and HID mapping behavior;
- mapping schema and `.voiceKeyDefault` Codable compatibility token.

`RETIRE`:

- `RemoteOrbit.persistentSessionTriggerKey` as active application storage authority;
- `RemoteOrbit.secondaryMomentaryVoiceTriggerKey` as active application storage authority;
- migration that seeds Persistent configuration;
- production restore/write coupling to those preferences;
- tests that define their AppStorage round-trip as current product behavior.

`FROZEN`:

- Persistent coordinator state machine and its runtime behavior;
- Dual Receiver gesture/mapping state machine and its runtime behavior;
- current runtime-only Persistent/secondary fields while those machines exist;
- LONG-only correctness mechanisms.

## Verification implications

Implementation must prove:

- old Persistent/Receiver-B UserDefaults values cannot become active startup authorities;
- generic/momentary compatibility still migrates correctly into the selected voice profile;
- runtime-only Persistent/Dual tests keep their behavioral assertions after any storage-oriented harness cleanup;
- LONG-only regression remains green;
- full Release and Universal2 durable CI remain green.

## Consequences

Production startup becomes single-authority for user voice destination: selected `VoiceInputProfile` plus its bounded momentary compatibility projection. Historical Persistent/Dual runtime code can no longer be reactivated merely by stale stored preferences.

## Reversibility

High. Existing obsolete UserDefaults bytes are left untouched, and the historical runtime code remains until later domains. A rollback to an older binary can still observe the old stored values.

## Task reconciliation

`TASK_RECONCILIATION_REQUIRED: YES`

Reason: Domain 1 is merged/closed and the authorized mutation boundary advances to the separately audited Domain 2 persisted-preference authority.

Durable document: this file.