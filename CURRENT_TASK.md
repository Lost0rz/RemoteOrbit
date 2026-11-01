# RemoteOrbit Current Task

## RO-PROJECT-CLOSEOUT-046 — Repository Closeout & Baseline

Status: `WORKTREE_CLEANUP_COMPLETE / LOCAL_BRANCH_RETIREMENT_AUTHORIZED`
TASK_CLASS: `REPOSITORY / WORKSPACE LIFECYCLE CLOSEOUT`
Repository: `Lost0rz/RemoteOrbit`

## Objective

Close the completed RemoteOrbit development cycle into one clear baseline without changing accepted product behavior.

## Completed

### Phase A — remote hygiene

- Open PR count: `0`.
- Remote branches: `main` only.

### Phase B — local worktree cleanup

Owner execution verified:

- pruned `7` stale/missing worktree registrations;
- removed `8` exact audited historical worktrees after exact HEAD + clean checks;
- final registered worktree count: `1`;
- remaining canonical worktree: `/Volumes/Jack-Dev/Projects/remoteorbit`;
- local branches intentionally preserved.

## Phase C — exact local branch retirement

### SAFE_DELETE_MERGED

Before deleting each branch below, verify its current tip is still an ancestor of current `origin/main`; delete with normal `git branch -d` only:

1. `codex/ci-self-hosted-runner-migration-20261031`
2. `codex/diagnostic-hardening-041`
3. `codex/ime-readiness-prompt-sync-043`
4. `codex/observability-039`
5. `codex/runtime-reliability-038-b-continuity-evidence`
6. `codex/shortcut-recorder-exclusive-capture-v1`
7. `codex/task045a-diagnostics-gating`
8. `codex/task045b-domain1-legacy-voice-product-surface`
9. `codex/task045b-domain2-legacy-voice-persisted-preferences`
10. `codex/task045b-domain3-persistent-voice-runtime-retirement`
11. `codex/task045b-domain4-dual-receiver-runtime-retirement`
12. `codex/task045b-domain5-legacy-generic-short-classifier-retirement`
13. `codex/task045b-domain6-local-microphone-capture-retirement`
14. `codex/task045d-domain1-remote-only-pcm-attribution-retirement`
15. `codex/task045d-domain2-p1a5-front-edge-experiment-retirement`
16. `codex/voice-pipeline-simplification-042`

### SAFE_DELETE_SUPERSEDED

These four local branches were previously audited as superseded historical lines whose required product intent was integrated or replaced by the accepted baseline. Re-check exact tip SHA before force-deleting only these branch refs:

1. `codex/brand-icon-unification-044` = `f245068219e2dfbacce62e1b385a30a79f015728`
2. `codex/ime-readiness-stability-043` = `4493657ae266072b95b159e539fa2e7fb6aa2a35`
3. `codex/mapping-config-simplify-040` = `c5f6c2f84c56b4e40780960bcd4173a1a4724731`
4. `codex/release-v0.2.15` = `f049e6eb7f0e5625b807fba1860d04c048b638ca`

No other branch deletion is authorized.

## Canonical normalization after branch retirement

After branch deletion succeeds:

1. `git remote set-url origin https://github.com/Lost0rz/RemoteOrbit.git`;
2. `git fetch origin --prune`;
3. verify canonical checkout is clean and on `main`;
4. `git merge --ff-only origin/main`;
5. verify local `HEAD == origin/main`;
6. verify exactly one local branch remains: `main`;
7. verify exactly one registered worktree remains;
8. verify only `origin/main` remains as a real remote-tracking branch.

## Stop conditions

Stop without deleting the affected branch if:

- a merged-class branch is no longer an ancestor of current `origin/main`;
- a superseded-class branch tip no longer matches its frozen SHA;
- canonical checkout is dirty;
- canonical branch is not `main`;
- `--ff-only` cannot advance local main;
- any unexpected local branch/worktree appears.

Do not reset, stash, clean, rebase, cherry-pick, or delete any unclassified work.

## Non-goals

- no product behavior changes;
- no tag/release;
- no driver/CoreAudio/TCC/default-device changes.

## Next

Owner executes the exact Phase C command and returns the final branch/worktree/remote state. Web then performs final closeout audit and decides whether Task 046 can be marked `CLOSED / CLEAN_BASELINE_ESTABLISHED`.
