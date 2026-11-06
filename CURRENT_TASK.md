# RemoteOrbit Current Task

## RO-GOVERNANCE-ISSUE-CONTROL-MIGRATION-050 — delegated approval policy migration

Status: `ACTIVE / READY_FOR_DRAFT_PR`
TASK_CLASS: `GOVERNANCE / CONTROL-PLANE`
Repository: `Lost0rz/RemoteOrbit`
Control mode: `FILE_CONTROL`
Control authority: paired `CURRENT_TASK.md` / `CURRENT_STATUS.md` on this authorized policy branch, based on authoritative main
Audited main parent: `660fc839217cbbb290b506357403c0c110171377`
Authorized branch: `codex/task050-delegated-approval-policy`

## Authorization

The user-provided card `RO-GOVERNANCE-050-DELEGATED-APPROVAL-POLICY-001` explicitly authorizes a narrowly scoped delegated Issue approval policy migration, a paired task/status control transition as the first commit, focused official validator positive/negative checks, and one Draft PR for independent audit. It does not authorize automatic merge, ISSUE_CONTROL cutover, Issue body edits or approval comments during this policy-PR phase, or any product/audio/runtime change.

The first paired-control commit updated `CURRENT_TASK.md` and `CURRENT_STATUS.md` together as a direct child of the audited main parent above: `d4008e199a15cbf69a350acad6dfdaa2c88758b9`. The policy PR may change only `AGENTS.md`, `CURRENT_TASK.md`, and `CURRENT_STATUS.md`. Keep the local Bridge branch and the separate dirty Engineering-Governance checkout intact.

## Objective

Propose `ISSUE_DELEGATED_APPROVAL: ENABLED` as one operative declaration in `AGENTS.md` while preserving `CONTROL_MODE: FILE_CONTROL` and the direct human-authored `SPEC_APPROVAL_V1` rule. The declaration exists on this branch only and is not accepted policy until reviewed merge to main. Delegation is a lower-assurance, exact-spec GitHub approval path only; it does not authorize Issue execution under FILE_CONTROL or enable cutover.

## Policy requirements

- Only an explicit user decision in the current conversation approving the exact current Issue specification after digest/revision review can support `SPEC_DELEGATED_APPROVAL_V1`.
- Use the distinct `SPEC_DELEGATED_APPROVAL_V1` identifier and the official required repository, Issue, task, revision, digest, decision, authorization-channel, user-decision, summary, and provenance fields. Never label a proxy comment `SPEC_APPROVAL_V1` or claim independent proof of user intent.
- Preserve trusted `ISSUE_APPROVERS` author checks, OPEN Issue checks, canonical digest equality, revision integrity, revocation detection, and the `DELEGATED_ACCOUNT_ATTESTED` lower-assurance result.
- Web Agent A remains read-only for project audit/spec/status work except for this narrowly authorized delegated approval comment after exact current-spec user approval. This does not grant general GitHub Issue write, repository source, branch, PR lifecycle, merge, release, or cutover authority.
- Local Codex and any connector must not synthesize direct `SPEC_APPROVAL_V1` on an approver's behalf. Keep accepted FILE_CONTROL as the only task authority until a separately authorized and verified cutover.

## Verification

- The installed official Engineering Governance 0.8.1 `test_issue_spec_check.py` suite completed: 34 tests passed, including default-off rejection, exact matching opt-in acceptance, stale digest rejection, and trusted actor/provenance enforcement. No plugin installation or source checkout was modified.
- `git diff --check` passed; the exact change set remains limited to `AGENTS.md`, `CURRENT_TASK.md`, and `CURRENT_STATUS.md`; do not run Swift/product tests.
- Do not modify Issues #41/#42 or post any approval comment in this policy-PR phase.

## PR delivery and stop boundary

Next create one Draft PR from the audited main parent and keep it unmerged. After PR creation, update the paired controls in the same commit to record its identity. Stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`; do not mark Ready or merge.

## After independent audit and merge

Only after live verification that the strategy PR merged to authoritative main, reread Issues #41/#42 and their current comments. Check their approval-method text and exact current digests. If a specification materially changes, increment its revision and calculate a new digest. Obtain an explicit user decision approving each exact current specification before posting any `SPEC_DELEGATED_APPROVAL_V1`; a prior decision or Revision 3 approval must not be carried to a changed spec. Verify the delegated comment author, full digest binding, revocation state, and lower-assurance result using the official helper. This policy PR does not automatically switch `CONTROL_MODE` or authorize ISSUE_CONTROL cutover.

## Preserved Task 049 and PR #40

Task `RO-AUDIO-CONTINUITY-DIAGNOSTIC-049` remains `WAITING_FOR_FRESH_HARDWARE_CAPTURE`; no capture, installation, driver, CoreAudio, product source, merge, or release action is authorized here. PR #40 must remain OPEN / DRAFT / UNMERGED at its live head and must not be modified.
