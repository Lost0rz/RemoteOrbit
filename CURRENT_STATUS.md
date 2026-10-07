# CURRENT_STATUS

Last updated: 2026-10-07
State: ACTIVE INCIDENT — USER A FAST-CLICK HARDWARE ACCEPTANCE READY
Repository: `Lost0rz/RemoteOrbit`

This file is the authority for mutable current project state. Historical detail remains preserved in Git history.

## Control-plane integrity

- Previous control HEAD: `074875a0df8e8bd26ca3b508ece97243787f57a0`.
- Candidate branch remains `codex/disabled-short-classifier-regression-fix` at exact HEAD `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`.
- Candidate source is unchanged and unmerged.
- Prior B4 external event-plane investigation remains PAUSED.

## Installed exact candidate

```text
INSTALLED_RUNTIME_PID: 79232
INSTALLED_SOURCE_HEAD: 172427957fd18a2b5827edd1cb1c4bddb6a5b7db
INSTALLED_SHA256: a033e86a92b02175a498bba3232c5ae8b72719caef781cb74c3187e8e64ed017
SHORT_BINDING: Disabled
PERSISTENT_TRIGGER: left_option
CURRENT_INPUT_SOURCE: com.bytedance.inputmethod.doubaoime.pinyin
APP_RESTARTED_DURING_RECONCILIATION: NO
SOURCE_MUTATION: NO
REBUILD_OR_REINSTALL: NO
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

The old incompatible/corrupt first record predated the candidate installation and the blocked journal was archived intact. The same installed candidate relaunched successfully and the fresh journal path is readable.

## Momentary trigger reconciliation — PASS

Latest reconciliation report establishes:

```text
MOMENTARY_AFTER: left_option in running app bundle-ID preference domain
UI_SCREENSHOT: Left Option
HID_MAPPING_TARGET_AFTER: left_option
HID_READBACK_VERIFY: MATCH for 0x7000000E2
LATER_FILTER_CONFIGURED_KEY: left_option
PERSISTENT: left_option
INPUT_SOURCE: com.bytedance.inputmethod.doubaoime.pinyin
```

There is a storage/readback discrepancy between the separate RemoteOrbit suite and the running app bundle-ID preference domain for momentary/legacy values. For this acceptance, the effective runtime authority is established by the running app value plus HID readback/filter configuration. The discrepancy is recorded but is not a blocker to User A.

## Active causal test — User A

The accepted candidate restores only the Disabled-SHORT classifier boundary introduced before PR #14:

```text
SHORT = Disabled
fast physical click < 300 ms
→ classify SHORT
→ drop Disabled short action
→ no HOLD promotion
→ hardware gate cancels
→ no short replay
→ no synthetic trigger
```

User A is now authorized.

Decision after A:

- Valid fast click + Doubao Session does NOT open => `A_PASS_READY_FOR_USER_B`.
- Valid fast click + Doubao Session opens => `CLASSIFIER_FIXED_EXTERNAL_MECHANISM_REMAINS`; do not perform B.
- Press >= 300 ms => `INVALID_FOR_A`; allow one retry only.

Do not merge candidate before A/B acceptance.
