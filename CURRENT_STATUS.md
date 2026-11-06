# CURRENT_STATUS

Last updated: 2026-11-06
State: `RO-GOVERNANCE-ISSUE-CONTROL-MIGRATION-050 / Delegated Approval Policy Migration — ACTIVE / READY_FOR_DRAFT_PR`
Repository: `Lost0rz/RemoteOrbit`
Remote control authority: `main`
Audited control parent: `660fc839217cbbb290b506357403c0c110171377`
Control mode: `FILE_CONTROL`
Accepted Issue approvers: `Lost0rz`
WP03 approver-policy merge: `a02859e5df597ec7094eda5ac05116c67b0f9d2e` (PR #43, MERGED)
WP04 Bridge merge: `660fc839217cbbb290b506357403c0c110171377` (PR #44, MERGED)
Main CI run `42191445976`: SUCCESS on `660fc839217cbbb290b506357403c0c110171377`
Active policy branch: `codex/task050-delegated-approval-policy`, created from the audited main parent
Policy PR: NOT CREATED

## Task 050 delegated approval policy migration

The user-provided card `RO-GOVERNANCE-050-DELEGATED-APPROVAL-POLICY-001` authorizes a governance-only proposal to opt in to lower-assurance delegated Issue approvals while preserving exact-spec digest checks and provenance. This branch remains a proposal under `FILE_CONTROL`; it does not authorize Issue execution or change the control mode. The first paired control commit `d4008e199a15cbf69a350acad6dfdaa2c88758b9` is a direct child of audited main `660fc839217cbbb290b506357403c0c110171377`. `AGENTS.md` now contains the proposed delegated policy on this branch; it remains unaccepted until a reviewed PR merges to main.

The authorized PR scope is limited to `AGENTS.md`, `CURRENT_TASK.md`, and `CURRENT_STATUS.md`. The policy must keep direct `SPEC_APPROVAL_V1` human-authored, introduce exactly one operative `ISSUE_DELEGATED_APPROVAL: ENABLED`, restrict Web Agent A to a separately identified delegated approval comment after explicit user approval of the exact current Issue spec, and grant no general repository write, product-code, PR-merge, or cutover authority. The installed official checker at Engineering Governance 0.8.1 passed all 34 official tests, including default-off, exact matching digest, stale digest, trusted actor and provenance cases. `git diff --check` passes and the current change set is limited to the three governance files. The PR must remain Draft and stop for independent audit.

PR #40 is separate and remains OPEN / DRAFT / UNMERGED at head `1d6370cb9a9bfa1f1d8bff10095f149fefe89288`; it is outside this policy change. No Issue #41/#42 body edit or approval comment is in this policy-PR phase. After the policy PR is independently audited and merged, reread both live Issue specs and approval records; materially revised specs require a new revision and digest plus explicit user approval of that exact current spec before any `SPEC_DELEGATED_APPROVAL_V1` comment and official verification. No prior revision decision is carried forward.

## Preserved Task 049 workstream (non-writing during Task 050 policy migration)

Task `RO-AUDIO-CONTINUITY-DIAGNOSTIC-049` remains unfinished at `WAITING_FOR_FRESH_HARDWARE_CAPTURE`. Its objective is to classify the decoded-PCM supply-deficit boundary from fresh RC003 evidence; `ROOT_CAUSE_STATUS` remains `UNKNOWN`. No Task 049 execution or hardware capture is authorized during this Task 050 delegated approval policy migration; Issue #41 remains a non-authoritative draft under FILE_CONTROL.

PR #40 remains the separate product-diagnostics PR. Current GitHub evidence: OPEN / DRAFT / UNMERGED, head `1d6370cb9a9bfa1f1d8bff10095f149fefe89288`, base branch `main`, reported base ref `15f213d9bb81986685e751d89753fd7f293e108b`. Current remote main is `660fc839217cbbb290b506357403c0c110171377`; preserve the observed PR base-ref difference for later Task 049 reconciliation. Do not update or otherwise modify PR #40 here.

### Accepted release baseline

RemoteOrbit `v0.2.15` remains the latest published release.
- Version: `0.2.15`
- Build: `44`
- Tag target: `7f1c763e60db8c9ecc4a696f4246d3ee9eaaea1a`

### Confirmed incident boundary

The 2026-11-03 RC003 runtime evidence establishes a decoded-PCM supply deficit with corresponding AudioPipe active-remote underrun. In the inspected sessions, decode rejects / zero-sample decodes and output-ring overflow drops do not explain the deficit. The 500 ms prebuffer was not the observed capacity bottleneck, and the startup-only 45 ms reserve cannot repair a sustained average supply deficit.

Remaining causal boundary:
1. local serial BLE `handleAudio` service time;
2. sustained effective source-clock mismatch;
3. episodic upstream / BLE delivery starvation.

### Task 049 remote implementation and machine evidence

Remote implementation is complete at PR #40 head `1d6370cb9a9bfa1f1d8bff10095f149fefe89288`, without changing product voice behavior.

- Probe A records bounded `BLE_HANDLER_SUMMARY` service-time metrics without per-packet logging or unbounded storage.
- Probe B provides read-only decoded-supply analysis; non-contiguous trace windows are excluded from authoritative source-rate conclusions.
- Exact-head CI run `41628598574`: SUCCESS; 513 Swift tests passed; Native Release build and build-only packaging smoke passed; exact-diff audit passed.
- These are historical machine results; fresh RC003 capture and human hardware acceptance remain pending.

The hardware gate requires an instrumented Task 049 build, persisted `voice.session.summary` / `voice.session.trace`, normal handler summary logs, session IDs and a read-only report. No capture is authorized by the current Task 050 WP04 Bridge stage.

## Workspace and next gate

The canonical local checkout is `/Volumes/Jack-Dev/Projects/RemoteOrbit`, now on `codex/task050-delegated-approval-policy` from audited `origin/main` `660fc839217cbbb290b506357403c0c110171377`. It had one registered RemoteOrbit worktree and no unique local changes before this transition. The separate Engineering-Governance source checkout and its pre-existing `.agents/plugins/marketplace.json` modification are outside this task and remain untouched.

The first paired control commit establishes this authorized policy-migration phase. The branch now proposes the narrowly scoped delegation policy and the installed official validator suite passed. Next: push this branch and create one Draft PR, then stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`; do not merge automatically. PR #40 remains separate and must stay OPEN / DRAFT / UNMERGED.
