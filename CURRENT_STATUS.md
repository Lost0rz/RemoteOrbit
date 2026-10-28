# CURRENT_STATUS

Last updated: 2026-10-28
State: ACTIVE — TASK 038-A RAPID REPRESS ADMISSION
Repository: Lost0rz/RemoteOrbit

## Repository authority

- Canonical development repository: `/Volumes/Jack-Dev/Projects/remoteorbit`.
- Canonical branch: `main`.
- Verified origin: `https://github.com/Lost0rz/remoteorbit.git`.
- Fresh live `main`, local `main`, and `origin/main` were aligned at `baa6d4dd655d862e0a70fbcb93410909e49a0146` before the Task 038 activation commit.
- Task 038 activation control head: `b17194c498e8b7c31495e4a95de97a21a9e0893c`, pushed and verified on live `main`.
- The canonical worktree was clean before this Task 038 control transition.
- Task 037 PR #22 is merged at `326b56911ef883d62f1f0fda0c38fc40c06ab648`; its human acceptance debt remains pending and is carried forward below.
- No open PR exists for the new task. The retained Task 037 implementation worktree `/private/tmp/remoteorbit-shortcut-recorder-exclusive-capture-v1` is not an active Task 038 writer and is not modified by this task.

## Historical accepted baseline

- Task 036 remains CLOSED — REPOSITORY LIFECYCLE CLOSEOUT WEB-ACCEPTED.
- Task 037 remains MERGED — HUMAN ACCEPTANCE DEFERRED.
- Task 037 delivered dedicated shortcut-recorder CGEventTap ownership and its recorded focused/full/build/self-test evidence; no Task 037 source or acceptance claim is reopened by Task 038.
- `HUMAN_UI_ACCEPTANCE: PENDING` for the deferred Task 037 cases: Command-Space, Command-Shift-4, Option-A, pure modifier recording, and restoration of normal macOS shortcut behavior after recorder close/cancel.

## Task 038 — runtime reliability roadmap

- Task ID: `RO-RUNTIME-RELIABILITY-038`.
- Objective: fix the confirmed rapid voice re-press admission failure with the smallest behavior change while preserving established SHORT/LONG semantics and accepted voice behavior.
- Staged roadmap:
  - `038-A ACTIVE`: rapid re-press admission.
  - `038-B DEFERRED`: audio continuity evidence.
  - `038-C DEFERRED`: Option-edge authority.
  - `038-D DEFERRED`: interaction latency.
  - `038-E DEFERRED`: runtime telemetry/log retention.
  - `038-F DEFERRED`: privacy-preserving text-output observation.
- Only 038-A implementation is authorized in this transition. No unrelated stage is opened by implication.
- Reported incident basis: a new physical voice-key down during the previous session's AUDIO_STOP/drain window was followed by `late AUDIO_START ignored during drain`; the new interaction did not establish an independent lifecycle. This runtime report is task input and still requires deterministic source/test reconstruction.
- Authorized implementation branch: `codex/runtime-reliability-038-a-rapid-repress`.
- Authorized implementation worktree: `/private/tmp/remoteorbit-runtime-reliability-038-a-rapid-repress`.
- Implementation start HEAD: `b17194c498e8b7c31495e4a95de97a21a9e0893c`.
- Worktree registration: this paired control commit; worktree was clean before product mutation.
- Target final development state: `WAITING_FOR_INDEPENDENT_WEB_AUDIT` unless the required deterministic regression cannot reproduce the represented failure, in which case stop with `ROOT_CAUSE_NOT_REPRODUCED`.
- `HUMAN_UI_ACCEPTANCE: PENDING`; no UI change is expected in 038-A.

## Current phase and next action

- Phase: IMPLEMENTATION ACTIVE — 038-A only.
- Next authorized action: add the deterministic RED regression in the registered implementation worktree, then implement the smallest admission fix if the failure reproduces.
- Single active Task 038-A product writer: `/private/tmp/remoteorbit-runtime-reliability-038-a-rapid-repress`. The retained Task 037 worktree is historical and non-authoritative for 038.

## Task 038-A boundaries

- Preserve existing SHORT/LONG semantics and accepted voice behavior.
- Do not tune AudioPipe buffers, change Adaptive Playout, BLE codec or packet timing, reinterpret `AUDIO_STOP reason=0x02`, repair Option/noOptionEdge, add text-output Accessibility observers, redesign DiagnosticAuthority, change logging retention/cadence, modify unrelated mappings, bundle backup cleanup, or perform opportunistic refactors.
- Every new physical voice-key down must have an observable terminal admission result: admitted, explicitly deferred, or explicitly rejected with a concrete reason.
- Old-session AUDIO_START/AUDIO_STOP, drain callbacks, timers, and micClose cleanup must not mutate a newly admitted session.

## Required closeout evidence

- Deterministic regression reproduces the represented rapid re-press state transition; otherwise stop with `ROOT_CAUSE_NOT_REPRODUCED` and do not invent a fix.
- Focused Task 038-A tests, full `swift test`, and `swift build -c release` must be recorded against the implementation identity.
- No merge is authorized by this task card. Do not install, package, release, change permissions, or retire branches/worktrees.
