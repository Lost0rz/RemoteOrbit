# CURRENT_STATUS

Last updated: 2026-10-07
State: ACTIVE INCIDENT — CANDIDATE INSTALLED / DIAGNOSTIC JOURNAL READINESS RECOVERY AUTHORIZED
Repository: `Lost0rz/RemoteOrbit`

This file is the authority for mutable current project state. Historical detail remains preserved in Git history.

## Control-plane integrity

- Previous control HEAD: `db6f61a972d4ba3c395a12b242596e6f6b28505b`.
- Candidate branch remains `codex/disabled-short-classifier-regression-fix` at exact HEAD `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`.
- Candidate source is unchanged and unmerged.
- Prior B4 external event-plane investigation remains PAUSED.

## Installed candidate

```text
CANDIDATE_HEAD: 172427957fd18a2b5827edd1cb1c4bddb6a5b7db
INSTALLED_RUNTIME_PID_BEFORE_RECOVERY: 72913
INSTALLED_SOURCE_HEAD: 172427957fd18a2b5827edd1cb1c4bddb6a5b7db
INSTALLED_SHA256: a033e86a92b02175a498bba3232c5ae8b72719caef781cb74c3187e8e64ed017
STAGED_INSTALLED_MATCH: YES
SHORT_BINDING: Disabled
MOMENTARY_TRIGGER: left_option
PERSISTENT_TRIGGER: left_option
LEGACY_TRIGGER: left_option
OBSERVED_INPUT_SOURCE_AT_RECOVERY_GATE: com.tencent.inputmethod.chatterfly.pinyin
SOURCE_MUTATION: NO
MERGED: NO
HARDWARE_ACCEPTANCE_A_OR_B_PERFORMED: NO
```

Pre-install evidence is preserved at:

`/private/tmp/remoteorbit-disabled-short-hardware-acceptance-20261007`

Known hashes:

```text
VOICE_DIAGNOSTIC_SHA256: 77ec5da36c6c17b964965355d3bd2a455964c7e5eb655d3c674335a06ff33410
DIAGNOSTIC_JOURNAL_SHA256: 89b0b05fcb66eab1ff92dfbd7e47681bda6c66402933d51f40bfbf43299aec9b
```

## Diagnostic readiness blocker

After exact-candidate installation:

```text
diagnostics status: PASS
diagnostics verify: EXIT 65 — corrupt diagnostic journal at record 1
diagnostics query: EXIT 65 — corrupt diagnostic journal at record 1
```

Independent source audit establishes:

- `diagnostics status` checks journal existence/metadata and does not prove records decode.
- `verify` and `query` decode the JSONL from record 1 and fail closed on a corrupt/unsupported record.
- the journal writer appends by seeking to the end and does not pre-validate historical records before writing.
- therefore a pre-existing corrupt or incompatible record 1 can block CLI verification while the newly installed candidate itself remains valid.

Classification:

```text
CANDIDATE_PRODUCT_FAILURE_ESTABLISHED: NO
CURRENT_RUNTIME_JOURNAL_CORRUPTION_ESTABLISHED: NOT YET
PREEXISTING_JOURNAL_RECORD1_HYPOTHESIS: MUST BE PROVEN BEFORE ROTATION
HARDWARE_ACCEPTANCE_A: BLOCKED UNTIL READINESS RECOVERY PASSES AND DOUBAO IS RESTORED
```

## Input-source reconciliation

The prior recovery task incorrectly treated Doubao being active as a prerequisite for journal maintenance. The executor correctly observed `com.tencent.inputmethod.chatterfly.pinyin` and stopped.

For the journal-readiness task, the active input source is not part of the causal mechanism being tested. Record-1 attribution, intact journal archival, same-binary relaunch and CLI verification do not require Doubao.

Therefore:

- preserve the currently observed input source during journal recovery;
- do not switch input methods merely to satisfy the journal-recovery gate;
- do not interpret Chatterfly as a candidate/runtime failure;
- User A remains forbidden until the journal is ready and the user later restores Doubao manually;
- before User A, the active source must again be verified as `com.bytedance.inputmethod.doubaoime.pinyin`.

## Authorized runtime-evidence maintenance

Only the following is authorized before User A:

1. read-only compare record 1 of the preserved pre-install journal with record 1 of the current live journal;
2. record hashes and minimal JSON/schema facts for both first records without editing either file;
3. proceed only if the first records are byte-identical, proving the corrupt first record predates candidate installation;
4. preserve/hash the full current live journal again;
5. gracefully quit RemoteOrbit so the journal handle is closed;
6. archive/move the live journal out of the active journal pathname without deleting or truncating it, and retain a copy/reference in the evidence directory;
7. relaunch the same already-installed exact candidate app; do not rebuild or reinstall;
8. re-verify exact source HEAD, binary SHA-256 and key settings; record the active input source but do not require Doubao for this maintenance step;
9. run `diagnostics status`, `diagnostics verify`, and `diagnostics query --limit 1` against the fresh live journal path.

No hardware gesture is authorized during this recovery.

## Recovery decision

Journal recovery passes only if:

```text
PREINSTALL_RECORD1_EQUALS_BLOCKED_LIVE_RECORD1: YES
OLD_LIVE_JOURNAL_ARCHIVED_INTACT: YES
RELAUNCHED_SOURCE_HEAD: 172427957fd18a2b5827edd1cb1c4bddb6a5b7db
RELAUNCHED_BINARY_SHA256: a033e86a92b02175a498bba3232c5ae8b72719caef781cb74c3187e8e64ed017
SETTINGS_PRESERVED: YES
diagnostics status: PASS
diagnostics verify: PASS
diagnostics query --limit 1: PASS
```

If those pass while Chatterfly remains active, return `JOURNAL_READY_DOUBAO_RESTORE_REQUIRED`, not `READY_FOR_USER_A`.

Only after the user manually restores Doubao and the exact source is verified as `com.bytedance.inputmethod.doubaoime.pinyin` may the control plane advance to `READY_FOR_USER_A`.

An empty fresh journal is acceptable if `verify/query` pass and no producer naturally emitted yet. Do not synthesize an event solely to populate it.

If the preserved and live first records differ, STOP without journal rotation and return `RECORD1_ATTRIBUTION_NOT_PROVEN`.

If a fresh journal again becomes corrupt at record 1 under the same candidate, STOP and return `CURRENT_RUNTIME_DIAGNOSTIC_CORRUPTION_REPRODUCED`.

Forbidden:

- no source edit, rebuild, reinstall or merge;
- no driver/CoreAudio/LaunchAgent/TCC/settings mutation;
- no input-source change during the local journal-recovery execution;
- no journal deletion or truncation;
- no synthetic input or user SHORT/LONG gesture;
- no resumption of B4 unless Web later authorizes it.
