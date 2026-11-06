# RemoteOrbit Current Task

## RO-GOVERNANCE-ISSUE-CONTROL-MIGRATION-050 / WP04 — post-merge Issue spec reconciliation

Status: `ACTIVE / WAITING_FOR_INDEPENDENT_WEB_AUDIT`
TASK_CLASS: `GOVERNANCE / CONTROL-PLANE`
Repository: `Lost0rz/RemoteOrbit`
Control mode: `FILE_CONTROL`
Control authority: this `CURRENT_TASK.md` on the authorized Bridge PR branch
Audited control parent: `a02859e5df597ec7094eda5ac05116c67b0f9d2e`
WP04 control transition commit: `62aa07ce0e1a2c47c86ed1a840a4930d2b76a1f0`
WP03 preparation PR: #43 — MERGED at the audited control parent
Authorized Bridge branch: `codex/task050-wp04-control-bridge`
Bridge PR: #44 — https://github.com/Lost0rz/RemoteOrbit/pull/44 — OPEN / DRAFT / UNMERGED

## Authorization

The user-provided card `RO-GOVERNANCE-050-WP04-CONTROL-BRIDGE-001` explicitly authorizes the WP03 to WP04 FILE_CONTROL transition, paired updates to `CURRENT_TASK.md` and `CURRENT_STATUS.md`, and one exceptional control-only Draft Bridge PR. The transition commit must be a direct child of the live, audited `origin/main` above. The Bridge PR must remain Draft and unmerged for independent audit.

`AGENTS.md` on accepted main remains `CONTROL_MODE: FILE_CONTROL`; `ISSUE_APPROVERS: Lost0rz` is accepted after PR #43 merged. That policy does not approve either Issue or activate ISSUE_CONTROL.

## Objective

Reconcile the post-merge WP03 status drift and establish the Task 050 / WP04 authorization on the paired control files. This Bridge PR stage is limited to the two control files. Do not resume Issue #41/#42 body edits or approval preparation until the Bridge PR is merged and its live main state is revalidated.

## Current Bridge PR scope and allowed side effects

Only these repository files may change in the Bridge PR:

- `CURRENT_TASK.md`
- `CURRENT_STATUS.md`

Authorized delivery side effects: create the named branch from freshly verified `origin/main`, make the paired control transition commit directly from the audited parent, run focused governance checks, push only this branch, and create one Draft Bridge PR. After PR creation, any update recording its identity must change both control files in the same commit. Do not create another PR or merge this one.

Do not modify `AGENTS.md`, Issue #41 or #42, PR #40, product source, runtime, driver, audio settings, TCC, or CoreAudio. Do not switch to ISSUE_CONTROL, merge any PR, or run the full Swift suite.

## WP04 continuation after the Bridge PR gate

After an independently audited and verified Bridge PR merge, resume WP04 Issue-spec reconciliation under FILE_CONTROL: reread current main controls and both complete Issue bodies; update stale baselines and authority descriptions; increment a revision when a body materially changes; run the installed official digest and structural checker against fresh JSON; and perform semantic and dependency review. Prepare exact approval records, but only authenticated GitHub user `Lost0rz` may post each `SPEC_APPROVAL_V1` approval. Verify those comments from fresh Issue data. Issue approval does not authorize ISSUE_CONTROL or cutover; WP05 and WP06 remain separate gates.

## Preserved Task 049 workstream

Task `RO-AUDIO-CONTINUITY-DIAGNOSTIC-049` remains unfinished at `WAITING_FOR_FRESH_HARDWARE_CAPTURE`; its objective remains classifying the decoded-PCM supply-deficit boundary, and `ROOT_CAUSE_STATUS` remains `UNKNOWN`. PR #40 remains OPEN / DRAFT / UNMERGED at head `1d6370cb9a9bfa1f1d8bff10095f149fefe89288`; it must remain unmodified. No Task 049 source edits, hardware capture, installation, driver or CoreAudio action, merge, or release is authorized by this Bridge stage.

## Bridge PR completion criteria

- `CURRENT_TASK.md` and `CURRENT_STATUS.md` are updated together, with the first transition commit a direct child of audited `origin/main`.
- The paired controls identify PR #43 as merged at `a02859e5df597ec7094eda5ac05116c67b0f9d2e`, accepted `ISSUE_APPROVERS: Lost0rz`, and `FILE_CONTROL` as unchanged.
- Task 049, PR #40, its fresh RC003 hardware gate, and unresolved cause remain preserved.
- The Bridge PR changes exactly the two authorized control files, is OPEN / DRAFT / UNMERGED, and its live branch head matches the PR head.
- Focused governance checks pass; the full Swift suite is not run.
- Stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`. Do not auto-merge.
