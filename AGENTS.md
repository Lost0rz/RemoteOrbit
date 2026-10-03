# RemoteOrbit Agent Instructions

This file contains durable project rules. It must not be used as a live status log.

## Mandatory session startup

Before changing code, packaging, runtime configuration, diagnostics, or project state:

1. Read `AGENTS.md`.
2. Read `CURRENT_STATUS.md`.
3. Read `CURRENT_TASK.md`.
4. Verify the actual Git state relevant to the task.
5. Run the state-drift gate described below.

Also read [README.md](README.md), [SETUP_NOTES.md](SETUP_NOTES.md), and subsystem-specific documents when they are relevant.

Chat history, model memory, prior handoff prose, and local assumptions are context only. They are not authoritative project state.

## Project authority model

The three root control files have separate responsibilities:

- `AGENTS.md`: durable engineering and process rules.
- `CURRENT_STATUS.md`: the current verified project snapshot.
- `CURRENT_TASK.md`: the single currently authorized task.

Do not duplicate volatile branch, PR, HEAD, incident, release-candidate, installed-build, or worktree facts in `AGENTS.md`.

When sources disagree, prefer direct evidence in this order:

1. observed runtime identity for runtime claims;
2. actual local Git/worktree state for local checkout claims;
3. current GitHub remote state for remote branch/PR claims;
4. the latest verified state recorded in `CURRENT_STATUS.md`;
5. historical reports, chat transcripts, or model memory.

A lower-ranked source must never silently overwrite a higher-ranked source. Record the discrepancy and stop when it changes task authority.

## One-active-task rule

Only one task may be ACTIVE in `CURRENT_TASK.md`.

A task may authorize bounded subtasks, but unrelated bug fixes, refactors, logging changes, packaging, release work, cleanup, or experiments require a new task or explicit amendment to the current task.

Do not continue a previous task merely because a branch, PR, worktree, or chat still exists.

## State-drift gate

Before implementation or any side-effectful operation, compare the expected state in `CURRENT_STATUS.md` and `CURRENT_TASK.md` with actual state.

At minimum verify, when applicable:

- repository;
- remote default branch and remote main HEAD;
- local authoritative worktree path;
- local branch or detached state;
- local HEAD;
- clean/dirty state;
- active PR and PR head SHA;
- installed/running build identity when runtime evidence matters.

If a material mismatch exists:

- STOP product work;
- do not auto-reset, auto-clean, auto-stash, auto-checkout, rewrite history, delete worktrees, or reinterpret the task;
- record or report the mismatch;
- reconcile project state before continuing.

Unknown remains unknown. A remote-only session must not claim current local worktree, installed app, running process, driver, or TCC state without local evidence.

## Project policy

1. Product behavior and explicitly accepted contracts take precedence over implementation convenience. Do not silently redesign user-visible behavior.
2. Keep this file limited to durable project rules. Current PR, branch, HEAD, incident, release candidate, and active-task status belong in the state/task records.
3. Do not expand a bounded diagnostic or corrective task into unrelated cleanup, refactoring, packaging, release, installation, or worktree maintenance without authorization.
4. Prefer one authoritative implementation/investigation line at a time. Parallel branches may exist as evidence or frozen experiments, but their role must be recorded in `CURRENT_STATUS.md`.
5. Never treat an open PR or existing worktree as active merely because it still exists.

## Evidence vocabulary

Use these labels consistently when state or diagnosis is material:

- **FACT**: directly verified by current evidence.
- **INFERENCE**: conclusion strongly supported by facts but not directly observed.
- **HYPOTHESIS**: plausible explanation requiring further evidence.
- **UNKNOWN**: not established by available evidence.

Do not promote INFERENCE or HYPOTHESIS to FACT through repetition.

## Runtime identity and evidence

6. Treat these as distinct identities unless proven otherwise:
   - source checkout and source HEAD;
   - built executable or app bundle;
   - installed `/Applications/RemoteOrbit.app`;
   - running process;
   - installed `RemoteOrbitAudio.driver`;
   - LaunchAgent/runtime configuration.
7. Any runtime conclusion that depends on identity must report the material identity evidence, such as source HEAD, executable path/hash, app version/build, Bundle ID/code identity, installed component version, or running process.
8. A Terminal/helper permission result does not prove the RemoteOrbit product process has the same TCC/Accessibility/Input Monitoring/Event access. Product permission claims require evidence from the product process or an equivalent identity-preserving check.
9. Symptom recovery, restart success, reload success, or temporary stability does not by itself establish root cause. Separate observed recovery from causal proof.
10. Distinguish verified facts, plausible mechanisms, and uninspected layers. Unknown must remain unknown.

## Forensic and side-effect discipline

11. During an incident/forensic capture, preserve the observed runtime by default. Do not rebuild, reinstall, replace the app, change TCC permissions, alter LaunchAgents, replace/reinstall the HAL driver, restart CoreAudio, or change diagnostic behavior unless the task explicitly authorizes that mutation.
12. Packaging, installation, driver replacement, `coreaudiod` restart, TCC changes, and LaunchAgent changes are side-effectful operations. An audit, diagnosis, or source-only task does not authorize them.
13. Do not stack a speculative production fix on top of unresolved diagnostic work without first reconciling what is observation-only, experimental, frozen evidence, and intended for production.
14. Worktree, branch, and PR cleanup is also a state-changing operation. Inventory and classify first; delete or close only when the current task explicitly authorizes it.

## Validation

15. Validate the changed boundary with the smallest sufficient evidence. Protocol, audio, HID, packaging, permission, source, and installed-runtime claims may require different validation; one class of evidence must not be substituted for another.
16. Tests should establish contract behavior or regression protection, not merely increase test count. Use broader regression only when the affected boundary or requested acceptance criteria justify it.
17. Before recommending merge or release, state remaining uncertainty and any runtime behavior that was not directly validated.
18. Documentation-only governance changes must still be checked for internal consistency against current remote state and must not assert unverifiable local/runtime facts.

## Commit, PR, and merge discipline

19. Every active implementation line should have a clear purpose and disposition in `CURRENT_STATUS.md`.
20. A PR may be OPEN or DRAFT without being ACTIVE. Activity is granted only by `CURRENT_TASK.md` / `CURRENT_STATUS.md`.
21. Before merge, verify the PR head SHA, base, intended scope, validation level, unresolved uncertainties, and whether state files need updating as part of the same transition.
22. After a merge or authoritative branch transition, update `CURRENT_STATUS.md` before starting the next product task.
23. Do not release merely because a PR merged. Release requires explicit authorization and release-specific validation.

## Handoff contract

At the end of any task that changes project state, update the control files as needed so a fresh assistant can determine, without chat history:

- remote main and exact SHA;
- authoritative local worktree if locally verified;
- active branch / PR and exact head SHA;
- installed/running build identity if relevant and verified;
- confirmed facts;
- unresolved unknowns;
- frozen/superseded work;
- the single active task;
- the next permitted action;
- explicitly forbidden actions.

If those answers cannot be established, the handoff must say so explicitly rather than guess.
