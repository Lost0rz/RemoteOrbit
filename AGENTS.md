# RemoteOrbit Agent Instructions

## Mandatory startup contract

Before changing code, diagnostics, packaging, runtime configuration, tests, or project
state, read these files in order:

1. `AGENTS.md` — durable project rules.
2. `CURRENT_STATUS.md` — current repository/runtime/worktree authority.
3. `CURRENT_TASK.md` — the only currently authorized work scope.

Do not use chat history, remembered branch names, stale local notes, or an old worktree
as a substitute for these files.

If the local branch, HEAD, worktree, PR, installed runtime, or other material identity
does not match `CURRENT_STATUS.md`, do not continue production mutation. Perform a
read-only reconciliation first, update the state record, and only then resume work.

If the requested work is outside `CURRENT_TASK.md`, update and explicitly re-freeze
the task before implementation. One active task/worktree is the default; parallel
work must be explicitly recorded.

Before changing code, packaging, runtime configuration, or diagnostics, also read
[README.md](README.md), [SETUP_NOTES.md](SETUP_NOTES.md), and the documents relevant
to the requested subsystem.

## Authority model

- `AGENTS.md` owns durable engineering/process rules.
- `CURRENT_STATUS.md` owns mutable current-state facts and must distinguish
  remote-verified facts from local-only or unverified facts.
- `CURRENT_TASK.md` owns the active scope, non-goals, next action, and completion
  criteria.
- Git, GitHub, and runtime evidence are evidence used to update these records; they
  do not justify silently bypassing a recorded mismatch.
- A conversation is not a state database.
- An open PR, existing branch, registered worktree, or remembered checkout is not
  active merely because it exists.

After a material transition (new active worktree, branch/HEAD change, PR
creation/closure, task handoff, runtime identity change, or accepted conclusion),
update the relevant current-state/task record as part of the transition.

## Control-plane transition protocol

A material control-plane transition includes any change to:

- the task name or phase;
- the set of authorized side effects;
- the single ACTIVE PR/branch/worktree authority;
- a lifecycle decision that enables closing, merging, deleting, pruning, installing,
  releasing, or otherwise mutating project state.

Such a transition is valid only when one of these is true:

1. the user explicitly authorized that transition in the current request; or
2. the current task's completion gate explicitly names that exact next transition
   and the gate has been satisfied with evidence.

An agent must not advance to a "logical next phase" on its own.

For every material transition:

1. read the current control-plane branch HEAD;
2. revalidate the current task/status against direct evidence;
3. update `CURRENT_STATUS.md` and `CURRENT_TASK.md` in the **same Git commit**;
4. make that commit a direct child of the HEAD that was audited;
5. move the branch by fast-forward only;
6. if the branch HEAD changed before publication, abort the transition, re-read all
   three files, and restart reconciliation.

A task/status split across separate commits is not an authoritative transition.
If `CURRENT_STATUS.md` and `CURRENT_TASK.md` disagree about phase, authority, or
allowed side effects, STOP all state-changing work.

Any detected concurrent control-plane write invalidates an in-progress quality-audit
PASS count. Reconcile first and restart the audit count from zero.

### PR metadata is evidence, not task authority

The open/closed/draft state of a PR is an observed repository fact. It does not
grant, revoke, or advance task authority by itself.

If PR metadata changes out-of-band:

- treat it as state drift;
- preserve the lifecycle classification separately from the current PR state;
- update CURRENT_STATUS with the observed fact;
- do not infer a new task or phase;
- do not reopen/close/merge another PR unless CURRENT_TASK explicitly authorizes
  that exact mutation.

The control-plane branch plus CURRENT_TASK remains task authority even if its PR is
temporarily closed or PR metadata is changed by another session.

### Live branch identity is not the same as PR head identity

When a branch is the active authority, resolve its current ref directly from the
repository branch/ref state.

Do not use a pull request's `head_sha` as a proxy for the live branch HEAD after
the PR has been closed. A closed PR can retain the head SHA from the moment it was
closed while the underlying branch continues to advance.

Therefore:

- branch authority checks use the live branch ref;
- PR head SHA is evidence about the PR snapshot;
- if they differ, record the difference instead of treating either as an implicit
  task transition.

## Evidence vocabulary

Use these labels consistently whenever project state or diagnostic conclusions are
material:

- **FACT** — directly verified by current evidence.
- **INFERENCE** — strongly supported by verified facts but not directly observed.
- **HYPOTHESIS** — plausible explanation requiring more evidence.
- **UNKNOWN** — not established by available evidence.
- **HISTORICAL** — previously reported/accepted context not verified as current.

Do not promote INFERENCE, HYPOTHESIS, UNKNOWN, or HISTORICAL state to FACT through
repetition.

## State-drift and freshness gate

Before product implementation or another side-effectful operation, revalidate the
material authority fields needed by the task. At minimum, when applicable:

- verified canonical RemoteOrbit remote identity and its fetched default branch / remote-tracking `main` (use `origin/main` only when `origin` has been verified as that remote);
- active PR and relevant PR head;
- authoritative local worktree path;
- local branch or detached state;
- exact local HEAD;
- clean/dirty/untracked state;
- installed/running runtime identity when runtime evidence matters.

If a material field differs from `CURRENT_STATUS.md`, or the snapshot cannot be
verified:

1. STOP product mutation.
2. Do not auto-reset, clean, stash, checkout, rewrite history, prune/delete a
   worktree, or reinterpret the task to hide the mismatch.
3. Reconcile read-only.
4. Update the control files only after update authority is explicit.
5. Resume only after the state is coherent again.

A remote-only session must not claim current local worktree, installed app, running
process, driver, LaunchAgent, or TCC state without local evidence.

## Project policy

1. Product behavior and explicitly accepted contracts take precedence over
   implementation convenience. Do not silently redesign user-visible behavior.
2. Keep this file limited to durable project rules. Current PR, branch, HEAD,
   incident, release candidate, and active-task status belong in
   `CURRENT_STATUS.md` or `CURRENT_TASK.md`.
3. Do not expand a bounded diagnostic or corrective task into unrelated cleanup,
   refactoring, packaging, release, or installation work without authorization.
4. Worktree/branch/PR cleanup is state-changing work. Inventory and classify first;
   delete, prune, close, merge, or rewrite only when the current task explicitly
   authorizes it.
5. Worktree retirement and branch retirement are separate lifecycle actions. A clean
   worktree may be removed while its local and remote branches are deliberately
   retained when current task authority proves the branch remains a valid history
   authority. Never treat worktree removal as implicit branch deletion.
6. If a cleanup target is already absent before the authorized mutation begins,
   classify it as reconciliation/drift; do not count the current executor as having
   performed that deletion.

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
