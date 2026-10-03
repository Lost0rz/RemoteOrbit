# RemoteOrbit Current Task

## Task identity

- **Task:** REPOSITORY CLOSEOUT
- **Phase:** remote branch deletion complete; repository closeout complete
- **Status:** COMPLETE
- **Task authority:** this file
- **Product development:** FROZEN

## User authorization

The user explicitly authorized this closeout phase on 2026-10-03:

- list every worktree and PR;
- classify each as ACTIVE, MERGED, SUPERSEDED, or ABANDONED;
- delete what is safe to delete;
- record the reason/blocker for everything retained.

After the local census and candidate classification were recorded, the user gave
final confirmation to delete exactly the 14 named remote refs individually, with a
fresh SHA check before each deletion and an immediate `ls-remote` verification.

This authorization does not waive evidence-preservation rules.

## Lifecycle vocabulary

- **ACTIVE** — the single line currently authorized to change project state.
- **MERGED** — accepted into `main` by a verified merged PR.
- **SUPERSEDED** — not merged itself, but a later accepted line replaced or
  incorporated its purpose.
- **ABANDONED** — intentionally not proceeding and not accepted into main.

Branch/worktree cleanup additionally uses **KEEP** and **DELETE CANDIDATE**.

## Allowed

- read-only Git/GitHub/worktree census;
- classify all PRs, remote branches, and local worktrees;
- add closeout comments to obsolete PRs;
- close unmerged PRs proven SUPERSEDED or ABANDONED;
- delete remote branches proven safe when a real ref-deletion capability is
  available;
- remove local worktrees proven safe only after local census confirms exact HEAD,
  branch/detached state, dirty/untracked state, and local-only commits;
- delete corresponding local branches after their worktrees/evidence are preserved;
- update the three control files.

## Forbidden

- no product bug fixes;
- no new logging, telemetry, probes, or diagnostics;
- no speculative runtime experiments;
- no merge of product PRs as a cleanup shortcut;
- no force push, destructive reset, clean, history rewrite, or evidence-destroying
  stash/checkout;
- no deletion of a branch/worktree containing unique unresolved evidence unless that
  evidence is first preserved elsewhere;
- no package/install/release/TCC/HAL/LaunchAgent/CoreAudio mutation.

## Remote closeout target

The current remote classifications to verify are:

- #17 — **ACTIVE** control-plane line.
- #9 — **SUPERSEDED** by merged #10 and P1 closure #12.
- #16 — **ABANDONED**; later forensic work restarted from current main.
- merged PRs — **MERGED**.
- #4/#5/#6 — **SUPERSEDED** by the accepted #7 corrective.

Every classification must be verified from GitHub evidence before mutation.

## Local worktree gate

GitHub cannot enumerate local worktrees. Before deleting any local worktree, the
owning Mac must run:

```bash
git worktree list --porcelain
```

For every worktree record:

```text
PATH
BRANCH_OR_DETACHED
HEAD
CLEAN_DIRTY_UNTRACKED
REMOTE_TRACKING
ASSOCIATED_PR_IF_ANY
LOCAL_ONLY_COMMITS
CLASSIFICATION: ACTIVE / MERGED / SUPERSEDED / ABANDONED
DELETE: YES / NO
DELETE_BLOCKER
```

Also identify registered-but-missing worktrees. Do not prune/remove/reset/clean/stash
during the census.

## Completion gate

Closeout is complete only when:

1. every PR has one lifecycle classification;
2. every remote branch has KEEP / DELETE CANDIDATE / DELETED plus a reason;
3. obsolete unmerged PRs are closed with preserved history;
4. every local worktree has one lifecycle classification;
5. safe local worktrees and corresponding local branches are removed;
6. all retained lines have an explicit evidence/authority blocker;
7. exactly one ACTIVE control task/PR remains; at most one ACTIVE product-evidence
   worktree may be retained, but it is frozen for mutation until closeout ends;
8. CURRENT_STATUS records the final state.

## Remote progress

- all 17 PRs classified; #9 and #16 closed under the authorized closeout; #17 remains OPEN Draft;
- all 18 remote branches classified; the 14 authorized candidates were individually deleted and post-verified; exactly four KEEP refs remain;
- the owning-Mac census began with 13 live worktrees and 10 registered-but-missing entries;
- four safe live worktrees were removed, all ten verified-missing registrations were pruned, and 15 safe local branches were deleted;
- nine original worktrees remain, including one ACTIVE frozen Flight Recorder evidence worktree; one new ACTIVE control-plane worktree was created;
- the first delete attempt for `codex/voice-recovery-from-good` hit a transient TLS transport error; its unchanged approved SHA was rechecked and a single retry succeeded;
- final live remote inventory was exactly `main`, `codex/project-agents-control-plane-v1`, `codex/persistent-duplicate-audio-forensics`, and `codex/voice-single-owner-session`;
- the final closeout snapshot correction was audited against control HEAD `8a09a80411fd3f19c37332a4d2e7799773cf5182`; both control files are committed together as its direct child and pushed by fast-forward.

## Completion result

All eight completion criteria above pass. PR #17 remains OPEN + Draft and unmerged as
the sole control-plane review artifact. The 14 deletions had no unresolved failures;
the final remote branch count is four. The 10 retained live worktrees and zero
registered-but-missing paths are recorded in `CURRENT_STATUS.md`.

No next task is authorized. Product development remains FROZEN; stop after this
repository closeout and do not resume product debugging under this task.
