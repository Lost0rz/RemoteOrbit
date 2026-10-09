# RemoteOrbit Current Task

## RO-REPOSITORY-LIFECYCLE-CLOSEOUT-036 — Gate B

- Status: ACTIVE — GATE B LIFECYCLE CLASSIFICATION
- Repository: Lost0rz/RemoteOrbit
- Canonical path: /Volumes/Jack-Dev/Projects/remoteorbit
- Canonical branch: main
- Gate A Web audit: PASS, as stated by the current Gate B task handoff.
- Gate B expected parent/current head at transition start: 7dbd7b39e6e643d5a317d69776b9e2d81006ef83.
- The Gate B control transition is a paired status/task commit directly parented by that SHA. Record its resulting SHA as GATE_B_CONTROL_HEAD in the external Gate B evidence.
- Gate 0 passed: after fetching origin, local HEAD, origin/main, and live remote main all equaled the expected head; branch main; canonical worktree clean.

## Objective
Classify every candidate identified in Gate A, resolve unique-history and dirty-work preservation requirements, perform the named read-only special inspections, and produce an exact ordered Gate C preservation/cleanup manifest. Gate B performs no cleanup.

## Authorized actions
- Read-only Git/ref/history/status/diff inspection and read-only filesystem inspection.
- Compare candidate commits, files, diffs, and artifact metadata/content where explicitly required below.
- Classify lifecycle state and design preservation.
- Write the Gate B report and supporting evidence outside the repository.
- The paired CURRENT_STATUS.md and CURRENT_TASK.md transition commit and its fast-forward push to origin/main, directly after the verified parent, are authorized.

## Not authorized in Gate B
- rm/rmdir, git clean/reset/stash, git worktree remove/prune, branch/tag/remote deletion.
- Moving or copying files, archiving, creating Git bundles, preservation patches, or preservation copies.
- Product, test, runtime, packaging, AGENTS.md, or other repository changes.
- Any Gate C action. Do not execute the Gate C manifest.

## B1 — all 14 Git candidates
Use only these classes: CANONICAL_RETAIN, SAFE_LOCAL_RETIRE, PRESERVE_THEN_RETIRE, NEEDS_RECONCILIATION. Treat the Gate A suggested classes as hypotheses. For each candidate report path, class, HEAD, branch/detached state, dirty state, unique local commits, remote backing ref, release-tag backing, reason, and preservation requirement. No dirty worktree may be SAFE_LOCAL_RETIRE. Keep unresolved ownership/history as NEEDS_RECONCILIATION.

## B2 — 12 candidate-only commits
For every unique commit, identify exact local refs that keep it reachable, whether it is on any live remote ref, whether another local branch also represents it, and whether it must be in the pre-cleanup history snapshot. Produce LOCAL_UNIQUE_COMMIT_PRESERVATION_TABLE with COMMIT, SUBJECT, CURRENT_REF, REMOTE_REF_PRESENT, PRESERVE_IN_HISTORY_BUNDLE, WHY. Default to preservation YES unless redundancy is proved. Do not infer an experiment is worthless because it was not merged.

## B3 — three dirty worktrees
Resolve an exact Gate C recipe for each of:
- remoteorbit-audio-p1-a5: untracked P1A5Observer/Info.plist, build.sh, main.swift.
- remoteorbit-p0-voice-experiment: eight tracked modifications and three untracked source/test files per Gate A evidence.
- remoteorbit-voice-p0-final: eight tracked modifications and three untracked source/test files per Gate A evidence.
Recipe design should include BASE_HEAD.txt, STATUS.txt, TRACKED_WORKTREE.patch, TRACKED_INDEX.patch, UNTRACKED_MANIFEST.txt, and untracked-files.tar. Specify binary-safe diff commands for Gate C. Do not create these files in Gate B. Report PRESERVATION_RECIPE_COMPLETE YES/NO for each.

## B4 — detached HEADs
Confirm the v0.2.14 publication worktree HEAD 46dc94f58e67d5da38420047f009d3f311321108 remains reachable through annotated tag v0.2.14; if verified, classify that worktree SAFE_LOCAL_RETIRE. Confirm flight-recorder HEAD 01eeddaecd0dff596b7e0fd31cd4b1862360bc9f is retained by local ref codex/cross-mode-flight-recorder-minimal and include that ref in history preservation.

## B5 — all 26 non-main remote branches
Use SAFE_REMOTE_RETIRE_MERGED, ARCHIVE_REF_THEN_RETIRE, REMOTE_RETAIN, NEEDS_RECONCILIATION. The three Gate A branches already ancestors of main (codex/project-agents-control-plane-v1, codex/read-only-diagnostic-cli-v1, codex/release-v0.2.14-baseline) should normally be SAFE_REMOTE_RETIRE_MERGED unless evidence contradicts. Default other non-main unmerged branches to ARCHIVE_REF_THEN_RETIRE unless there is an explicit reason to retain them live. Do not merge historical diagnostic/experimental branches just to facilitate cleanup; the history snapshot should preserve their refs/history. Table fields: REMOTE_BRANCH, TIP, IN_MAIN, CLASSIFICATION, PRESERVATION_REQUIRED, REASON.

## B6 — design one pre-cleanup Git history snapshot
Design but do not create /Volumes/Jack-Dev/Archives/RemoteOrbit/retirement-20261009/git/RemoteOrbit-pre-cleanup-all-refs.bundle and refs-manifest.txt. It must preserve all local branches, fetched origin branches, tags, candidate-only commits reachable from local refs, and release history. Gate C must explicitly fetch live remote heads before bundle creation without deleting refs. Specify exact bundle verification commands including git bundle verify and proof required unique commits are present. Do not create the bundle in Gate B.

## B7 — all 46 non-Git artifact groups
Classify each as ARCHIVE_FORENSIC, DELETE_EPHEMERAL, RETAIN_ACTIVE, EXCLUDE_NOT_REMOTEORBIT_OWNED, or NEEDS_INSPECTION. Caches/build/module caches/temp validation outputs generally DELETE_EPHEMERAL. Potentially non-reconstructable capture/evidence/diagnostic/forensic/diff material generally ARCHIVE_FORENSIC. Current Task 036 evidence is RETAIN_ACTIVE. Clearly MemoX-owned material is EXCLUDE_NOT_REMOTEORBIT_OWNED. Unknown source/diff material remains NEEDS_INSPECTION until inspected. Do not delete or move any item.

## B8 — required special inspections
A. /Volumes/Jack-Dev/Data: inspect the two working-diff filenames, headers, hashes, and relationship to RemoteOrbit; decide whether unique RemoteOrbit work is present. Do not modify.
B. /Volumes/Jack-Dev/Projects/_forensics/RemoteOrbit/2026-10-09-v0211-nonseize-hid-audit: inspect MANIFEST.txt, HIDMonitor-working.swift, and the patch; decide whether evidence is unique. Default ARCHIVE_FORENSIC.
C. /Volumes/Jack-Dev/Projects/RemoteOrbit-app-archives: assess whether the v0.2.12 ZIP has a reason to remain under Projects; classify its lifecycle without moving it.
D. /Volumes/Jack-Dev/Projects/remoteorbit-diagnostic-backups: determine whether old app bundles contain anything not reproducible from Git/release history.
E. /Users/jack7788/Applications/RemoteOrbit P1A5 Observer.app: relate the installed app to untracked P1A5Observer source; do not uninstall; classify lifecycle.
F. /Volumes/Jack-Dev/Worktrees/RemoteOrbit: confirm empty; expected DELETE_EPHEMERAL.
G. Resolve the MemoX scoped-owner document exact path. If MemoX-owned and unrelated to RemoteOrbit lifecycle, classify EXCLUDE_NOT_REMOTEORBIT_OWNED.

## B9 — proposed final filesystem design
Gate C should leave /Volumes/Jack-Dev/Projects/remoteorbit as the only RemoteOrbit development source checkout. Durable history belongs under /Volumes/Jack-Dev/Archives/RemoteOrbit/retirement-20261009/, with proposed subdirectories git/, dirty-worktrees/audio-p1-a5/, dirty-worktrees/p0-voice-experiment/, dirty-worktrees/voice-p0-final/, forensics/, release-history/ only for intentionally retained local artifacts, and manifests/GATE_A/, manifests/GATE_B/, manifests/RETIREMENT_MANIFEST.txt. Design only; do not create this structure.

## B10 — exact Gate C manifest
Produce ordered steps for: preservation; verification; worktree removals; local branch retirements; remote branch retirements; non-Git archive/delete actions; empty-directory cleanup; git worktree prune; reverse filesystem scan; final Git integrity checks. Every destructive entry must identify exact TARGET, ACTION, PRECONDITION, PRESERVATION_PROOF, and ROLLBACK_OR_RECOVERY_SOURCE. No wildcard deletion or broad rm -rf. Gate B only designs this manifest.

## Stop conditions
Stop if control head drifts; a new dirty worktree or local-only commit appears; any candidate cannot be classified safely; /Volumes/Jack-Dev/Data contains unresolved unique work; bundle design would fail to preserve a unique commit; or any destructive Gate C entry lacks an exact target. Report the exact stop reason and do not continue dependent classification.

## Acceptance and handoff
Return complete Git candidate, unique commit, dirty worktree, detached-head, all remote branch, and all non-Git artifact classification tables; special-inspection findings; proposed archive layout; exact Gate C manifest; counts; and evidence hashes. Final state is WAITING_FOR_WEB_GATE_B_AUDIT only when every required classification and Gate C manifest is complete and no stop condition remains. Otherwise state the exact STOP reason. Mutations are limited to the paired control-plane transition. Cleanup performed: NO. Never execute Gate C.
