# CURRENT_STATUS

Last updated: 2026-10-07
State: ACTIVE INCIDENT — JOURNAL READY / MOMENTARY TRIGGER RECONCILIATION BEFORE USER A
Repository: `Lost0rz/RemoteOrbit`

This file is the authority for mutable current project state. Historical detail remains preserved in Git history.

## Control-plane integrity

- Previous control HEAD: `e6f13c057e6e4d5b3d7cd3e8585e4775f7004b43`.
- Candidate branch remains `codex/disabled-short-classifier-regression-fix` at exact HEAD `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`.
- Candidate source is unchanged and unmerged.
- Prior B4 external event-plane investigation remains PAUSED.

## Installed candidate and current observed configuration

```text
CANDIDATE_HEAD: 172427957fd18a2b5827edd1cb1c4bddb6a5b7db
INSTALLED_RUNTIME_PID: 79232
INSTALLED_SOURCE_HEAD: 172427957fd18a2b5827edd1cb1c4bddb6a5b7db
INSTALLED_SHA256: a033e86a92b02175a498bba3232c5ae8b72719caef781cb74c3187e8e64ed017
SHORT_BINDING: Disabled
MOMENTARY_TRIGGER_OBSERVED: right_option
PERSISTENT_TRIGGER_OBSERVED: left_option
LEGACY_TRIGGER_OBSERVED: right_option
CURRENT_INPUT_SOURCE: com.bytedance.inputmethod.doubaoime.pinyin
SOURCE_MUTATION: NO
MERGED: NO
HARDWARE_ACCEPTANCE_A_OR_B_PERFORMED: NO
```

## Diagnostic journal readiness — CLOSED

```text
PREINSTALL_RECORD1_EQUALS_BLOCKED_LIVE_RECORD1: YES
ARCHIVE_HASH_MATCH: YES
FRESH_JOURNAL_STATE: absent/empty
DIAGNOSTICS_STATUS_EXIT: 0
DIAGNOSTICS_VERIFY_EXIT: 0
DIAGNOSTICS_QUERY_EXIT: 0
```

The corrupt journal predated the candidate installation and was archived intact. The same installed candidate relaunched successfully and the fresh journal path is readable.

## Trigger-authority reconciliation

Independent source audit establishes:

- the device-scoped HID mapping target is `currentMomentaryVoiceTriggerKey`;
- idle remote voice uses the `momentaryTrigger` policy and logs/owns the configured momentary key;
- startup runtime restore reads the persisted momentary and persistent keys;
- the legacy key is retained as a compatibility/diagnostic field and is not the current HID mapping authority.

Therefore the prior Gate 0 requirement that momentary/persistent/legacy all equal `left_option` was too broad.

For User A causal comparability with the sealed incident, the required trigger condition is:

```text
MOMENTARY_TRIGGER = left_option
```

The observed `right_option` momentary setting is a real blocker because it changes the physical/system-mapped HID target. The observed legacy `right_option` is not an A blocker. Persistent is already `left_option` and must remain unchanged.

## Authorized reconciliation before User A

Only this setting change is authorized:

- user changes the RemoteOrbit **momentary trigger** through the normal app settings UI from Right Option to Left Option.

Do not edit UserDefaults directly. Do not change legacy. Do not change persistent. Do not restart/rebuild/reinstall the app.

After the user change, local execution may only verify read-only that:

```text
SHORT = Disabled
MOMENTARY_TRIGGER = left_option
PERSISTENT_TRIGGER = left_option
CURRENT_INPUT_SOURCE = com.bytedance.inputmethod.doubaoime.pinyin
HID mapping/readback target = left_option
candidate source/head/hash unchanged
```

Legacy may remain `right_option`; report it but do not treat it as failure.

When these conditions pass, User A is authorized. The next hardware action remains exactly one fast physical click/release. User B remains forbidden until A passes.
