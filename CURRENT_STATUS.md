# CURRENT_STATUS

Last updated: 2026-10-29
State: WAITING_FOR_INDEPENDENT_WEB_AUDIT — RO-OBSERVABILITY-039 CANDIDATE
Repository: Lost0rz/RemoteOrbit

## Repository authority

- Canonical development repository: `/Volumes/Jack-Dev/Projects/remoteorbit`.
- Verified origin: `https://github.com/Lost0rz/remoteorbit.git`.
- Audited control parent: `origin/main` at `8f71cde21df6ca1f5a831a8b5390abbfde61e9d9`.
- Active implementation branch: `codex/observability-039`.
- Active implementation worktree: `/private/tmp/remoteorbit-longterm-observability-039`.
- Verified candidate HEAD: `373717186d3c889217a611f4e913b431ece9bd47` (`docs: document long-term observability workflow`).
- PR #25 (`Release RemoteOrbit v0.2.15`) is Draft/Open/Unmerged; public release is blocked and no merge, tag, or release is authorized by this task.
- The former release-control branch `codex/release-v0.2.15` remains at `f049e6eb7f0e5625b807fba1860d04c048b638ca` in `/private/tmp/remoteorbit-release-v0.2.15-local-soak`; it is retained for provenance and is not an active writer for this task.
- The owner's MacBook Air natural-use observation reported substantial final-text omission. This records the release decision as `RELEASE_BLOCKED / SOAK_FAILED`; it does not claim a technical root cause.
- Task 038-B is terminal at `NARROWED_NOT_ESTABLISHED`; its closeout is `docs/diagnostics/2026-10-28-task-038-b-audio-continuity-closeout.md`.
- `038-C/D/E/F` remain deferred unless a later transition explicitly activates them.

## Task transition

- Previous active task: `RO-RELEASE-V0.2.15`, state `LOCAL_SOAK_ACTIVE`.
- Current active task: `RO-OBSERVABILITY-039`, state `WAITING_FOR_INDEPENDENT_WEB_AUDIT`.
- Transition parent: `373717186d3c889217a611f4e913b431ece9bd47`.
- `CURRENT_STATUS.md` and `CURRENT_TASK.md` were updated together in the control-transition commit immediately following that parent.

## Product and runtime boundaries

- This task is diagnostics/observability infrastructure only.
- ATVV mode, BLE command/protocol semantics, codec, sample rate, AudioPipe buffering/playout, jitter behavior, gain, HID mapping, gesture semantics, Option/Control ownership, persistent sessions, driver semantics, and Doubao trigger behavior are frozen.
- Mac mini is the construction/verification host. MacBook Air is the owner-controlled natural-use acceptance host. Runtime PIDs and local runtime identity must not be compared across hosts.
- No installed Air runtime, TCC state, driver, LaunchAgent, tag, release, or PR #25 lifecycle state may be changed by this task.

## Candidate evidence

- 442 Swift tests pass; release build and `run-self-tests.sh` pass.
- `git diff --check` passes.
- Source review confirms no new AudioPipe render disk I/O, formatting, authority call, or diagnostic lock; BLE audio callbacks do not synchronously write the journal; normal sessions emit summary-only and anomaly traces are emitted off-path.
- Documentation and export tests cover L1/L2, bounded retention, archive inclusion/exclusion, receiver evidence-unavailable state, schema/query fields, and no-root-cause boundary.

## Current next action

Independent Web audit of exact candidate HEAD. Later MacBook Air installation/natural-use acceptance remains owner-controlled and is not performed by this task.

## Stop conditions

Stop and report if the control plane drifts, a concurrent diagnostic writer appears, a unique local work conflicts, or the requested evidence cannot be implemented without changing product audio/gesture semantics, adding invasive text capture, or adding hot-path disk/lock/allocation behavior.
