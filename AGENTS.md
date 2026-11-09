# RemoteOrbit Agent Instructions

CONTROL_MODE: ISSUE_CONTROL
ISSUE_APPROVERS: Lost0rz
ISSUE_DELEGATED_APPROVAL: ENABLED
ISSUE_WEB_SPEC_AUTHORING: ENABLED

Keep exactly one operative declaration for each control and channel above; only the version accepted on live `main` is authoritative. Approver membership and opt-ins change only through their separately approved policy boundary.

## Project authority and execution environments

Engineering Governance `project-governance` owns the reusable engineering workflow. This file selects RemoteOrbit's control mode and owns permanent RemoteOrbit policy. Use the installed `project-governance` contracts `references/issue-control.md`, `references/issue-execution-contract.md`, `references/control-plane.md`, `references/control-identity.md`, `references/workspace-lifecycle.md`, `references/verification-tiers.md` and `references/remote-delivery.md` for the procedures they own. If the required capability or reference is unavailable or incompatible with this file, stop the affected write; do not substitute or invent another framework.

Cloud and local are execution/evidence contexts, not fixed planner, reviewer or implementation roles. Do not require a particular assistant, model, CLI or worker technology. Role flexibility does not change authenticated approval, Issue-write, source-write or merge permissions. Resolve the current environment's actual capabilities and permissions for each action; cloud-only evidence does not prove local app, driver, LaunchAgent, worktree or TCC state.

The declarations above select the accepted Issue Control mode and two optional authoring/approval channels. They do not authorize arbitrary agents to approve, self-approve, impersonate another approval channel or change source/PR/merge state. An exact approved Issue revision remains the task execution authority. Retired root `CURRENT_TASK.md` and `CURRENT_STATUS.md` are historical only.

## Issue authority and writer permissions

Before execution or any repository mutation other than the narrow Web Issue-spec authoring operation below, resolve the canonical repository and live authoritative `main`; select one exact Issue and read its current body, state and relevant comments. Verify the repository, Issue, `TASK_ID`, `SPEC_REVISION`, canonical digest, OPEN state, trusted approval, no revocation/conflicting revision, and the proposed action's Work Package with the installed official verifier. Confirm the authenticated identity and effective write permission of the actual channel; a GitHub Connector and local `gh` are separate permission surfaces. Check relevant PR/ref, branch/worktree state and overlapping writers. If authority or identity is stale, missing or ambiguous, stop and reconcile read-only.

Direct `SPEC_APPROVAL_V1` must be authored by an actual authenticated user listed in `ISSUE_APPROVERS`; an executor must not synthesize it or approve its own work. `SPEC_DELEGATED_APPROVAL_V1` is a separate lower-assurance account proxy: only Web Agent A may use it after explicit user approval of the exact current specification, and the official verifier must report `DELEGATED_ACCOUNT_ATTESTED`. Neither path grants general Issue write, source, branch, PR, merge or release authority.

Web Issue-spec authoring is separate from approval and execution. It requires an explicit current user request and exactly one operative `ISSUE_WEB_SPEC_AUTHORING: ENABLED` declaration accepted on live `main`, verified with the installed `web_spec_authoring_opt_in()` helper. Before writing, check for duplicate/current Issues, reread the exact target Issue and relevant comments, verify the authenticated Issue writer's channel permission, and resolve overlapping writers. For an approved or in-progress revision, pause the affected writer; increment `SPEC_REVISION` for a body edit and preserve comments/approval history. Stop if the writer cannot be safely paused. Read back the published body and digest. This exception authorizes only the requested Issue body operation; it never authorizes approval, source, branch/worktree, PR, merge, release or runtime actions.

An exact approved Issue authorizes only its listed scope and current Work Package. Comments, labels, audits, CI, PR state and handoff cards do not expand scope. Do not recreate retired root task/status files as parallel controls.

## Freshness, PR and workspace safety

At each material transition, re-read live `main`, the selected Issue, relevant PR/ref and active local branch/worktree. Resolve a live branch from branch/ref state; do not substitute a PR `head_sha` for the live branch HEAD, especially after PR closure. PR open/closed/draft state is evidence, not task authority. Do not write directly to protected `main` unless the selected approved Issue and accepted repository rules expressly authorize it. If a material identity or writer changes, stop and reconcile before continuing.

Worktree, branch and PR cleanup are state-changing actions. Inventory and classify first; preserve unknown or unique work. Do not reset, clean, stash, overwrite, prune, delete or rewrite history to conceal a mismatch. Worktree retirement and branch retirement are separate; removing one does not imply deleting the other. If a cleanup target is already absent, classify it as pre-existing drift rather than executor-performed cleanup. Remote evidence alone does not prove local branch, worktree, cleanliness or runtime state.

For product work, consult `README.md`, `SETUP_NOTES.md` and the relevant subsystem contracts. Accepted product behavior takes precedence over implementation convenience; do not silently redesign it.

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

- Treat these as distinct identities unless proven otherwise:
  - source checkout and source HEAD;
  - built executable or app bundle;
  - installed `/Applications/RemoteOrbit.app`;
  - running process;
  - installed `RemoteOrbitAudio.driver`;
  - LaunchAgent/runtime configuration.
- Any runtime conclusion that depends on identity must report the material
  identity evidence, such as source HEAD, executable path/hash, app version/build,
  Bundle ID/code identity, installed component version, or running process.
- A Terminal/helper permission result does not prove the RemoteOrbit product
  process has the same TCC/Accessibility/Input Monitoring/Event access. Product
  permission claims require evidence from the product process or an equivalent
  identity-preserving check.
- Symptom recovery, restart success, reload success, or temporary stability does
  not by itself establish root cause. Separate observed recovery from causal proof.
- Do not substitute one evidence class for another. Source evidence, protocol
  evidence, hardware evidence, runtime identity, packaging evidence, and permission
  evidence answer different questions.

## Forensic and side-effect discipline

- During an incident/forensic capture, preserve the observed runtime by default.
  Do not rebuild, reinstall, replace the app, change TCC permissions, alter
  LaunchAgents, replace/reinstall the HAL driver, restart CoreAudio, or change
  diagnostic behavior unless the task explicitly authorizes that mutation.
- App packaging/installation, audio-driver replacement, `coreaudiod` restart,
  TCC or LaunchAgent changes are runtime side effects requiring explicit
  authorization; source-only work does not authorize them.
- Worktree deletion/pruning and history rewriting are also side-effectful and
  require exact authority. Never use them to hide state drift or discard unknown
  work.
- Do not stack a speculative production fix on top of unresolved diagnostic
  work without first reconciling what is observation-only, experimental, frozen
  evidence, and intended for production.

## Project-specific verification and evidence

- Verify audio, HID, packaging, permission and installed-runtime claims with the corresponding evidence class; source-only checks do not establish real driver or hardware behavior.
- Use **FACT**, **INFERENCE**, **HYPOTHESIS**, **UNKNOWN** and **HISTORICAL** consistently for material state claims. Do not promote inference, hypothesis, unknown or historical state to fact by repetition.
- Validate the changed boundary with the smallest sufficient evidence. Tests must establish the contract or regression protection; use broader checks only when the affected boundary or acceptance criteria require them.
- A task is not closed merely because tests pass. Reconcile current state, callers, active worktree/PR, remaining uncertainty and acceptance criteria. Report material unverified runtime behavior before merge or release recommendations.
- A merge does not authorize a release. Real hardware/runtime acceptance remains human-owned unless explicitly changed by an authorized task.

## Durable voice interaction invariant

- The RC003 microphone button has one user-visible voice mode. A quick SHORT tap
  (release before the accepted 300 ms hold boundary) is a no-op: it must not replay
  the IME trigger, synthesize a tap, toggle/open/close a Persistent session, or show
  voice/readiness HUD state. A held LONG press crossing the 300 ms boundary promotes
  into the direct remote voice lifecycle; release then follows the existing direct
  drain/close path. Persistent and dual-receiver semantics are not production
  authorities for the microphone button unless the user explicitly changes this
  durable product contract in a future governed task.

## Retirement and diagnostics discipline

- Retire obsolete voice modes by production authority, not by symbol name. Remove
  obsolete user-visible semantics, live configuration, runtime entry points, and
  tests that assert retired behavior; do not delete shared mechanisms solely because
  they were historically named Persistent or Dual. Preserve any mechanism still
  required to satisfy the durable LONG-only contract until an equivalent replacement
  is proven by focused regression evidence.
- Treat correctness/safety mechanisms and diagnostics as separate concerns. A
  diagnostics-off optimization must not disable bounded ownership, release/drain,
  suppression, watchdog, or transport mechanisms that are required for correctness.
  Audio recording remains a separately controlled opt-in diagnostic surface.
