# CURRENT_STATUS

Last updated: 2026-10-07
State: ACTIVE INCIDENT — JOURNAL READY / USER A HARDWARE ACCEPTANCE AUTHORIZED
Repository: `Lost0rz/RemoteOrbit`

This file is the authority for mutable current project state. Historical detail remains preserved in Git history.

## Control-plane integrity

- Previous control HEAD: `650770958ee49fc8048654404cc815c51fee4958`.
- Candidate branch remains `codex/disabled-short-classifier-regression-fix` at exact HEAD `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`.
- Candidate source is unchanged and unmerged.
- Prior B4 external event-plane investigation remains PAUSED.

## Installed candidate

```text
CANDIDATE_HEAD: 172427957fd18a2b5827edd1cb1c4bddb6a5b7db
INSTALLED_RUNTIME_PID: 79232
INSTALLED_SOURCE_HEAD: 172427957fd18a2b5827edd1cb1c4bddb6a5b7db
INSTALLED_SHA256: a033e86a92b02175a498bba3232c5ae8b72719caef781cb74c3187e8e64ed017
SHORT_BINDING: Disabled
MOMENTARY_TRIGGER: left_option
PERSISTENT_TRIGGER: left_option
LEGACY_TRIGGER: left_option
SOURCE_MUTATION: NO
MERGED: NO
HARDWARE_ACCEPTANCE_A_OR_B_PERFORMED: NO
```

## Diagnostic journal readiness — CLOSED

Recovery evidence:

```text
PREINSTALL_RECORD1_SHA256: 43efe4c23a94cec53727d1b48e19427b91b2de582f836f021220334e7a24640a
BLOCKED_LIVE_RECORD1_SHA256: 43efe4c23a94cec53727d1b48e19427b91b2de582f836f021220334e7a24640a
PREINSTALL_RECORD1_EQUALS_BLOCKED_LIVE_RECORD1: YES
BLOCKED_LIVE_FULL_SHA256: 89b0b05fcb66eab1ff92dfbd7e47681bda6c66402933d51f40bfbf43299aec9b
ARCHIVED_JOURNAL_SHA256: 89b0b05fcb66eab1ff92dfbd7e47681bda6c66402933d51f40bfbf43299aec9b
ARCHIVE_HASH_MATCH: YES
FRESH_JOURNAL_STATE: absent/empty
DIAGNOSTICS_STATUS_EXIT: 0
DIAGNOSTICS_VERIFY_EXIT: 0
DIAGNOSTICS_QUERY_EXIT: 0
```

The corrupt first record predated the candidate installation and the blocked journal was archived intact. The same installed candidate relaunched successfully and the fresh journal path passes status/verify/query. Therefore the diagnostic-readiness blocker is closed.

## Input-source observation during recovery

```text
INPUT_SOURCE_BEFORE_RECOVERY_RELAUNCH: com.tencent.inputmethod.chatterfly.pinyin
INPUT_SOURCE_AFTER_RECOVERY_RELAUNCH: com.bytedance.inputmethod.doubaoime.pinyin
INPUT_SOURCE_CHANGED_DURING_RECOVERY: YES
INPUT_SOURCE_CHANGE_COMMAND_EXECUTED_BY_AGENT: NO
CAUSE_OF_INPUT_SOURCE_CHANGE: UNKNOWN
```

Do not attribute this source change to RemoteOrbit. The journal-recovery task did not issue an input-source change command. The current post-relaunch source is the required Doubao source for hardware acceptance, so this observation is not a blocker to User A. Before User A, perform one read-only confirmation that the currently active source is still `com.bytedance.inputmethod.doubaoime.pinyin`. If it is not, STOP without changing it and return the actual source.

## Active causal test

The accepted candidate restores only the Disabled-SHORT classifier boundary introduced before PR #14:

```text
SHORT = Disabled
fast physical click < hold threshold
→ classify SHORT
→ drop Disabled short action
→ no HOLD promotion
→ hardware gate cancels
→ no short replay
→ no synthetic trigger
```

User A is now authorized after the read-only Doubao confirmation.

Decision after A:

- If a valid fast click is classified SHORT and Doubao Session does **not** open: proceed to one true LONG B.
- If a valid fast click is classified SHORT but Doubao Session still opens: STOP at `CLASSIFIER_FIXED_EXTERNAL_MECHANISM_REMAINS`; resume B4 later.
- If the click crosses the threshold, mark `INVALID_FOR_A` and allow one retry only.

Do not merge candidate before A/B acceptance.
