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

## Local reconciliation gate

After pulling the control files locally, the next agent must perform a read-only census before any product work:

1. read the three control files in order;
2. fetch remote state;
3. report local repository root;
4. report every registered worktree;
5. for each worktree report path, branch/detached state, exact HEAD, and clean/dirty state;
6. identify any worktree associated with PR #16, PR #9, or prior forensic/flight-recorder work;
7. inspect the installed/running RemoteOrbit identity only if runtime identity is relevant to the next task;
8. compare actual local state to `CURRENT_STATUS.md`;
9. write verified local facts into `CURRENT_STATUS.md`;
10. stop before cleanup or product changes.

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

Complete and review the remote control-plane files, then sync them locally and perform the **read-only local reconciliation gate**.

Do not resume RemoteOrbit product debugging before that gate is complete.
