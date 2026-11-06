# RemoteOrbit Current Task

## RO-GOVERNANCE-ISSUE-CONTROL-MIGRATION-050 — WP05 ISSUE_CONTROL migration PR

Status: `ACTIVE / WP05 IMPLEMENTATION / WAITING_FOR_INDEPENDENT_WEB_AUDIT`
TASK_CLASS: `GOVERNANCE / CONTROL-PLANE`
Repository: `Lost0rz/RemoteOrbit`
Accepted control mode on main: `FILE_CONTROL`
Control authority during this branch: this paired `CURRENT_TASK.md` / `CURRENT_STATUS.md` transaction until the migration PR is merged
Audited main parent: `9ae4d3ab46b93d2229de4c181aae7461e3c187da`
Authorized branch: `codex/task050-wp05-issue-control-cutover`

## Authorization

The user-provided card `RO-GOVERNANCE-050-WP05-CUTOVER-PR-001` authorizes WP05 under the approved Task 050 / Issue #42 Revision 4 scope. The installed official Engineering Governance 0.8.1 verifier returned `STRUCTURE_AND_DELEGATED_APPROVAL_PASS` for Issue #42 Revision 4 digest `6f86c72fd713133246e7287d2f6a252e64eede63da83b6935f88889ab5661bc9`, approval assurance `DELEGATED_ACCOUNT_ATTESTED`, comment `IC_kwDOUD0uu88AAAABjmNoTw`. Issue #41 Revision 4 was independently verified for continuity: digest `6e5ecb8e08411e1c51fb9e9ddf54580e7f9c7fd77ce8f1065fd8ad735065f49c`, comment `IC_kwDOUD0uu88AAAABjmMNzg`, same assurance.

This authorization permits one governance-only migration branch and Draft PR. It does not permit direct changes to main, automatic PR merge, activation of ISSUE_CONTROL before a verified merge, Issue body/comment changes, Task 049 execution, PR #40 changes, or product/audio/runtime/CI changes.

## Objective and scope

Prepare one migration PR that proposes `CONTROL_MODE: ISSUE_CONTROL`, retains `ISSUE_APPROVERS: Lost0rz` and `ISSUE_DELEGATED_APPROVAL: ENABLED`, replaces live FILE_CONTROL startup/task selection rules with exact approved Issue selection and verification, removes `CURRENT_TASK.md` and `CURRENT_STATUS.md` from the proposed active root, and updates only verified active references in:

- `README.md`
- `SETUP_NOTES.md`
- `docs/README.md`
- `docs/DOMAIN_MAP.md`

The first commit of this branch is the paired control-only reconciliation/authorization commit. Subsequent changes remain in the same migration PR. The proposed ISSUE_CONTROL state takes effect only after the Draft PR is independently audited, separately authorized for merge, merged to authoritative main, and the merge is verified.

## Preserved boundaries

- Task `RO-AUDIO-CONTINUITY-DIAGNOSTIC-049` remains `WAITING_FOR_FRESH_HARDWARE_CAPTURE`; no capture, install, driver, CoreAudio, TCC, device, or release operation is authorized.
- PR #40 remains OPEN / DRAFT / UNMERGED at live head `1d6370cb9a9bfa1f1d8bff10095f149fefe89288`; do not modify it.
- Preserve durable product, voice, diagnostics, runtime, CI, security, and human-acceptance rules in `AGENTS.md`.
- Web Agent A retains remote audit/spec/status responsibilities and only the accepted narrow delegated-approval exception. Local Codex verifies and executes the approved Issue scope and records receipts on that same Issue. Neither gains general authority beyond this task.
- No daemon, watcher, external framework, new CI workflow, or per-comment automation.

## Verification and completion

- Freshly verify origin/main, Issue #41/#42 exact Revision 4 approvals, local identity/worktree, open PR writers, and the PR #40 head before any further material mutation.
- Keep the initial control commit limited to `CURRENT_TASK.md` and `CURRENT_STATUS.md`, as a direct child of audited main.
- Verify the proposed tree has one active authority (`ISSUE_CONTROL`) and no active startup/routing requirement for the retired root files.
- Run the official delegated verifier against both latest Issue JSON files and the proposed `AGENTS.md`; run focused documentation/link checks and `git diff --check`.
- Confirm the diff is limited to governance and the necessary active documentation references, and confirm PR #40 is unchanged.
- Create one Draft PR targeting main and stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`.

## STOP boundary

Do not mark the PR Ready, merge it, claim cutover, post Issue approvals/receipts, begin WP06, or act on Task 049. Until a verified merge, authoritative main remains FILE_CONTROL. After publishing the Draft PR, wait for independent Web audit and separate owner merge authorization.
