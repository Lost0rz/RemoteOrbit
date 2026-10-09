# RemoteOrbit Current Task

## Current task — BROADER LIFECYCLE INVENTORY

- **Status:** ACTIVE / READ ONLY
- **Task ID:** `RO-LIFECYCLE-INVENTORY-031`
- **Control parent:** `3c4dc85357b0dcca373c85dc2a946a4abe111765`
- **Canonical path:** `/Volumes/Jack-Dev/Projects/remoteorbit`
- **Expected canonical branch:** `main`
- **Expected canonical HEAD before local refresh:** `3c4dc85357b0dcca373c85dc2a946a4abe111765`

## Goal
Produce a complete evidence-backed lifecycle matrix for all remaining RemoteOrbit worktrees and `codex/*` branches before any deletion.

## Classification vocabulary
Use only:
- `ACTIVE` — explicitly current authorized work. Existing age/name alone cannot make an item active.
- `MERGED` — work is fully contained in accepted `main` and has no unique dirty/unpushed work requiring preservation.
- `SUPERSEDED` — not fully merged as-is, but a later accepted line replaced the intent; unique content, if any, must be identified before deletion.
- `ABANDONED` — no current authority and no accepted need to continue; unique work status must still be explicit before deletion.
- `FORENSIC` — intentionally retained evidence or artifact; preserve unless separately authorized.
- `UNKNOWN` — insufficient evidence. Never delete an UNKNOWN item.

## Required inventory
For every registered worktree report path, branch/detached state, HEAD, clean/dirty/untracked state, tracking remote, ahead/behind, whether HEAD is contained in `origin/main`, unique local commits not in main, and provisional lifecycle class with evidence.

For every local branch report HEAD, worktree ownership if any, upstream, ahead/behind, containment in main, unpushed commits, associated remote branch if any, associated PR if identifiable, and provisional class.

For every live remote `codex/*` branch report live HEAD, containment in current main, commits unique to that branch, associated PR state/merge state if identifiable, matching local branch/worktree if any, and provisional class.

Also identify duplicates where multiple branches/worktrees point to the same HEAD or belong to the same superseded diagnostic lineage.

## Safety boundary
This task authorizes no lifecycle deletion or mutation. Do not run worktree remove/prune, branch -d/-D, push --delete, reset, restore, clean, stash, rebase, merge, cherry-pick, build/install/restart, or hardware actions.

A normal `git fetch origin` for freshness is allowed; do not use destructive local cleanup. Evidence files may be written only under `/private/tmp`.

## Completion output
Return counts and a per-item matrix, then summaries:
- `ACTIVE`
- `MERGED_CLEAN_DELETE_CANDIDATE`
- `SUPERSEDED_NEEDS_PRESERVATION_CHECK`
- `ABANDONED_NEEDS_PRESERVATION_CHECK`
- `FORENSIC_RETAIN`
- `UNKNOWN_STOP`

No deletion is authorized even for delete candidates. Final state must be `LIFECYCLE_INVENTORY_READY_FOR_WEB_AUDIT`.
