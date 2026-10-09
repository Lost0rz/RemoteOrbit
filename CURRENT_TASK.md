# RemoteOrbit Current Task

## Current task — LIFECYCLE RECONCILIATION BATCH 2

- **Status:** ACTIVE / READ-ONLY LIFECYCLE RECONCILIATION
- **Task ID:** `RO-LIFECYCLE-RECONCILIATION-BATCH2-033`
- **Control parent:** `5971f384f8011ac4a0fe3a32f959a63a54a635ab`
- **Canonical path:** `/Volumes/Jack-Dev/Projects/remoteorbit`

## Why this task exists
Task 032's five exact lifecycle objects are already absent. The latest executor run performed no cleanup mutation and returned five `SKIPPED_DUE_TO_DRIFT` results because the exact worktree paths, local branches, and live remote branches were already gone.

The prior closeout attribution of five successful removals is superseded by the corrective control-plane transition that activated this task.

A fresh read-only inventory is required before any further lifecycle deletion because the remaining population includes dirty worktrees, forensic lineages, historical Jack-Dev worktrees, `/private/tmp` worktrees, and UNKNOWN/unclassified objects.

## Goal
Produce one evidence-backed compact manifest of every remaining RemoteOrbit lifecycle object sharing the canonical Git common directory, and classify each object without mutation.

The result must distinguish:
- `CANONICAL_ACTIVE`
- `ACTIVE_TASK`
- `MERGED_CLEAN_REMOTE_COVERED`
- `REMOTE_COVERED_BUT_RETAINED`
- `LOCAL_UNIQUE_HISTORY`
- `DIRTY_UNCOMMITTED`
- `FORENSIC_RETAIN`
- `STALE_REGISTRATION_CANDIDATE`
- `UNKNOWN`

This task may propose exact candidates for a later cleanup batch, but it does not authorize deleting them.

## Gate 0 — authority and freshness
From `/Volumes/Jack-Dev/Projects/remoteorbit`:
1. verify the canonical checkout exists, is on `main`, and is clean before synchronization;
2. `git fetch origin --prune`;
3. require local `main` to fast-forward only to the live `origin/main` carrying this Task-033 control transition;
4. re-read `AGENTS.md` if present, `CURRENT_STATUS.md`, and `CURRENT_TASK.md`;
5. require `CURRENT_TASK.md` to identify `RO-LIFECYCLE-RECONCILIATION-BATCH2-033` before continuing.

If the canonical checkout is dirty, cannot fast-forward, or the task identity differs: STOP with no mutation.

## Gate 1 — common-dir and worktree inventory
Read only:
- `git rev-parse --git-common-dir`
- `git worktree list --porcelain`

For every registered worktree record:
- exact path and `realpath` when the path exists;
- branch or detached state;
- HEAD;
- whether the path exists;
- storage class: `AIR_TEMP`, `JACK_DEV_PROJECTS`, `JACK_DEV_WORKTREES`, or other;
- clean/dirty tracked state;
- untracked-file count;
- whether the worktree is locked/prunable according to Git metadata.

Do not run `git worktree prune`.

## Gate 2 — local branch/ref inventory
Read only:
- local branches and exact heads;
- upstream names when configured;
- local commits not in `origin/main`;
- local commits not in the branch's live remote counterpart when one exists;
- whether each branch head is an ancestor of current `origin/main`.

Do not delete or rename refs.

## Gate 3 — live remote branch inventory
Use live remote evidence, not cached refs alone.

Inventory all live RemoteOrbit `codex/*` branch names and heads. For each local lifecycle branch, record:
- live remote counterpart present/absent;
- exact live remote HEAD when present;
- ahead/behind relationship where meaningful;
- whether both local and remote heads are contained in current `origin/main`.

Do not delete remote branches.

## Gate 4 — protected lineage rules
The following categories remain protected regardless of age or naming:
- any dirty worktree;
- any object with untracked files not proven derived/recreatable;
- any local-only commit not already preserved by an accepted authority;
- any FORENSIC lineage;
- any object whose classification is `UNKNOWN`;
- the distinct branch `codex/dual-receiver-momentary-routing-v1-plan` until this task explicitly classifies it.

Do not infer safety from "no open PR" alone.

## Gate 5 — exact candidate proposal
For an object to be proposed as `MERGED_CLEAN_REMOTE_COVERED`, provide all of:
- exact worktree path;
- exact local branch;
- exact local HEAD;
- clean tracked state;
- zero untracked files;
- zero local commits outside current `origin/main`;
- live remote counterpart state/head when applicable;
- zero unpushed commits relative to the live counterpart when applicable;
- local head contained in current `origin/main`;
- remote head contained in current `origin/main` when a remote counterpart exists.

Any missing proof => not a cleanup candidate.

## Forbidden
No state-changing lifecycle or product action is authorized:
- no `git worktree remove` or `prune`;
- no branch/tag/ref deletion;
- no remote branch deletion;
- no reset/restore/clean/stash;
- no merge/rebase/cherry-pick/commit/push except the initial ff-only main synchronization already authorized by Gate 0;
- no source/test/runtime/settings/mapping/build/install/hardware changes.

## Required final receipt
Return:
```text
RO_LIFECYCLE_RECONCILIATION_BATCH2

CONTROL_HEAD:
ORIGIN_MAIN:
CANONICAL_HEAD:
CANONICAL_CLEAN:
COMMON_GIT_DIR:

REGISTERED_WORKTREE_COUNT:
LOCAL_BRANCH_COUNT:
LIVE_REMOTE_CODEX_BRANCH_COUNT:

WORKTREES:
  - path:
    exists:
    storage:
    branch_or_detached:
    head:
    clean:
    untracked_count:
    classification:
    reason:

DIRTY_OR_UNIQUE_PROTECTED:
  - ...

FORENSIC_RETAIN:
  - ...

UNKNOWN_RETAIN:
  - ...

PROPOSED_NEXT_CLEANUP_CANDIDATES:
  - path:
    branch:
    local_head:
    live_remote_head:
    all_candidate_gates_pass:

MUTATIONS_PERFORMED: NONE

FINAL_STATE:
BATCH2_RECONCILIATION_READY_FOR_WEB_AUDIT
or
STOP_<reason>
```
