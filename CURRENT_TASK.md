# RemoteOrbit Current Task

## RO-PROJECT-CLOSEOUT-046 — Repository Closeout & Baseline

Status: `REMOTE_PR_HYGIENE / ACTIVE`
TASK_CLASS: `REPOSITORY / WORKSPACE LIFECYCLE CLOSEOUT`
Repository: `Lost0rz/RemoteOrbit`

## Objective

Close the completed RemoteOrbit development cycle into one clear baseline without changing accepted product behavior.

Owner-authorized outcome:

1. close stale remote PRs after evidence-based classification;
2. clean stale local worktrees after inventory and merged/superseded checks;
3. leave one clear canonical baseline;
4. preserve unique/unmerged work unless its lifecycle is explicitly decided.

## Phase A — remote PR hygiene

Inventory all currently open PRs and classify each as one of:

- `MERGED/EQUIVALENT` — intent already present in current main;
- `SUPERSEDED/HISTORICAL` — old work must not be merged into current main;
- `ACTIVE/RETAIN` — still contains intentional unmerged work that should remain available;
- `UNKNOWN` — insufficient evidence; do not mutate.

Authorized Phase A side effects:

- close PRs classified `SUPERSEDED/HISTORICAL`;
- optionally leave a concise closeout comment recording why they were closed;
- keep `ACTIVE/RETAIN` and `UNKNOWN` PRs open;
- update CURRENT_STATUS + CURRENT_TASK atomically after the remote inventory/closure result.

Not authorized in Phase A:

- merge any stale PR;
- delete remote branches;
- rewrite history;
- product source/runtime changes;
- tag/release.

### Starting inventory

Fresh remote evidence found exactly three open Draft PRs:

- #25 `Release RemoteOrbit v0.2.15` — historical/diverged release/soak candidate;
- #26 `fix: deterministic mapping entry and observable recordings` — historical/diverged Settings corrective;
- #28 `ui: unify RemoteOrbit app, settings, and menu bar iconography` — separate branding/icon work requiring an independent lifecycle decision.

PR #25 and #26 are authorized for closure once their live identities remain unchanged at mutation time. PR #28 must receive an explicit lifecycle classification from current evidence before any close/merge action.

## Next phases

After Phase A is recorded complete:

- Phase B: local worktree / checkout inventory and retirement;
- Phase C: canonical baseline reconciliation, stale docs/branches classification, and final repository closeout receipt.

Each phase must preserve unique work and distinguish worktree retirement from branch/history retirement.
