# RemoteOrbit Current Task

## Task identity

- **Task:** REPOSITORY CLOSEOUT
- **Phase:** PR / branch classification, then local worktree reconciliation
- **Status:** ACTIVE
- **Task authority:** this file
- **Product development:** FROZEN

## Objective

Close the accumulated RemoteOrbit development lines before any further debugging.

Every PR and candidate cleanup branch must be classified from evidence. Every local
worktree must be inventoried locally before it is removed.

## Classification vocabulary

Use exactly these lifecycle labels for PRs and worktrees:

- **ACTIVE** — the single line currently authorized to change project state.
- **MERGED** — accepted into `main` by a verified merged PR.
- **SUPERSEDED** — not merged itself, but a later accepted line explicitly replaced
  or incorporated its purpose.
- **ABANDONED** — intentionally not proceeding; no accepted successor needs this
  line as implementation authority.

Branch cleanup may additionally record **KEEP** or **DELETE CANDIDATE**. That is a
cleanup decision, not a fifth lifecycle state.

## Current authorization

### Allowed

- read-only Git/GitHub/worktree census;
- classify all PRs, branches, and locally registered worktrees;
- add closure comments to obsolete PRs;
- close PRs proven SUPERSEDED or ABANDONED;
- delete remote/local branches proven safe **only when the available tool can do so
  without rewriting or destroying unique unresolved evidence**;
- remove local worktrees proven safe after local read-only census confirms their
  branch/HEAD/dirty/untracked state;
- update `AGENTS.md`, `CURRENT_STATUS.md`, and `CURRENT_TASK.md`.

### Forbidden

- no product bug fixes;
- no new logging, telemetry, or diagnostics;
- no speculative runtime experiments;
- no merge of product PRs as a cleanup shortcut;
- no force push, destructive reset, clean, or history rewrite;
- no deletion of a local worktree before its exact state is inventoried;
- no deletion of a branch that is the only verified reference to unique unresolved
  evidence unless that evidence is preserved elsewhere first;
- no package/install/release/TCC/HAL/LaunchAgent/CoreAudio mutation.

## Remote closeout decisions

- PR #17: **ACTIVE** — control-plane / closeout authority.
- PR #9: **SUPERSEDED** — its P0 audio-data-plane purpose was carried forward by
  merged PR #10 and the P1 stage was closed by merged PR #12.
- PR #16: **ABANDONED** — it was not merged; later persistent-audio forensics
  restarted from `main` rather than stacking this speculative production fix.
- All GitHub PRs whose `merged_at` is non-null: **MERGED**.
- Closed-unmerged PRs #4/#5/#6: **SUPERSEDED** by merged PR #7, whose description
  explicitly consolidates the accepted v0.2.11 corrective and excludes the
  superseded alternatives/diagnostic-only line.

## Local worktree gate

GitHub cannot enumerate local Git worktrees. Therefore remote closeout is not allowed
to claim that all worktrees are closed.

On the machine that owns RemoteOrbit repositories, first verify the canonical remote,
fetch it, then run a read-only census:

```bash
git worktree list --porcelain
```

For every registered worktree record:

```text
PATH
BRANCH_OR_DETACHED
HEAD
CLEAN_DIRTY_UNTRACKED
REMOTE_TRACKING
ASSOCIATED_PR_IF_ANY
CLASSIFICATION: ACTIVE / MERGED / SUPERSEDED / ABANDONED
DELETE: YES / NO
DELETE_BLOCKER
```

Also identify registered-but-missing worktrees and local-only commits. Do not prune,
remove, reset, clean, stash, or checkout during the census.

## Completion gate

Repository closeout is complete only when:

1. every PR has one lifecycle classification;
2. obsolete open PRs are closed with a reason;
3. every remote branch has a keep/delete decision and blocker when retained;
4. every local worktree has one lifecycle classification;
5. safe local worktrees/branches are removed;
6. retained worktrees/branches have an explicit reason;
7. exactly one ACTIVE line remains;
8. two consecutive closeout audits find no new material state issue.

## Next authorized step

Finish the remote PR/branch closeout, then run the local read-only worktree census.
Do not resume product debugging.
