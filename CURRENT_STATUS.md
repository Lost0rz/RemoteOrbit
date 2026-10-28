# CURRENT_STATUS

Last updated: 2026-10-28
State: WAITING_FOR_INDEPENDENT_WEB_AUDIT — TASK 038-A CORRECTIVE-1 COMPLETE
Repository: Lost0rz/RemoteOrbit

## Repository authority

- Canonical development repository: `/Volumes/Jack-Dev/Projects/remoteorbit`.
- Canonical branch: `main`.
- Verified origin: `https://github.com/Lost0rz/remoteorbit.git`.
- Fresh live `main`, local `main`, and `origin/main` were aligned at `baa6d4dd655d862e0a70fbcb93410909e49a0146` before the Task 038 activation commit.
- Task 038 activation control head: `b17194c498e8b7c31495e4a95de97a21a9e0893c`, pushed and verified on live `main`.
- The canonical worktree was clean before this Task 038 control transition.
- Task 037 PR #22 is merged at `326b56911ef883d62f1f0fda0c38fc40c06ab648`; its human acceptance debt remains pending and is carried forward below.
- Task 038-A product implementation commit is `6f2c47d8bfc906c55d71c78c67243004708dd80a`, pushed and verified in the authorized branch history; later commits are control-plane handoff records.
- Draft PR #23 is open at `https://github.com/Lost0rz/RemoteOrbit/pull/23`, base `main`; it is not merged.
- Corrective card `RO-RUNTIME-RELIABILITY-038-A-CORRECTIVE-1-20261028` explicitly reopens only the 038-A lifecycle-completion slice on PR #23; it does not create a new product task or authorize merge.
- Corrective product commit is `a9f1c242582f902a64a1edc3dc17e2c83e8c08d4`, pushed and verified on the authorized branch.
- The retained Task 037 implementation worktree `/private/tmp/remoteorbit-shortcut-recorder-exclusive-capture-v1` is not an active Task 038 writer and is not modified by this task.

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
- Deterministic regression reproduced the represented admission boundary in `testRapidRepressDuringBLEAudioDrainIsDeferredAndReplayed`.
- Root-cause classification: **INFERENCE** — the coordinator could begin a new logical press while BLE's `audioStopDrainWorkItem` still blocked admission, allowing the new start to reach the existing late-AUDIO_START rejection. This is source/test reconstruction, not independent hardware/runtime causal proof.
- Selected policy: explicitly defer the physical press at the BLE audio-drain boundary, retain its session/down metadata, and replay asynchronously after the drain clears. The press is not silently discarded; key-up before replay cancels the retained press.
- Stale-session evidence: the new test invokes a late Session A tail completion after Session B admission without changing Session B or producing a duplicate Option edge; existing session/tail guards remain in force, and the new replay occurs after old drain cleanup on a fresh main-queue turn.
- Focused evidence: `VoicePressCoordinatorTests` 39/39 PASS; `BLEBridgeTests` 14/14 PASS. Full `swift test`: 406/406 PASS. `swift build -c release`: PASS. `git diff --check`: PASS.
- Changed files are limited to `remote-orbit/Sources/RemoteOrbit/BLEBridge.swift`, `remote-orbit/Sources/RemoteOrbit/main.swift`, and `remote-orbit/Tests/RemoteOrbitTests/VoicePressCoordinatorTests.swift`; no AudioPipe, codec/timing, Option-edge, Accessibility, DiagnosticAuthority, retention, driver, packaging, install, or release boundary changed.
- Target final development state is now `WAITING_FOR_INDEPENDENT_WEB_AUDIT`; do not merge unless a later governance transition authorizes it.
- Corrective audit finding reproduced: `clearTransportState` cancelled and cleared `audioStopDrainWorkItem` while B remained `PendingRepress(audioDrain)` and no admission callback or transport preparation occurred.
- Corrective root cause: **FACT** — the BLE reset/cancellation path owned barrier cleanup but did not notify the coordinator; the normal completion path was the only notifier.
- Corrective lifecycle owner: `BLEBridge` now owns the BLOCKED → CLEAR notification in both `clearTransportState` cancellation/reset and `finishAudioStopAfterDrain` normal completion. Notification is queued after connection/streaming callbacks and is guarded against stale/cancelled duplicate completion.
- Corrective evidence: normal drain replay exactly once; reset/cancellation replay exactly once; physical-up before retirement cancels without replay; stale cancelled Session A completion produces no second replay; existing ordinary LONG and Option/mic ownership tests remain green.
- Corrective focused evidence: `BLEBridgeTests` 17/17 PASS; `VoicePressCoordinatorTests` 39/39 PASS. Full `swift test`: 409/409 PASS. `swift build -c release`: PASS. `git diff --check`: PASS.
- Corrective changed files: `remote-orbit/Sources/RemoteOrbit/BLEBridge.swift` and `remote-orbit/Tests/RemoteOrbitTests/BLEBridgeTests.swift`; no 038-B or unrelated boundary changed.
- `HUMAN_UI_ACCEPTANCE: PENDING`; no UI change is expected in 038-A.

## Current phase and next action

- Phase: CORRECTIVE COMPLETE — WAITING FOR INDEPENDENT WEB AUDIT; 038-A lifecycle completion only.
- Next action: independent Web audit of Draft PR #23. No further product mutation, merge, install, package, release, permission change, or worktree/branch retirement is authorized by this handoff.
- Single active Task 038-A product writer: `/private/tmp/remoteorbit-runtime-reliability-038-a-rapid-repress`. The retained Task 037 worktree is historical and non-authoritative for 038.

## Task 038-A boundaries

- Preserve existing SHORT/LONG semantics and accepted voice behavior.
- Do not tune AudioPipe buffers, change Adaptive Playout, BLE codec or packet timing, reinterpret `AUDIO_STOP reason=0x02`, repair Option/noOptionEdge, add text-output Accessibility observers, redesign DiagnosticAuthority, change logging retention/cadence, modify unrelated mappings, bundle backup cleanup, or perform opportunistic refactors.
- Every new physical voice-key down must have an observable terminal admission result: admitted, explicitly deferred, or explicitly rejected with a concrete reason.
- Old-session AUDIO_START/AUDIO_STOP, drain callbacks, timers, and micClose cleanup must not mutate a newly admitted session.

## Required closeout evidence

- Deterministic regression reproduced the represented rapid re-press state transition and is recorded above.
- Focused Task 038-A tests, full `swift test`, and `swift build -c release` are recorded against implementation commit `6f2c47d8bfc906c55d71c78c67243004708dd80a`.
- `HUMAN_UI_ACCEPTANCE: PENDING`; 038-A has no intended UI change, and the deferred Task 037 human acceptance debt remains unchanged.
- `MERGE_STATUS: NOT_MERGED`; independent Web audit remains outstanding. Do not install, package, release, change permissions, or retire branches/worktrees.
- `AUDIT_FINDING_REPRODUCED: YES`; the corrective invariant is covered by real BLEBridge reset/completion lifecycle seams, not only a coordinator Boolean mock.
- Corrective stop boundary was not invoked; the missing reset-path notification was reproduced and fixed without changing SHORT/LONG or persistent-session semantics.
