# RemoteOrbit Current Task

## Task identity

- **Task:** REPOSITORY CLOSEOUT
- **Phase:** local worktree closeout complete; remote branch deletion pending final user confirmation
- **Status:** ACTIVE
- **Task authority:** this file
- **Product development:** FROZEN

## User authorization

The user explicitly authorized this closeout phase on 2026-10-03:

- list every worktree and PR;
- classify each as ACTIVE, MERGED, SUPERSEDED, or ABANDONED;
- delete what is safe to delete;
- record the reason/blocker for everything retained.

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
- all 18 remote branches classified; 14 are DELETE CANDIDATE and four are KEEP;
- the owning-Mac census began with 13 live worktrees and 10 registered-but-missing entries;
- four safe live worktrees were removed, all ten verified-missing registrations were pruned, and 15 safe local branches were deleted;
- nine original worktrees remain, including one ACTIVE frozen Flight Recorder evidence worktree; one new ACTIVE control-plane worktree was created;
- remote deletion awaits final confirmation of the 14 exact candidate branch refs; no remote refs have been deleted;
- control files are updated on a direct child of the freshly verified live control branch HEAD.

## Next authorized step

Request the user's final confirmation to delete exactly these refs, individually and with post-delete verification:

- codex/audio-data-plane-p0-audit
- codex/configurable-voice-trigger-key
- codex/media-key-suppression-isolation
- codex/mic-disabled-bypass-short-classifier
- codex/p1-a6-long-duration-telemetry
- codex/p1-stage-merge-closure
- codex/persistent-segment-transaction-isolation
- codex/release-v0.2.13
- codex/v0211-disabled-short-classifier
- codex/v0211-option-race-audit
- codex/voice-recovery-from-good
- codex/voice-single-owner-option
- fix/v0211-final-voice-corrective
- release/v0.2.12

On confirmation, reverify the live heads, delete one ref at a time with git push origin --delete <branch>, and verify that git ls-remote --heads origin <branch> is empty after each deletion. If any ref is absent, has changed lifecycle, or Git rejects deletion, stop that branch and reclassify. Then update CURRENT_STATUS.md and CURRENT_TASK.md in one fast-forward commit. Do not resume product debugging until repository closeout is complete.
