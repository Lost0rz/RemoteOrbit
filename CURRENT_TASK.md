# RemoteOrbit Current Task

## Current task — AIR TEMP WORKTREE RETIREMENT BATCH 3

- **Status:** ACTIVE / EXACT WORKTREE-ONLY CLEANUP
- **Task ID:** `RO-AIR-TEMP-WORKTREE-RETIREMENT-BATCH3-034`
- **Control parent:** `c81a3342ef538bec90ddbdc83d74a45789765776`
- **Canonical path:** `/Volumes/Jack-Dev/Projects/remoteorbit`

## Goal
Remove only the physical registered `/private/tmp` worktrees listed below while deliberately retaining every associated local branch and live remote branch. This task frees stale Air temporary checkouts without discarding Git history.

## Exact authorized worktrees

1. `/private/tmp/remoteorbit-b4-external-event-plane-verification`
   - branch `codex/b4-external-event-plane-verification`
   - expected local HEAD `bcc2591db627914b6900a96c6f7bcfc3ca0b5e1f`
   - expected live remote HEAD `1ad28f3448894642d67b22fffebfe2daa5b47947`

2. `/private/tmp/remoteorbit-b4-post-capture-neighbor-audit`
   - branch `codex/b4-post-capture-neighbor-audit`
   - expected local HEAD `6ee9f262e19168cf466a42261fcb3b205c5df3b7`
   - expected live remote HEAD `703f53eae1db05f593148ea87a239cd92d468ec1`

3. `/private/tmp/remoteorbit-b7-audio-consumer-boundary-audit`
   - branch `codex/b7-audio-consumer-boundary-audit`
   - expected local/remote HEAD `d751375eac7c058f7ba9fa05bc1ba15bfa0b3961`

4. `/private/tmp/remoteorbit-b7-baseline-pref-reconciliation`
   - branch `codex/b7-baseline-pref-reconciliation`
   - expected local/remote HEAD `062347ea0f69c3aed402976bd53a50e35e4675a7`

5. `/private/tmp/remoteorbit-b7-consumer-stop-precursor-audit`
   - branch `codex/b7-consumer-stop-precursor-audit`
   - expected local/remote HEAD `b8e1b5c56b7e1d046743fc2d94e52537b31c73d9`

6. `/private/tmp/remoteorbit-b7-mapping-semantic-diff-audit`
   - branch `codex/b7-mapping-semantic-diff-audit`
   - expected local/remote HEAD `de368eca920b8c23f354e4ea79f2f103972a3133`

7. `/private/tmp/remoteorbit-b7-pending-prewarm-isolation`
   - branch `codex/b7-pending-prewarm-isolation`
   - expected local/remote HEAD `e7eacf414b3698fca4ae091d011055f63c0aa97d`

8. `/private/tmp/remoteorbit-b7-prewarm-b-capture`
   - branch `codex/b7-prewarm-b-capture`
   - expected local/remote HEAD `ecad84fd4432b72c887b7212c38859303b36f9bc`

9. `/private/tmp/remoteorbit-b7-prewarm-b-capture-v2`
   - branch `codex/b7-prewarm-b-capture-v2`
   - expected local/remote HEAD `126de807434872d8a47caa8a2c09873e40561092`

10. `/private/tmp/remoteorbit-b7-stop-initiator-audit`
    - branch `codex/b7-stop-initiator-audit`
    - expected local/remote HEAD `f534655b17720489ad71e9d7c257b9edb8bb216c`

11. `/private/tmp/remoteorbit-b8-frontmost-boundary-audit`
    - branch `codex/b8-frontmost-boundary-audit`
    - expected local/remote HEAD `457ea252082c30641c4aa477c29de94e5333fd0f`

12. `/private/tmp/remoteorbit-disabled-short-classifier-regression-fix`
    - branch `codex/disabled-short-classifier-regression-fix`
    - expected local/remote HEAD `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`

13. `/private/tmp/remoteorbit-dual-receiver-momentary-routing-v1-plan`
    - branch `codex/dual-receiver-momentary-routing-v1-plan`
    - expected local/remote HEAD `6415c6baccae75b220391568d77b546c5cbbefe8`

14. `/private/tmp/remoteorbit-persistent-pending-prewarm-fix-candidate`
    - branch `codex/persistent-pending-prewarm-fix-candidate`
    - expected local/remote HEAD `b1411a981d0b024affd8b9f2cc42b6fd2bd707d8`

## Gate 0 — authority and freshness
From the canonical repository:
1. require current checkout `main` and clean;
2. `git fetch origin --prune`;
3. fast-forward only to the live `origin/main` carrying this task;
4. re-read `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md`;
5. require Task ID `RO-AIR-TEMP-WORKTREE-RETIREMENT-BATCH3-034`.

If authority differs or canonical is dirty: STOP with no lifecycle mutation.

## Gate 1 — single process/open-file snapshot
Before any worktree removal, capture one read-only `lsof -nP` snapshot. For each exact target path, check whether any live process has an open file or current object under that exact path.

If a target is in active use, mark only that target `SKIPPED_ACTIVE_USE` and do not remove it.

## Gate 2 — per-object fresh safety check
Immediately before removing each target independently, require all of:
- registered worktree exists at the exact path;
- realpath equals the exact authorized `/private/tmp` path;
- attached branch equals the exact authorized branch;
- local HEAD equals the expected local HEAD;
- `git status --porcelain -uall` is empty;
- zero untracked files;
- no active-use match from Gate 1;
- live remote counterpart exists at the exact expected remote HEAD;
- expected local HEAD is equal to or an ancestor of the expected live remote HEAD.

This task does **not** require either branch head to be contained in `main`, because the branch itself is intentionally retained as history authority.

Any failed check => `SKIPPED_DUE_TO_DRIFT` for that object only. Never force-remove.

## Gate 3 — authorized mutation
For each independently passing object, from the canonical repo run only:

`git worktree remove <exact-path>`

No `--force`.

Do not run `git worktree prune`.

Do not delete or rename the local branch.
Do not delete or modify the remote branch.
Do not reset, clean, stash, merge, rebase, cherry-pick, or commit product files.

## Gate 4 — post-remove history preservation check
After each successful worktree removal, verify:
- exact worktree path absent;
- worktree no longer registered;
- exact local branch still exists at its pre-removal local HEAD;
- exact live remote branch still exists at its pre-removal remote HEAD.

If branch history changed unexpectedly, STOP further mutation and report the drift.

## Protected / forbidden
Do not touch:
- canonical `/Volumes/Jack-Dev/Projects/remoteorbit`;
- `/private/tmp/remoteorbit-persistent-long-primary-failure-attribution`;
- `/Volumes/Jack-Dev/Projects/remoteorbit-p0-voice-experiment`;
- `/Volumes/Jack-Dev/Projects/remoteorbit-voice-p0-final`;
- `/Volumes/Jack-Dev/Projects/remoteorbit-audio-p0`;
- `/Volumes/Jack-Dev/Projects/remoteorbit-audio-p1-a3`;
- `/Volumes/Jack-Dev/Projects/remoteorbit-audio-p1-a4`;
- `/Volumes/Jack-Dev/Projects/remoteorbit-audio-p1-a5`;
- `/Volumes/Jack-Dev/Projects/RemoteOrbit-flight-recorder`;
- any local/remote branch or ref;
- any source/test/runtime/settings/mapping/build/install/hardware state.

## Required final receipt
Return:
```text
RO_AIR_TEMP_WORKTREE_RETIREMENT_BATCH3

CONTROL_HEAD:
ORIGIN_MAIN:
CANONICAL_HEAD:
CANONICAL_CLEAN:

PER_OBJECT:
  - path:
    branch:
    expected_local_head:
    expected_remote_head:
    clean:
    untracked_count:
    active_use:
    remote_head_match:
    local_ancestor_of_remote:
    result: REMOVED / SKIPPED_ACTIVE_USE / SKIPPED_DUE_TO_DRIFT
    local_branch_retained:
    remote_branch_retained:

SUCCESSFUL_REMOVALS:
SKIPPED_ACTIVE_USE:
SKIPPED_DUE_TO_DRIFT:

REGISTERED_WORKTREE_COUNT_FINAL:
LOCAL_BRANCH_COUNT_FINAL:
LIVE_REMOTE_CODEX_BRANCH_COUNT_FINAL:

PROTECTED_OBJECTS_MODIFIED: NO
BRANCHES_DELETED: 0
REMOTE_BRANCHES_DELETED: 0
PRODUCT_TEST_RUNTIME_CHANGED: NO

FINAL_STATE:
BATCH3_WORKTREE_ONLY_CLEANUP_READY_FOR_WEB_CLOSEOUT
or
BATCH3_PARTIAL_WORKTREE_ONLY_CLEANUP_READY_FOR_WEB_RECONCILIATION
or
STOP_<reason>
```
