# RemoteOrbit Current Task

## RO-DOMAIN-DOC-AUDIT-047 — Domain Map & Documentation Authority Refresh

Status: `ACTIVE / DOCUMENTATION_AUTHORITY_REFRESH`
TASK_CLASS: `REPOSITORY DOCUMENTATION / DOMAIN NAVIGATION AUDIT`
Repository: `Lost0rz/RemoteOrbit`
Control parent: `c614b683e3fe58c423f89be3503dbe0c78aa02e9`

## Objective

Rebuild RemoteOrbit's semantic navigation from the current `main` baseline, then reconcile durable and historical documentation so repository docs accurately describe the current product contract, architecture, ownership, and supported workflows after Task 046 closeout.

## Authorized scope

1. Audit the full repository tree and current source/test structure needed to establish Domain/capability ownership and runtime/test routes.
2. Find the current Domain Map or equivalent navigation projection and refresh/rebuild it from verified evidence.
3. Audit README, setup documents, design/plan/history documents, ADR-like notes, diagnostic documents, and documentation indexes for:
   - stale current-state claims;
   - superseded Persistent/dual-receiver or other retired business/product semantics;
   - references to retired branches/worktrees/PRs/tasks as if they were current authority;
   - duplicated or conflicting architecture/ownership statements;
   - broken or obsolete navigation/links;
   - historical material that should be clearly retained as history instead of active guidance.
4. Update authoritative documents where current guidance is still needed.
5. Delete documentation that is obsolete, misleading, redundant, or superseded and has no remaining historical/evidence value.
6. Update control files at completion with the resulting documentation authority and remaining uncertainties.

## Non-goals / prohibited side effects

- No Swift/product behavior change.
- No test behavior change except documentation references to tests.
- No app/driver packaging, install, runtime, CoreAudio, TCC, LaunchAgent, or default-device mutation.
- No release/tag operation.
- No branch/worktree/PR lifecycle cleanup or creation unless task authority is explicitly reconciled first.
- Do not rewrite historical evidence solely to make old conclusions look current; preserve useful history with explicit historical labeling when warranted.

## Evidence and decision rules

- Current source and current tests verify navigation claims; search/index results are leads only.
- `AGENTS.md` remains durable normative authority; `CURRENT_STATUS.md` and this file remain the only mutable control-plane authorities.
- A Domain Map is a derived navigation projection, not business/product authority.
- Documents that encode an accepted durable product contract may be updated only to align with current accepted authority, not to invent new behavior.
- When deletion vs retention is ambiguous, retain only if the document has unique historical/evidence value and clearly mark it non-authoritative/historical.

## Completion gate

Task 047 can close only when all are true:

- current repository/document inventory has been audited;
- Domain Map/navigation projection reflects current Domain/capability → source/runtime/test routes;
- stale active guidance has been updated or removed;
- superseded business/design documents are deleted or explicitly demoted to historical reference;
- README/setup/index links are coherent after cleanup;
- final documentation mutations are remotely delivered and verified on `main`;
- `CURRENT_STATUS.md` and `CURRENT_TASK.md` are reconciled in one final control transition commit.
