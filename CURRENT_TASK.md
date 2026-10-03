# RemoteOrbit Current Task

## Task identity

- **Task:** PROJECT STATE BOOTSTRAP
- **Phase:** Remote authority establishment, then local reconciliation
- **Status:** ACTIVE
- **Task authority:** this file
- **Product development:** FROZEN

## Objective

Establish a durable, repository-backed project control plane before any further RemoteOrbit bug fixing, logging expansion, diagnostic instrumentation, or runtime experimentation.

The immediate goal is to make a fresh web or local AI session able to recover the project state from the repository instead of reconstructing it from chat history.

## Current authorization

### Allowed

- read-only Git/GitHub state audit;
- audit of existing branches and open/draft PRs;
- creation and correction of `AGENTS.md`, `CURRENT_STATUS.md`, and `CURRENT_TASK.md`;
- documentation-only review of project authority and workflow;
- local reconciliation after these files are synced;
- classification of existing local worktrees after local evidence is available.

### Forbidden

Until this task is closed:

- no product bug fixes;
- no production behavior changes;
- no new logging or telemetry;
- no diagnostic instrumentation changes;
- no new runtime experiments;
- no new speculative fix branches;
- no packaging, installation, driver, TCC, LaunchAgent, or CoreAudio changes;
- no release;
- no merge/close/delete of historical product PRs solely as cleanup;
- no deletion/pruning of local worktrees solely as cleanup;
- no reset/clean/stash/checkout that destroys or hides unresolved local evidence.

## Remote authority established in this phase

The governance work is carried by:

- Repository: `Lost0rz/RemoteOrbit`
- Base: `main`
- Governance PR: **#17**
- Governance branch: `codex/project-agents-control-plane-v1`

Product PRs #16 and #9 are not active implementation authority during this task. Their product work is frozen pending reconciliation.

## Required outputs

1. Root `AGENTS.md` containing durable rules.
2. Root `CURRENT_STATUS.md` containing the verified project snapshot.
3. Root `CURRENT_TASK.md` containing exactly one active task.
4. A remote audit that distinguishes remote-verifiable facts from local-only unknowns.
5. A local reconciliation pass after sync.

## Safe local sync gate

The three control files currently live on the governance branch, not on `main`.
Do not pull, merge, checkout, or reset an existing worktree merely to obtain these
files before its state has been inventoried.

On the machine that owns the RemoteOrbit repositories/worktrees:

1. locate an existing RemoteOrbit repository without mutating its current branch;
2. inspect `git remote -v` / `git remote get-url origin`;
3. verify that the remote you intend to use actually points to `Lost0rz/RemoteOrbit`;
   if `origin` points elsewhere, STOP and identify the correct remote instead of
   silently fetching from the wrong repository;
4. fetch only after remote identity is established, e.g. `git fetch origin` when
   `origin` is the verified RemoteOrbit remote;
5. verify that
   `origin/codex/project-agents-control-plane-v1` exists (or use the equivalent
   verified remote-tracking ref if the canonical remote is not named `origin`);
6. read the three control files directly from that verified remote-tracking branch, for
   example with:
   - `git show origin/codex/project-agents-control-plane-v1:AGENTS.md`
   - `git show origin/codex/project-agents-control-plane-v1:CURRENT_STATUS.md`
   - `git show origin/codex/project-agents-control-plane-v1:CURRENT_TASK.md`
7. only after reading them, perform the read-only worktree census below.

Do not create a new worktree, switch branches, merge PR #17, or overwrite local files
merely to read the control plane. A later explicit step can decide how these files
enter the authoritative local/main branch after reconciliation.

## Local reconciliation gate

After reading the remote control files, the next agent must perform a read-only census before any product work:

1. read the three control files in order;
2. fetch remote state;
3. report local repository root;
4. run `git worktree list --porcelain` and preserve its output as the worktree census;
5. report every registered worktree, including registered-but-missing entries;
6. for each worktree report path, branch/detached state, exact HEAD, and clean/dirty/untracked state;
7. identify any worktree associated with PR #16, PR #9, or prior forensic/flight-recorder work;
8. identify local-only commits and dirty/untracked evidence that must not be lost;
9. inspect the installed/running RemoteOrbit identity only if runtime identity is relevant to the next task;
10. compare actual local state to `CURRENT_STATUS.md`;
11. write verified local facts into `CURRENT_STATUS.md` only after deciding which branch/worktree is the control-plane update authority;
12. stop before cleanup or product changes.

If local evidence conflicts with the remote snapshot, the task remains ACTIVE and the conflict must be reconciled first.

## Completion gate

PROJECT STATE BOOTSTRAP is complete only when a fresh assistant, using the repository and current local evidence but no historical chat, can answer all of the following without guessing:

1. What is the remote default branch?
2. What exact remote-main commit was last verified?
3. Which task is currently active?
4. Which PR/branch is authorized for that task?
5. Which product PRs are frozen?
6. Which local worktree is authoritative, if one has been verified?
7. What exact local HEAD and dirty/clean state does that worktree have?
8. What release/build is the latest published release?
9. What app/build is actually installed/running, if that identity matters and has been verified?
10. Which statements are FACT, INFERENCE, HYPOTHESIS, and UNKNOWN?
11. What is the next permitted action?
12. What actions are explicitly forbidden?

## Next authorized step

Fetch the governance branch locally **without switching/resetting existing worktrees**,
read the three control files from the remote-tracking branch, then perform the
**read-only local reconciliation gate**.

Do not resume RemoteOrbit product debugging before that gate is complete.
