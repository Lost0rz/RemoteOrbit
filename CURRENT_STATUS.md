# CURRENT_STATUS

Last updated: 2026-10-29
State: CORRECTIVE_ACTIVE_2 — RO-OBSERVABILITY-039
Repository: Lost0rz/RemoteOrbit

## Repository authority

- Canonical development repository: `/Volumes/Jack-Dev/Projects/remoteorbit`.
- Verified origin: `https://github.com/Lost0rz/remoteorbit.git`.
- Audited control parent: `origin/main` at `8f71cde21df6ca1f5a831a8b5390abbfde61e9d9`.
- Active implementation branch: `codex/observability-039`.
- Active implementation worktree: `/private/tmp/remoteorbit-longterm-observability-039`.
- Previous implementation candidate HEAD: `79406f17be3fbee77b4492687f63431434b23998` (`diagnostics: classify lifecycle inconsistencies`).
- Current control HEAD before this corrective: `bcecd35e47d7a21df3f1213395970a6c8e4073da`.
- Corrected implementation candidate HEAD: `ad223e4b5f35653abe1014697cb50a87d3db05ad` (`diagnostics: correct observability audit findings`).
- Remote-delivery verification before this corrective: `origin/codex/observability-039` matched `bcecd35e47d7a21df3f1213395970a6c8e4073da`.
- PR #25 (`Release RemoteOrbit v0.2.15`) is Draft/Open/Unmerged; public release is blocked and no merge, tag, or release is authorized by this task.
- The former release-control branch `codex/release-v0.2.15` remains at `f049e6eb7f0e5625b807fba1860d04c048b638ca` in `/private/tmp/remoteorbit-release-v0.2.15-local-soak`; it is retained for provenance and is not an active writer for this task.
- The owner's MacBook Air natural-use observation reported substantial final-text omission. This records the release decision as `RELEASE_BLOCKED / SOAK_FAILED`; it does not claim a technical root cause.
- Task 038-B is terminal at `NARROWED_NOT_ESTABLISHED`; its closeout is `docs/diagnostics/2026-10-28-task-038-b-audio-continuity-closeout.md`.
- `038-C/D/E/F` remain deferred unless a later transition explicitly activates them.

## Task transition

- Previous active task: `RO-RELEASE-V0.2.15`, state `LOCAL_SOAK_ACTIVE`.
- Current active task: `RO-OBSERVABILITY-039`, state `CORRECTIVE_ACTIVE`.
- Transition parent: `79406f17be3fbee77b4492687f63431434b23998`.
- `CURRENT_STATUS.md` and `CURRENT_TASK.md` were updated together in the control-transition commit immediately following that parent.
- Corrective transition start HEAD: `24d08c64abf5832a89957241713fb50cfd60da04`.
- The independent Web audit of the pushed candidate failed with findings covering anomaly/ring semantics, incident freezing, BLE/decode trace completeness, main-queue correlation, delivery-deficit classification, crash-tolerant journal recovery, export pagination/log source, receiver evidence, and late lifecycle correlation. The corrective scope remains observability-only.
- Corrective implementation baseline for this second corrective is `ad223e4b5f35653abe1014697cb50a87d3db05ad`; this control transition is the direct child of the delivered receipt `bcecd35e47d7a21df3f1213395970a6c8e4073da`.
- The second independent-audit corrective is bounded to one shared incident identity/anchor across the existing service and AudioPipe traces, production-path material-trigger alignment, exact export-limit semantics, and ADR capacity accuracy. It must not change product/audio behavior.

## Product and runtime boundaries

- This task is diagnostics/observability infrastructure only.
- ATVV mode, BLE command/protocol semantics, codec, sample rate, AudioPipe buffering/playout, jitter behavior, gain, HID mapping, gesture semantics, Option/Control ownership, persistent sessions, driver semantics, and Doubao trigger behavior are frozen.
- Mac mini is the construction/verification host. MacBook Air is the owner-controlled natural-use acceptance host. Runtime PIDs and local runtime identity must not be compared across hosts.
- No installed Air runtime, TCC state, driver, LaunchAgent, tag, release, or PR #25 lifecycle state may be changed by this task.

## Candidate evidence

- 457 Swift tests pass; release build and `run-self-tests.sh` pass.
- `git diff --check` passes.
- Source review confirms no new AudioPipe render/BLE callback disk I/O, formatting, authority call, or diagnostic lock; BLE audio callbacks do not synchronously write the journal; normal sessions emit summary-only and anomaly traces are emitted off-path.
- Focused evidence covers true incident freeze, retention-only overwrite, actual drop, real transport-to-render stages, bounded main-queue timestamps, explicit delivery deficit, partial-tail recovery/fail-closed corruption, cursor pagination, production log allowlist, receiver usefulness, and late lifecycle correlation.

## Current next action

Implement and verify the second corrective, then push `codex/observability-039` and return the task to `WAITING_FOR_INDEPENDENT_WEB_AUDIT`. The implementation must preserve both producers' relevant evidence for one material incident, align the main-queue material threshold with classification, correct the exact export-limit flag, and make ADR capacities exact. Later MacBook Air installation/natural-use acceptance remains owner-controlled and is not performed by this task.

## Stop conditions

Stop and report if the control plane drifts, a concurrent diagnostic writer appears, a unique local work conflicts, or the requested evidence cannot be implemented without changing product audio/gesture semantics, adding invasive text capture, or adding hot-path disk/lock/allocation behavior.
