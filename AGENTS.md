# RemoteOrbit Agent Instructions

## Mandatory startup contract

Before any project-state-changing action:

1. Read this file for the accepted durable rules and control mode.
2. Resolve the canonical repository and authoritative `main` from live Git evidence.
3. Select one explicit GitHub Issue and read its current body and comments using the authenticated local GitHub client. Confirm canonical repository, Issue number, `TASK_ID`, `SPEC_REVISION`, canonical digest, trusted approval, and applicable Work Package before changing state.
4. Read `README.md`, `SETUP_NOTES.md`, and the documents relevant to the requested subsystem.

Do not use chat history, remembered branch names, stale local notes, or a handoff card as a substitute for accepted repository authority. A handoff carries authority references and a bounded delta; it does not create or expand task authority.

If local branch, HEAD, worktree, remote Issue, PR, installed runtime, or other material identity is stale, ambiguous, or mismatched, perform read-only reconciliation and stop the affected mutation until it is resolved. Do not reset, clean, stash, rewrite history, prune, or delete work to hide a mismatch.

If the requested work is outside the selected Issue's approved scope, stop. A material scope change requires a new Issue revision, canonical digest, and matching approval before the affected mutation.

## Authority model

- `AGENTS.md` owns durable engineering and process rules and selects the accepted control mode.
- In accepted `ISSUE_CONTROL`, one selected, approved GitHub Issue revision owns the active task scope, Work Packages, non-goals, STOP conditions, and completion criteria.
- Approval, revocation, and execution receipts belong in comments on that same Issue. GitHub PR, CI, commit, and release records remain the authorities for their respective delivery facts.
- Root `CURRENT_TASK.md` and `CURRENT_STATUS.md` are retired from active authority after the migration PR is merged. Their prior contents remain in Git history; do not create or rely on duplicate live task/status controls.
- Project Profile, Domain maps, planning documents, handoffs, audits, CI/test results, and PR observations do not independently authorize execution.

After a material execution or delivery transition, update the selected Issue with a bounded, verifiable receipt when its Work Package requires it. Do not create a second task authority to mirror Issue progress.

## Control mode and Issue approver policy

CONTROL_MODE: ISSUE_CONTROL
ISSUE_APPROVERS: Lost0rz
ISSUE_DELEGATED_APPROVAL: ENABLED

These declarations become accepted repository policy only when the authorized migration PR is merged to the authoritative `main` and the merge is verified. A branch or Draft PR containing these declarations does not itself perform cutover. Until that event, accepted `main` remains under its previously accepted control mode and work must stay within the current accepted task authorization.

For every state-changing operation, select exactly one canonical repository, Issue, `TASK_ID`, `SPEC_REVISION`, and `SPEC_SHA256`. Using the authenticated local GitHub client and the installed official Governance verifier, verify that the current Issue is open and its exact digest is approved by a trusted author before acting. If the Issue or verifier cannot be read, stop. Verify local `gh` identity and access for any required Issue write; connector access alone is not proof of local CLI capability. Labels, PR metadata, approval-like prose, or a handoff card cannot replace that verification or expand an approved Work Package.

The direct approval path is a separate `SPEC_APPROVAL_V1` comment authored by the actual authenticated GitHub user listed in `ISSUE_APPROVERS`. It must bind the canonical repository, Issue, `TASK_ID`, `SPEC_REVISION`, and `SPEC_SHA256`, and state `DECISION: APPROVED_FOR_EXECUTION`. An execution agent or connector must not author or synthesize direct approval on an approver's behalf or approve its own work.

This repository explicitly opts in to the lower-assurance `SPEC_DELEGATED_APPROVAL_V1` path through the single operative declaration above. Only Web Agent A may use this narrow GitHub approval proxy, and only after the user explicitly approves the exact current Issue specification in the present conversation after reviewing its repository, Issue, task, revision, canonical digest, impact, and material changes. A delegated comment must use the distinct identifier and official fields `REPOSITORY`, `ISSUE`, `TASK_ID`, `SPEC_REVISION`, `SPEC_SHA256`, `DECISION`, `AUTHORIZATION_CHANNEL`, `USER_DECISION`, `USER_DECISION_SUMMARY`, and `PROVENANCE`; set `AUTHORIZATION_CHANNEL: CHATGPT_WEB`, `USER_DECISION: EXPLICIT_APPROVAL_OF_CURRENT_SPEC`, and `PROVENANCE: ACCOUNT_PROXY_NO_INDEPENDENT_CHAT_PROOF`. The summary must truthfully describe the user's explicit decision without sensitive content. The authenticated comment author must be listed in `ISSUE_APPROVERS`. The official verifier must confirm the Issue is open, the complete record and exact current digest match, and there is no revocation or conflicting revision hash; report the lower-assurance result as `DELEGATED_ACCOUNT_ATTESTED`. This is an account-proxy attestation, not independent proof of user intent. A materially changed specification needs a new revision, digest, and explicit user decision.

Delegated approval grants no general GitHub Issue write, repository source, branch, PR lifecycle, merge, release, or cutover authority. It does not authorize execution outside the exact approved Issue scope or permit an execution agent to approve its own implementation.

Web Agent A owns remote read-only project audit, specification/design review, and status/evidence reading, with only the narrow delegated-approval exception described above. Local Codex owns verification and implementation that are separately authorized by the selected Issue, focused validation, and verifiable execution receipts on that same Issue. Neither role receives broader authority through a card or connector.

## Issue-control execution and transition protocol

A material control-plane transition includes changing the active task or phase, authorized side effects, the active Issue/PR/workspace, or a lifecycle decision that enables merge, release, deletion, or other project-state mutation. Such a transition is valid only when the selected approved Issue's completion gate names it and its evidence is satisfied, or the user explicitly authorizes that exact transition under the currently accepted control mode.

Before each material transition:

1. Read the live authoritative main, selected Issue, relevant PR/ref, and active local branch/worktree.
2. Revalidate exact Issue revision, digest, approval, revocation state, and current Work Package against the proposed action.
3. Keep all changes within that Work Package's allowed operations and safety limits. A new material scope requires a new Issue revision and approval.
4. Record required decisions or outcomes on the same Issue; preserve GitHub as authority for commits, PR, CI, and merge events.
5. If an approval, Issue body, writer, or authoritative ref changes during the operation, stop and reconcile before continuing.

Do not update or recreate the retired root task/status files as a parallel control plane. Control-mode migration itself takes effect only after the migration PR has been independently audited, separately authorized for merge, merged to authoritative main, and verified there. Before the merge, do not claim cutover or use proposed branch policy to bypass accepted main authority.

### PR metadata is evidence, not task authority

The open/closed/draft state of a PR is an observed repository fact. It does not grant, revoke, or advance task authority by itself.

If PR metadata changes out of band, treat it as state drift; preserve lifecycle classification separately from current PR state; and do not infer a new task or phase. Do not open, close, mark ready, or merge a PR unless the selected approved Issue or the user's current explicit authorization permits that exact action.

### Live branch identity is not the same as PR head identity

When a branch is the active workspace, resolve its current ref directly from repository branch/ref state. Do not use a PR's `head_sha` as a proxy for live branch HEAD after the PR has been closed. If they differ, record the difference rather than treating either as an implicit task transition.

## Evidence vocabulary

Use these labels consistently whenever project state or diagnostic conclusions are material:

- **FACT** — directly verified by current evidence.
- **INFERENCE** — strongly supported by verified facts but not directly observed.
- **HYPOTHESIS** — plausible explanation requiring more evidence.
- **UNKNOWN** — not established by available evidence.
- **HISTORICAL** — previously reported/accepted context not verified as current.

Do not promote INFERENCE, HYPOTHESIS, UNKNOWN, or HISTORICAL state to FACT through repetition.

## State-drift and freshness gate

Before product implementation or another side-effectful operation, revalidate the material authority fields needed by the selected Issue. At minimum, when applicable:

- verified canonical RemoteOrbit remote identity and fetched authoritative main;
- selected Issue number, task ID, revision, digest, OPEN state, trusted approval, and revocation/conflict state;
- active PR and relevant live PR head/base;
- authoritative local worktree path, local branch or detached state, exact local HEAD, and clean/dirty/untracked state;
- installed/running runtime identity when runtime evidence matters.

If a material field cannot be verified or differs from the selected approved Issue or live host state, stop the affected mutation and reconcile read-only. Do not auto-reset, clean, stash, checkout, rewrite history, prune/delete a worktree, or reinterpret the task to hide the mismatch. Resume only when the authority and local state are coherent.

A remote-only session must not claim current local worktree, installed app, running process, driver, LaunchAgent, or TCC state without local evidence.

## Project policy

1. Product behavior and explicitly accepted contracts take precedence over implementation convenience. Do not silently redesign user-visible behavior.
2. Keep this file limited to durable project rules. Active task authorization belongs to the selected approved Issue; current PR, branch, CI, merge, and release facts belong to their GitHub records.
3. Do not expand a bounded Issue Work Package into unrelated cleanup, refactoring, packaging, release, or installation work without authorization.
4. Worktree/branch/PR cleanup is state-changing work. Inventory and classify first; delete, prune, close, merge, or rewrite only when the selected approved Issue or current explicit user authorization permits that exact mutation.
5. Worktree retirement and branch retirement are separate lifecycle actions. A clean worktree may be removed while its local and remote branches are deliberately retained when current authority proves the branch remains a valid history authority. Never treat worktree removal as implicit branch deletion.
6. If a cleanup target is already absent before the authorized mutation begins, classify it as reconciliation/drift; do not count the current executor as having performed that deletion.

## Durable CI authority

- `.github/workflows/remoteorbit-ci.yml` is the durable routine source/test/build CI
  entry point for RemoteOrbit.
- Routine macOS CI is expected to route to the repository-scoped self-hosted runner
  labels `[self-hosted, macOS, ARM64, remoteorbit]` unless a later task explicitly
  changes that authority.
- CI is software/build-only by default. It must not install or replace
  `/Applications/RemoteOrbit.app`, install/reload `RemoteOrbitAudio.driver`, restart
  CoreAudio, reset/change TCC, alter default audio devices, or promote real
  RC003/Doubao interaction to machine-owned product acceptance.
- Runner unavailability is an infrastructure failure to report, not implicit
  authority to fall back to paid GitHub-hosted macOS or mutate the host runtime.
- Real hardware/runtime acceptance remains a separately authorized, human-owned gate.

## Runtime identity and evidence

7. Treat these as distinct identities unless proven otherwise:
   - source checkout and source HEAD;
   - built executable or app bundle;
   - installed `/Applications/RemoteOrbit.app`;
   - running process;
   - installed `RemoteOrbitAudio.driver`;
   - LaunchAgent/runtime configuration.
8. Any runtime conclusion that depends on identity must report the material
   identity evidence, such as source HEAD, executable path/hash, app version/build,
   Bundle ID/code identity, installed component version, or running process.
9. A Terminal/helper permission result does not prove the RemoteOrbit product
   process has the same TCC/Accessibility/Input Monitoring/Event access. Product
   permission claims require evidence from the product process or an equivalent
   identity-preserving check.
10. Symptom recovery, restart success, reload success, or temporary stability does
    not by itself establish root cause. Separate observed recovery from causal proof.
11. Do not substitute one evidence class for another. Source evidence, protocol
    evidence, hardware evidence, runtime identity, packaging evidence, and permission
    evidence answer different questions.

## Forensic and side-effect discipline

12. During an incident/forensic capture, preserve the observed runtime by default.
    Do not rebuild, reinstall, replace the app, change TCC permissions, alter
    LaunchAgents, replace/reinstall the HAL driver, restart CoreAudio, or change
    diagnostic behavior unless the task explicitly authorizes that mutation.
13. Packaging, installation, driver replacement, `coreaudiod` restart, TCC
    changes, LaunchAgent changes, worktree deletion/pruning, and history rewriting
    are side-effectful operations. An audit, diagnosis, or source-only task does not
    authorize them.
14. Do not stack a speculative production fix on top of unresolved diagnostic
    work without first reconciling what is observation-only, experimental, frozen
    evidence, and intended for production.

## Validation

15. Validate the changed boundary with the smallest sufficient evidence. Protocol,
    audio, HID, packaging, permission, and installed-runtime claims may require
    different validation; one class of evidence must not be substituted for another.
16. Tests should establish contract behavior or regression protection, not merely
    increase test count. Use broader regression only when the affected boundary or
    requested acceptance criteria justify it.
17. Before recommending merge or release, state remaining uncertainty and any
    runtime behavior that was not directly validated.
18. A task is not closed merely because tests pass. Reconcile current state, callers,
    active worktree/PR, remaining uncertainty, and the explicit acceptance criteria.
19. A merge does not automatically authorize a release.

## Durable voice interaction invariant

20. The RC003 microphone button has one user-visible voice mode. A quick SHORT tap
    (release before the accepted 300 ms hold boundary) is a no-op: it must not replay
    the IME trigger, synthesize a tap, toggle/open/close a Persistent session, or show
    voice/readiness HUD state. A held LONG press crossing the 300 ms boundary promotes
    into the direct remote voice lifecycle; release then follows the existing direct
    drain/close path. Persistent and dual-receiver semantics are not production
    authorities for the microphone button unless the user explicitly changes this
    durable product contract in a future governed task.

## Retirement and diagnostics discipline

21. Retire obsolete voice modes by production authority, not by symbol name. Remove
    obsolete user-visible semantics, live configuration, runtime entry points, and
    tests that assert retired behavior; do not delete shared mechanisms solely because
    they were historically named Persistent or Dual. Preserve any mechanism still
    required to satisfy the durable LONG-only contract until an equivalent replacement
    is proven by focused regression evidence.
22. Treat correctness/safety mechanisms and diagnostics as separate concerns. A
    diagnostics-off optimization must not disable bounded ownership, release/drain,
    suppression, watchdog, or transport mechanisms that are required for correctness.
    Audio recording remains a separately controlled opt-in diagnostic surface.
