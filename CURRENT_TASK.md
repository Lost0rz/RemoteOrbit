# RemoteOrbit Current Task

## RO-GOVERNANCE-ISSUE-CONTROL-MIGRATION-050 / WP03 — FILE_CONTROL approver-policy bootstrap

Status: `ACTIVE / WAITING_FOR_INDEPENDENT_WEB_AUDIT`
TASK_CLASS: `GOVERNANCE / CONTROL-PLANE`
Repository: `Lost0rz/RemoteOrbit`
Control mode: `FILE_CONTROL`
Control authority: this `CURRENT_TASK.md` on the authorized preparation branch
Control parent: `0b1d3bef345c6d019240f136c875e01a91d25c0e`
Control transition commit: `4bcca00441e20d64403076a286e925ad04488d29`
Policy commit: `69470e3caa66c62dff151cc705ddae1eb393fbd8`
Authorized preparation branch: `codex/task050-wp03-approver-policy`
Preparation PR: #43 — https://github.com/Lost0rz/RemoteOrbit/pull/43 — OPEN / DRAFT / UNMERGED.

## Authorization

The user-provided execution card `RO-GOVERNANCE-050-WP03-EXEC-001` explicitly authorizes the FILE_CONTROL transition to Task 050 / WP03, edits to the three named control files, publication of the authorized preparation branch, and creation of one independent Draft PR. It explicitly prohibits merge and ISSUE_CONTROL activation.

Issue #42 revision 2 is an unapproved planning reference only. It does not authorize this or later work.

## Objective

Bootstrap a proposed trusted approver policy under FILE_CONTROL while preserving Task 049 and PR #40. Prepare one governance-only Draft PR and stop for independent Web audit. ISSUE_CONTROL remains disabled.

## Scope and allowed side effects

Only these repository files may change:

- `AGENTS.md`
- `CURRENT_TASK.md`
- `CURRENT_STATUS.md`

The first source-changing commit must update `CURRENT_TASK.md` and `CURRENT_STATUS.md` together and be a direct child of the audited control parent above. A later policy commit may update only `AGENTS.md`. After Draft PR creation, record its identity by updating both control files in one commit.

Authorized delivery side effects: create the named preparation branch, commit the bounded changes, push only that branch, and create one Draft PR. Keep the PR unmerged and await independent audit.

## WP03 completion criteria

- The active task and status identify this Task 050 / WP03 authorization and the preparation branch.
- Task 049 remains documented as unfinished and non-writing during this task; its diagnostic objective, unresolved cause and fresh RC003 hardware gate remain preserved in `CURRENT_STATUS.md`.
- `AGENTS.md` explicitly declares `CONTROL_MODE: FILE_CONTROL` and proposes `ISSUE_APPROVERS: Lost0rz`, with exact-spec approval and Web/local role boundaries.
- Durable RemoteOrbit voice, audio diagnostic, hardware, CI, installation, driver, TCC, CoreAudio, runtime identity, branch, PR and worktree safety rules are preserved.
- The preparation PR changes exactly the three authorized files, is OPEN / DRAFT / UNMERGED, and its live head matches the published branch.
- Stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`. Do not merge.

## Preserved Task 049 workstream

Task `RO-AUDIO-CONTINUITY-DIAGNOSTIC-049` remains unfinished at `WAITING_FOR_FRESH_HARDWARE_CAPTURE`; its objective remains classifying the decoded-PCM supply-deficit boundary, and `ROOT_CAUSE_STATUS` remains `UNKNOWN`. PR #40 remains the separate product-diagnostics PR at head `1d6370cb9a9bfa1f1d8bff10095f149fefe89288`; it must remain OPEN / DRAFT / UNMERGED and unmodified.

Task 049 is retained as a non-writing workstream during this Task 050 transition. This task authorizes no Task 049 source edits, hardware capture, installation, driver or CoreAudio action, merge or release.

## Verification

Use focused governance checks only: verify the control transition commit parent and paired Task/Status change; review the exact three-file diff; confirm FILE_CONTROL remains active; verify the published ref and Draft PR head/state. Do not run the Swift test suite for these control-file changes.

## STOP

Stop if remote main moves before the initial control transition is published, if an overlapping control-plane writer or unique local work appears, if the branch/PR identity conflicts, or if PR #40 changes materially. Do not reset, clean, stash, rebase, force-push, delete worktrees, approve Issues, execute WP04–WP06, or merge any PR.

After the independent Web audit, wait for separate user merge authorization.
