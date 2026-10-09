# RemoteOrbit Current Task

## RO-REPOSITORY-LIFECYCLE-CLOSEOUT-036 — Gate C

- Status: ACTIVE — GATE C PRESERVATION AND RETIREMENT
- Repository: Lost0rz/RemoteOrbit
- Canonical path: /Volumes/Jack-Dev/Projects/remoteorbit
- Canonical branch: main
- Gate A: PASS.
- Gate B: PASS.
- Corrected manifest audit: PASS.
- Gate C authorization: explicitly granted by the user for this request.
- Required Gate C start parent: 579b35fb5da814fc1f14402807b35fe32dd79828.
- Accepted manifest: /private/tmp/remoteorbit-lifecycle-closeout-036-gateb-20261009T122025Z/GATE_C_RETIREMENT_MANIFEST.txt
- Accepted manifest SHA-256: 4f5e6d8e4aa3496989df7f0a84ce431da1b69d8ba21ff76fb8aca7cad12ff7d9.

## Objective
Execute the accepted Gate C manifest exactly: preserve and verify every required ref, commit, dirty worktree, artifact, and prior gate evidence; then retire only the exact accepted targets; complete final Git and reverse-scan acceptance; and hand off for an independent web closeout audit.

## Authorized actions
- The exact read-only checks, archive creations/copies, bundle and dirty-worktree preservation, exact worktree/clone/local-branch/remote-branch retirement, exact ephemeral-target removal, exact empty-parent removal, and worktree pruning enumerated in the accepted manifest.
- The paired CURRENT_STATUS.md and CURRENT_TASK.md Gate C control transition and fast-forward push, directly parented by the verified Gate B head.
- The paired final handoff update and fast-forward push only after every Gate C acceptance check passes.
- Write Gate C evidence only under /Volumes/Jack-Dev/Archives/RemoteOrbit/retirement-20261009/manifests/GATE_C/.

## Scope limits and stop conditions
- The accepted corrected manifest is the sole execution authority. Do not add targets, broaden cleanup, or substitute paths.
- Preservation must precede every dependent retirement. Any failed or mismatched preservation proof immediately stops dependent destructive execution.
- Stop on manifest identity mismatch; preflight, branch, remote-ref, PR, worktree, path, content, checksum, or archive-destination drift; unexpected children; or any missing preservation proof.
- Do not touch unrelated Data entries, the MemoX-owned document, sibling forensic directories, product source, tests, runtime, packaging, or installed artifacts except the exact app copy named by the manifest.
- Do not declare Task 036 fully closed. After all checks pass, set GATE C EXECUTION COMPLETE / WAITING FOR INDEPENDENT WEB CLOSEOUT AUDIT and stop.

## Completion criteria
- Required all-refs bundle verifies and contains all accepted refs, tags, and 12 candidate-only commits; mirror verifier fsck passes.
- All three dirty-worktree packages and the named P1A5 app copy verify.
- Every named forensic/release and Gate A/Gate B evidence copy matches its source and is readable before the exact source retirement.
- Only exact manifest worktrees, clone, branches, remote refs, ephemeral paths, and empty parents are retired; all counts and paths are recorded.
- Final canonical worktree is clean on main; only canonical worktree, local main, and live remote main remain; tags are unchanged; final fsck, bundle checks, checksums, and reverse scan pass.
- The paired final handoff is pushed fast-forward, the live main SHA is recorded, and Task 036 waits for the independent web audit.
