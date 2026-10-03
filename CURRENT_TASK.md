# RemoteOrbit Current Task

## Task identity

- **Task:** CONTROL-PLANE QUALITY AUDIT
- **Phase:** remote quality freeze, then local read-only reconciliation
- **Status:** ACTIVE
- **Task authority:** this file
- **Product development:** FROZEN
- **Further repository cleanup:** FROZEN

## Objective

Independently audit the quality, consistency, safety, and cold-start usability of
`AGENTS.md`, `CURRENT_STATUS.md`, and `CURRENT_TASK.md`.

Do not declare the control plane ready merely because the files exist. Correct every
material defect found, then restart the consecutive-PASS count from zero.

## Current remote facts carried into this audit

- The control-plane authority is branch `codex/project-agents-control-plane-v1`.
- PR #17 is currently CLOSED Draft/unmerged; closing the PR did not change the branch task authority.
- PR #9 is currently OPEN Draft but its lifecycle classification remains SUPERSEDED.
- PR #16 is currently OPEN Draft but its lifecycle classification remains ABANDONED.
- #9 and #16 were closed during repository closeout and then reopened out-of-band;
  #17 was closed out-of-band. These PR metadata changes are drift facts, not
  authorization for additional cleanup or a task transition.
- Local worktree state remains UNKNOWN until a local census is performed.

## Allowed

- read-only Git/GitHub/PR/branch/release audits;
- verify existing lifecycle classifications against PR and commit evidence;
- inspect the complete diff of PR #17;
- cold-start and failure-injection reasoning against the three control files;
- documentation-only corrections to the three control files;
- inspect PR metadata for parity with CURRENT_STATUS; do not mutate PR state during this audit.

## Forbidden during this audit

- no product code changes;
- no logging, telemetry, probes, or diagnostic changes;
- no runtime experiments;
- no PR close/reopen/merge operations;
- no branch deletion;
- no local worktree delete/prune/remove;
- no reset, clean, destructive stash/checkout, force push, or history rewrite;
- no build/package/install/release/TCC/HAL/LaunchAgent/CoreAudio mutation;
- no transition to another task merely because it appears to be the next logical step.

## Audit protocol

A material corrective edit resets the consecutive-PASS count to **0**.

A detected concurrent write to the control-plane branch also resets the count to
**0** and requires all three files to be re-read before auditing continues.

After the final corrective edit, require at least **three consecutive independent
PASS rounds with no control-file mutation between them**. Across those rounds the
following gates must all be covered:

1. **Role/structure gate**
   - AGENTS contains only durable rules.
   - CURRENT_STATUS contains mutable facts and explicit UNKNOWN/HISTORICAL state.
   - CURRENT_TASK contains exactly one active task and its allowed/forbidden scope.

2. **Live factual parity gate**
   - remote default branch and main HEAD;
   - open/closed PR set, relevant head SHAs, and out-of-band PR metadata drift;
   - merged/unmerged lifecycle claims;
   - latest release/version/build;
   - branch inventory and unique-commit claims;
   - no remote-only claim presented as local runtime/worktree fact.

3. **Transition/concurrency gate**
   - task-phase transition requires explicit authority;
   - CURRENT_STATUS and CURRENT_TASK transition atomically in one commit;
   - branch-HEAD drift aborts publication;
   - status/task disagreement stops state-changing work.

4. **Cold-start/failure-injection gate**
   - wrong remote;
   - dirty worktree;
   - detached HEAD;
   - registered-but-missing worktree;
   - local-only commits/untracked evidence;
   - stale PR/branch;
   - concurrent control-plane writer;
   - installed/running build not remotely verifiable.

5. **Diff/scope gate**
   - PR #17 changes only governance documents;
   - no product/runtime/package/driver/config behavior is changed;
   - PR remains cleanly based on current main or any drift is explicitly reconciled.

## Safe local read/sync gate after remote audit passes

The control files currently live on the governance branch until PR #17 is merged.
Do not checkout/reset an existing worktree merely to read them.

On the owning Mac:

1. locate an existing RemoteOrbit repository without switching its branch;
2. inspect remotes and verify the canonical remote points to `Lost0rz/RemoteOrbit`;
3. fetch only after remote identity is established;
4. read the three files directly from the verified remote-tracking governance ref,
   e.g. with `git show <remote>/codex/project-agents-control-plane-v1:AGENTS.md`;
5. run `git worktree list --porcelain`;
6. preserve and classify every registered worktree, including missing entries,
   detached HEADs, dirty/untracked files, and local-only commits;
7. stop before cleanup or product work.

## Completion gate

This task is complete only when:

1. the latest control-plane HEAD has received **three consecutive independent PASS
   audit rounds** with no material issue and no intervening control-file mutation;
2. the live GitHub facts still match CURRENT_STATUS;
3. CURRENT_STATUS and CURRENT_TASK agree on phase and authority;
4. the control-plane branch diff relative to main remains governance-only;
5. no unresolved remote control-plane defect remains;
6. local-only state is still explicitly UNKNOWN rather than guessed.

Passing this remote audit does **not** complete local reconciliation and does not
authorize product debugging or cleanup.

## Next authorized step

Run the required consecutive remote audit rounds.

After they pass, report the remote control plane as ready for local read-only
reconciliation. Do not advance to another task automatically.
