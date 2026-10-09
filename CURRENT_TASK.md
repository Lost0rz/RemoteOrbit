# RemoteOrbit Current Task

## Current task — LIFECYCLE CLEANUP BATCH 1

- **Status:** ACTIVE / EXACT FIVE-ITEM CLEANUP
- **Task ID:** `RO-LIFECYCLE-CLEANUP-BATCH1-032`
- **Control parent:** `8d0822bba3a66f1ea1144149d3aa726479110e60`
- **Canonical path:** `/Volumes/Jack-Dev/Projects/remoteorbit`
- **Expected canonical branch before refresh:** `main`

## Goal
Remove exactly five Task-031-audited merged-clean lifecycle objects and nothing else, preserving all dirty, forensic, UNKNOWN, and unlisted objects.

## Exact authorized objects

1. `/private/tmp/remoteorbit-dual-receiver-mic-debounce-corrective`
   - local branch `codex/dual-receiver-mic-debounce-corrective`
   - local HEAD `458e28d91b5ff748613bb88f5b89212d660279c7`
   - remote branch same name at same HEAD

2. `/private/tmp/remoteorbit-dual-receiver-momentary-routing-v1`
   - local branch `codex/dual-receiver-momentary-routing-v1`
   - local HEAD `c90edbf73ad9b0642fa344734571c0e806c0eb73`
   - remote branch same name at same HEAD

3. `/private/tmp/remoteorbit-dual-receiver-system-mapped-routing-v2`
   - local branch `codex/dual-receiver-system-mapped-routing-v2`
   - local HEAD `e1e6fe0bf76e245c4237978600b117b5b8e2a83e`
   - remote branch same name at same HEAD

4. `/private/tmp/remoteorbit-p0a-external-ime-observer`
   - local branch `codex/p0a-external-ime-observer-minimal`
   - local HEAD `2d6a89ea83a61c6b134db17f7330b5d0d8b89049`
   - remote branch same name at `fddcbb7dd2985967cf8d9741c229888d0c0a06c2`
   - both local and remote heads are already contained in accepted main

5. `/Volumes/Jack-Dev/Projects/remoteorbit-pr18-observer-corrective`
   - local branch `codex/persistent-long-boundary-probes-v1`
   - local HEAD `c18d080cf4b2a0c3515ca3b321bf7bb3c3bca2c5`
   - remote branch same name at same HEAD
   - PR #18 merged

## Mandatory per-object pre-delete gate
For each object independently, immediately before deletion verify:
- worktree still exists at the exact path and owns the exact local branch;
- worktree HEAD equals the expected local HEAD;
- `git status --porcelain -uall` is empty;
- local branch has zero commits not in current `origin/main`;
- local branch has zero unpushed commits relative to its live remote counterpart when a counterpart exists;
- live remote branch exists at the exact expected remote HEAD;
- both expected local and live remote heads are ancestors of current `origin/main`.

If any check fails, do not mutate that object. Report `SKIPPED_DUE_TO_DRIFT` and continue only with other independently passing manifest objects. Never force-delete.

## Authorized sequence for each PASS object
1. From canonical repo (not inside target worktree), remove worktree with `git worktree remove <path>` and no force.
2. Delete local branch with `git branch -d <branch>` only.
3. Re-fetch and recheck exact live remote HEAD and ancestry.
4. Delete exactly that remote branch with `git push origin --delete <branch>`.

After all attempted objects, `git worktree prune` is allowed only to remove stale registrations resulting from these authorized removals; do not use prune as a substitute for classification.

## Forbidden
Do not touch any other worktree/branch. In particular do not mutate the three dirty worktrees, four FORENSIC lineages, or any UNKNOWN row from Task 031. No reset/restore/clean/stash/rebase/merge/cherry-pick, no product/test edits, no build/install/restart, no runtime/settings/mapping/hardware actions.

## Completion evidence
Return per object PASS/SKIPPED, pre-delete evidence, deletion results, and final canonical state. Final state must be either:
- `BATCH1_CLEANUP_READY_FOR_WEB_CLOSEOUT` if all five removed successfully; or
- `BATCH1_PARTIAL_CLEANUP_READY_FOR_WEB_RECONCILIATION` if any object was skipped/failed without force.
