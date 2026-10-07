# RemoteOrbit Current Task

## Current task — RO-INCIDENT-20261004-01 / DIAGNOSTIC JOURNAL READINESS RECOVERY BEFORE USER A

- **Status:** ACTIVE / RUNTIME EVIDENCE MAINTENANCE ONLY
- **Incident ID:** `RO-INCIDENT-20261004-01`
- **Candidate branch:** `codex/disabled-short-classifier-regression-fix`
- **Candidate HEAD:** `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`
- **Installed exact candidate SHA-256:** `a033e86a92b02175a498bba3232c5ae8b72719caef781cb74c3187e8e64ed017`
- **Installed PID before this recovery:** `72913`
- **Evidence directory:** `/private/tmp/remoteorbit-disabled-short-hardware-acceptance-20261007`
- **Source mutation:** FORBIDDEN
- **Rebuild/reinstall:** FORBIDDEN
- **Merge:** FORBIDDEN
- **User hardware A/B:** BLOCKED until this task returns `READY_FOR_USER_A`

## Objective

Recover a trustworthy fresh DiagnosticAuthority journal without losing or altering the existing evidence, after the exact candidate installation exposed:

```text
diagnostics status: PASS
diagnostics verify: EXIT 65 — corrupt diagnostic journal at record 1
diagnostics query: EXIT 65 — corrupt diagnostic journal at record 1
```

This task is not a product fix and does not diagnose the Disabled-SHORT behavior itself.

## Source-audit basis

Current implementation behavior has been independently checked:

1. `diagnostics status` reports file metadata and does not decode journal records.
2. `verify/query` decode from JSONL record 1 and fail closed on corrupt/unsupported data.
3. `JSONLinesDiagnosticJournal.append` seeks to the end and appends without validating old records first.
4. Therefore the existing record-1 failure may predate this candidate and must be attributed before any live-journal rotation.

Do not waive `verify/query`. Do not delete or truncate the journal.

## Gate 0 — current authority and identity

1. `git fetch origin --prune`.
2. Verify live `origin/main` exactly equals the control HEAD containing this task.
3. Verify `origin/codex/disabled-short-classifier-regression-fix` exactly equals `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`.
4. Read `AGENTS.md`, `CURRENT_STATUS.md`, and `CURRENT_TASK.md` from that live `origin/main`.
5. Verify the installed RemoteOrbit still has:
   - source HEAD `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`;
   - executable SHA-256 `a033e86a92b02175a498bba3232c5ae8b72719caef781cb74c3187e8e64ed017`;
   - SHORT = Disabled;
   - momentary/persistent/legacy = `left_option`;
   - Doubao input source remains active.
6. No hardware gesture.

Any identity/config mismatch => STOP.

## Gate 1 — prove record-1 provenance read-only

Locate:

- the pre-install journal copy/hash preserved in `/private/tmp/remoteorbit-disabled-short-hardware-acceptance-20261007`;
- the current live `diagnostic-events-v1.jsonl` used by the installed candidate.

Without modifying either file:

1. extract only raw record 1 from each;
2. record byte count and SHA-256 of each raw record 1;
3. compare them byte-for-byte;
4. report whether each record is valid JSON;
5. if valid JSON, report only structural metadata useful for compatibility attribution (for example schema/version/event name/source revision when present); do not dump unrelated payload/user content;
6. preserve these findings in the evidence directory.

PASS condition:

```text
PREINSTALL_RECORD1_EQUALS_BLOCKED_LIVE_RECORD1: YES
```

If NO or indeterminate => STOP at:

```text
RECORD1_ATTRIBUTION_NOT_PROVEN
```

Do not rotate/archive the live journal in that case.

## Gate 2 — archive blocked live journal intact

Only after Gate 1 PASS:

1. hash the complete current live journal and record size/mtime/path;
2. copy it into the evidence directory if an exact copy is not already present;
3. verify the copied hash matches the live hash;
4. gracefully terminate RemoteOrbit PID/runtime and confirm it exits;
5. after the process has exited, rename/move the live `diagnostic-events-v1.jsonl` to an archival filename that cannot be reopened as the active journal, preserving bytes exactly;
6. hash the archived file and require it equals the pre-move live hash;
7. do not delete/truncate/edit the archived journal.

Do not touch voice diagnostic logs or other diagnostic evidence except read/copy/hash.

## Gate 3 — relaunch same installed candidate and recover readiness

Do not rebuild or reinstall.

1. launch the existing `/Applications/RemoteOrbit.app` normally;
2. record new PID;
3. re-check:
   - source HEAD exactly `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`;
   - executable SHA-256 exactly `a033e86a92b02175a498bba3232c5ae8b72719caef781cb74c3187e8e64ed017`;
   - SHORT still Disabled;
   - momentary/persistent/legacy still `left_option`;
   - Doubao input source remains active;
4. inspect the live diagnostic journal pathname read-only.
5. Run:
   - `diagnostics status`
   - `diagnostics verify`
   - `diagnostics query --limit 1`

Required readiness:

```text
STATUS_EXIT: 0
VERIFY_EXIT: 0
QUERY_EXIT: 0
```

If a fresh journal naturally contains a record, report its schema/event/source revision and prove it belongs to the current candidate where available. If the journal is absent/empty but the CLI legitimately returns success, do not generate synthetic events merely to populate it.

If the fresh journal immediately reproduces a corrupt first record => STOP at:

```text
CURRENT_RUNTIME_DIAGNOSTIC_CORRUPTION_REPRODUCED
```

Do not proceed to User A.

## Gate 4 — handoff only

If Gates 0–3 pass, stop and return:

```text
READY_FOR_USER_A
```

Do not perform the user's fast-click A yourself. Do not ask the user to do LONG yet.

## Forbidden

- no product source/test/control mutation during local execution;
- no rebuild/reinstall of candidate;
- no merge/rebase/cherry-pick/amend;
- no driver/CoreAudio/LaunchAgent/TCC/Accessibility/Input Monitoring changes;
- no UserDefaults/settings reset or trigger-key change;
- no journal deletion, truncation, in-place edit or repair;
- no synthetic trigger/event generation;
- no remote hardware gesture A/B;
- no broad B4 investigation.

## Required report

```text
TASK_ID: RO-DIAGNOSTIC-JOURNAL-READINESS-RECOVERY-003
CONTROL_HEAD:
CANDIDATE_HEAD: 172427957fd18a2b5827edd1cb1c4bddb6a5b7db
INSTALLED_SOURCE_HEAD_BEFORE:
INSTALLED_SHA256_BEFORE:
SETTINGS_BEFORE:

PREINSTALL_JOURNAL_PATH:
BLOCKED_LIVE_JOURNAL_PATH:
PREINSTALL_RECORD1_SHA256:
BLOCKED_LIVE_RECORD1_SHA256:
PREINSTALL_RECORD1_EQUALS_BLOCKED_LIVE_RECORD1:
RECORD1_JSON_CLASSIFICATION:
RECORD1_COMPATIBILITY_METADATA:

BLOCKED_LIVE_FULL_SHA256:
ARCHIVED_JOURNAL_PATH:
ARCHIVED_JOURNAL_SHA256:
ARCHIVE_HASH_MATCH:

RELAUNCHED_PID:
RELAUNCHED_SOURCE_HEAD:
RELAUNCHED_SHA256:
SETTINGS_AFTER:
FRESH_LIVE_JOURNAL_PATH:
FRESH_LIVE_JOURNAL_STATE:
STATUS_EXIT:
VERIFY_EXIT:
QUERY_EXIT:
FRESH_RECORD_METADATA:

SOURCE_MUTATION: NO
REBUILD_OR_REINSTALL: NO
MERGED: NO
HARDWARE_ACTION_A_OR_B: NOT PERFORMED
FINAL_STATE:
```
