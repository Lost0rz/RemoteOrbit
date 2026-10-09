# RemoteOrbit Current Task

## Current task — TASK 028 LIFECYCLE CLEANUP

- **Status:** ACTIVE / CLEANUP ONLY
- **Task ID:** `RO-TASK028-LIFECYCLE-CLEANUP-029`
- **Accepted main before this transition:** `24bcb623803b2ca867fe142bdc8d84f174afc8cc`
- **Merged task branch:** `codex/dual-receiver-b-up-replay-ack-fix`
- **Expected task branch HEAD:** `85bb2e12cad41198e5a27d9e610cbdb30b01d357`
- **Expected worktree:** `/private/tmp/remoteorbit-dual-receiver-b-up-replay-ack-fix`
- **Product task 028:** CLOSED / ACCEPTED_MAIN / MERGED

## Goal
Leave a clean single accepted baseline after Task 028 by removing only the merged Task-028 worktree and task branch after proving there is no unique local work.

## Gate 0 — freshness
Read `AGENTS.md`, `CURRENT_STATUS.md`, and this file. Fetch/prune remote refs. Verify live remote main equals this cleanup control HEAD and live remote task branch, if still present, equals `85bb2e12cad41198e5a27d9e610cbdb30b01d357`.

If control HEAD or branch identity drifted: STOP and report.

## Gate 1 — bounded local inventory
Before deletion, report:
- canonical main path / branch / HEAD / clean state;
- registered worktree list;
- Task-028 worktree path / branch / HEAD / status including untracked files;
- local commits on task branch not reachable from accepted main;
- local commits not pushed to the remote task branch;
- whether task branch is fully contained in accepted main.

Required PASS conditions:
```text
TASK_WORKTREE_EXISTS: YES
TASK_WORKTREE_BRANCH: codex/dual-receiver-b-up-replay-ack-fix
TASK_WORKTREE_HEAD: 85bb2e12cad41198e5a27d9e610cbdb30b01d357
TASK_WORKTREE_DIRTY_OR_UNTRACKED: NO
UNIQUE_LOCAL_COMMITS_NOT_IN_MAIN: 0
UNPUSHED_TASK_COMMITS: 0
TASK_BRANCH_CONTAINED_IN_MAIN: YES
```

If any PASS condition fails: STOP. Do not force-delete, reset, clean, stash, or move files.

## Gate 2 — cleanup
Only after Gate 1 PASS:
1. change directory outside the task worktree;
2. remove the task worktree without `--force`;
3. run `git worktree prune`;
4. delete local `codex/dual-receiver-b-up-replay-ack-fix` with `git branch -d` only;
5. re-fetch remote refs and verify the remote task branch still points exactly to `85bb2e12cad41198e5a27d9e610cbdb30b01d357`;
6. delete the remote task branch;
7. update canonical main with `git switch main` + `git pull --ff-only origin main`;
8. verify canonical main clean.

## Final evidence
Return:
```text
CONTROL_HEAD
REMOTE_MAIN
CANONICAL_MAIN_HEAD
LOCAL_REMOTE_MAIN_MATCH
CANONICAL_MAIN_CLEAN
TASK_WORKTREE_REMOVED
WORKTREE_REGISTRATION_REMOVED
LOCAL_TASK_BRANCH_REMOVED
REMOTE_TASK_BRANCH_REMOVED
UNIQUE_WORK_LOST: NO
REMAINING_WORKTREES
REMAINING_REMOTE_TASK_BRANCHES
PRODUCT_SOURCE_CHANGED: NO
RUNTIME_CHANGED: NO
FINAL_STATE: CLEANUP_READY_FOR_WEB_CLOSEOUT
```

No product/test/runtime/settings/mapping/release/driver/TCC/hardware changes are authorized. Stop after evidence; Web performs final closeout classification.
