# RemoteOrbit Current Task

## RO-REPOSITORY-LIFECYCLE-CLOSEOUT-036 — Gate A

- **Status:** ACTIVE — GATE A READ-ONLY INVENTORY
- **Repository:** `Lost0rz/RemoteOrbit`
- **Canonical path:** `/Volumes/Jack-Dev/Projects/remoteorbit`
- **Canonical branch:** `main`
- **Gate 0 live remote baseline:** `e754895731f4ab64e9e0307b5b60f4edd728e187`
- **Control transition:** this paired status/task update must be one commit, a direct child of the Gate 0 baseline, pushed to `main`; record its resulting SHA as `GATE_A_CONTROL_HEAD` in Gate A evidence.

## Prior task
Task 035 (`RO-RUNTIME-BASELINE-RELEASE-035`) remains CLOSED / v0.2.14 accepted and published. Its retained publication worktree at `/private/tmp/remoteorbit-v0.2.14-publish` must be inspected, not presumed obsolete.

## Goal
Establish one canonical development repository/worktree, identify all RemoteOrbit-related source copies and artifacts in the specified search areas, and establish whether any unique uncommitted work or local-only commits may be at risk. Gate A must not conclude that unique work is disposable.

## Authorized Gate A actions
- Read repository state and inspect refs, worktrees, status, and history.
- Fetch `origin` without pruning; inspect live remote refs and GitHub PR metadata if access works.
- Search the specified filesystem roots without following symlinks recursively; inspect candidate metadata and hash discrete manifests/artifacts where practical.
- Write inventory evidence outside the repository.
- Commit and push only `CURRENT_STATUS.md` and `CURRENT_TASK.md` for this authorized control-plane transition.

## Explicitly prohibited
- `rm`, `rmdir`, `git clean`, `git reset`, `git stash`, `git worktree remove`, or `git worktree prune`.
- Local or remote branch deletion; tag deletion or modification.
- Checking out historical branches; merge/rebase/cherry-pick other than the explicitly permitted clean Gate 0 fast-forward to `origin/main`.
- Moving or archiving folders.
- Modifying product, test, runtime, or packaging code.
- Gate B classification decisions or any cleanup.
- Creating a worktree for this task.

## Gate A1 — registered Git inventory
From the canonical repository collect:
`git worktree list --porcelain`, `git branch -vv`, `git for-each-ref refs/heads`, `git for-each-ref refs/remotes`, local tags, `git remote -v`, `git ls-remote --heads origin`, and `git ls-remote --tags origin`. Do not prune. Explicitly inspect `/private/tmp/remoteorbit-v0.2.14-publish`.

For each registered worktree record absolute path and realpath, branch/detached state, exact HEAD, git-dir, clean/dirty state and staged/unstaged/untracked paths, path existence and `.git` pointer validity, canonical status, whether `GATE_A_CONTROL_HEAD` exists in its object database, and commit relationship to that control head when determinable.

## Gate A2–A4 — filesystem, Git, and artifact candidates
Search these roots: `/Volumes/Jack-Dev`, `/private/tmp`, `/tmp`, `~/.codex/worktrees`, `~/Documents`, and `~/Applications`. Do not follow symlinks recursively. Search case-insensitively for `RemoteOrbit`, `remoteorbit`, `remote-orbit`, and `remote_orbit`; discover Git metadata independently (`.git` directories/files and worktree gitdir pointers). Focus on candidate source trees under `/Volumes/Jack-Dev/Projects`, including `RemoteOrbit-app-archives`, `remoteorbit-audio-p0`, `remoteorbit-audio-p1-a3`, `remoteorbit-audio-p1-a4`, `remoteorbit-audio-p1-a5`, `remoteorbit-diagnostic-backups`, `RemoteOrbit-flight-recorder`, `remoteorbit-p0-voice-experiment`, and `remoteorbit-voice-p0-final`. Names alone do not establish disposition.

For each candidate Git repository/worktree record absolute/real path, repository top-level, git-dir and common git-dir where applicable, origin URL and all remotes, branch/detached state, exact HEAD and commit subject/date, porcelain-v2 working state with staged/unstaged/untracked path lists, local branches/upstreams, remote-tracking refs, visible tags, and relation to `GATE_A_CONTROL_HEAD`. If the control object exists, determine equality, ancestry, divergence, ahead/behind counts, and candidate-only commits (full list in evidence). Do not fetch in historical repositories. If the control object is absent, record `CONTROL_OBJECT_PRESENT=NO` and relation UNKNOWN for Gate B.

For non-Git candidate folders/files record absolute/real path, object type (directory/file/symlink/app/dmg/archive/evidence/unknown), apparent size, practical file count, latest modification time, presence of `*.swift`, `Package.swift`, `*.xcodeproj`, `*.xcworkspace`, `*.json`, `*.jsonl`, `*.log`, `*.app`, `*.dmg`, `*.pkg`, and `*.zip`. Identify only; do not declare obsolete. Avoid hashing huge trees; hash discrete manifests or artifacts only when useful.

## Gate A5 — unique-work risk
Explicitly enumerate:
- `UNCOMMITTED_WORK_CANDIDATES`
- `LOCAL_ONLY_COMMIT_CANDIDATES`
- `DETACHED_HEAD_CANDIDATES`
- `UNKNOWN_HISTORY_CANDIDATES`

Preserve all unresolved or unique work. Do not infer disposability.

## Gate A6 — remote lifecycle
Record live remote branch and tag inventories, open PR count if available, and relevant closed/merged PR metadata when readily available. Do not mutate remote state or delete historical `codex/*` branches.

## Evidence and completion
Write outside the repository to `/private/tmp/remoteorbit-lifecycle-closeout-036-gatea-YYYYMMDDTHHMMSS`. Include:
`00-control.txt`, `01-worktrees.txt`, `02-local-branches.txt`, `03-remote-branches.txt`, `04-tags.txt`, `05-filesystem-candidates.tsv`, `06-git-candidates.tsv`, `07-nongit-artifacts.tsv`, `08-unique-work-risk.txt`, `09-scan-errors.txt`, `GATE_A_INVENTORY.md`, and `SHA256SUMS.txt`. Hash the evidence outputs. Do not archive/delete evidence.

Record permission and scan errors. If an important candidate cannot be inspected, set `INVENTORY_COMPLETE=NO` and do not proceed to Gate B.

At the end, recheck live `origin/main` and record `GATE_A_START_CONTROL_HEAD`, `GATE_A_FINAL_LOCAL_HEAD`, `LIVE_ORIGIN_MAIN`, and `LIVE_REMOTE_MAIN`. If main changes during the scan, set `CONTROL_HEAD_DRIFT_DURING_SCAN=YES` and stop with `FINAL_STATE=STOP_CONTROL_HEAD_DRIFT`.

## Stop conditions and handoff
Stop before scanning if the Gate 0 repository identity, expected remote baseline, clean canonical main, or control-transition parent/push verification fails. Preserve evidence and report the exact blocker. Do not continue after control-head drift.

On complete inventory, stop at `WAITING_FOR_WEB_GATE_A_AUDIT`. Do not recommend deletion, perform Gate B, or clean up. The final report must include the machine-readable fields and candidate/risk tables required by the initiating task.

The final response starts with `RO_REPOSITORY_LIFECYCLE_CLOSEOUT_036_GATE_A` and reports: task transition result, control parent, control head, live remote main, control-head drift, canonical path/branch/HEAD/cleanliness, registered and noncanonical worktree counts, filesystem/Git/non-Git candidate counts, remote branch and non-main branch counts, open PR count, each unique-work risk count, important uninspected path count, inventory completeness, evidence directory and manifest SHA-256, mutations (`control-plane transition only`), cleanup (`NO`), and final state. Then include complete registered-worktree, Git-candidate, non-Git artifact-group, unique-work-risk, remote-branch, scan-error/inaccessible-path tables, and evidence-file hashes.
