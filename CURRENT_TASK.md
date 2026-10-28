# RemoteOrbit Current Task

## RO-RUNTIME-RELIABILITY-038 — Task 038

- Status: WAITING_FOR_INDEPENDENT_WEB_AUDIT — 038-A CORRECTIVE-2 COMPLETE.
- Task class: RUNTIME RELIABILITY / CORRECTIVE EXECUTION.
- Repository: `Lost0rz/RemoteOrbit`.
- Canonical repository: `/Volumes/Jack-Dev/Projects/remoteorbit`.
- Task 038 is a new task. Task 037 is merged and has no further product-code mutation authority.
- Task 038 control head: `b17194c498e8b7c31495e4a95de97a21a9e0893c`.
- Implementation commit: `6f2c47d8bfc906c55d71c78c67243004708dd80a`, verified as the live head of `codex/runtime-reliability-038-a-rapid-repress`.
- Draft PR #23: `https://github.com/Lost0rz/RemoteOrbit/pull/23`; base `main`, state OPEN/Draft, not merged.
- Corrective card: `RO-RUNTIME-RELIABILITY-038-A-CORRECTIVE-1-20261028`; same Task 038-A and same PR/worktree, no new task.
- Corrective product commit: `a9f1c242582f902a64a1edc3dc17e2c83e8c08d4`, pushed and verified on the authorized branch.
- Corrective-2 card: `RO-RUNTIME-RELIABILITY-038-A-CORRECTIVE-2-20261028`; same Task 038-A and same PR/worktree, no new task, no merge authority, and no 038-B authority.
- Corrective-2 product commit: `68ed029c582c3befb12f4f9996277e96bd2ecf60`, pushed and verified on the authorized branch.

## Preserved Task 037 history and deferred acceptance debt

- Task 037 PR #22 merged into `main` at `326b56911ef883d62f1f0fda0c38fc40c06ab648` after independent Web CODE_DIFF audit PASS.
- Task 037 recorded focused tests 11/11 PASS, full `swift test` 405/405 PASS, release build PASS, and self-tests 3/3 PASS; its protected Voice/EventSuppressor/KeyInjector/BLE/audio/mapping-schema authorities remained unchanged.
- `HUMAN_UI_ACCEPTANCE: PENDING` remains intentionally deferred. The later combined human acceptance must cover Command-Space without Spotlight, Command-Shift-4 without screenshot capture, Option-A, pure modifier recording, and restoration of normal macOS shortcuts after recorder close/cancel.
- Task 038 does not rewrite that debt as PASS and does not reopen Task 037.

## Objective

Fix the confirmed rapid voice re-press admission failure with the smallest behavior change. Preserve existing SHORT/LONG semantics and all currently accepted voice behavior.

Reported incident basis: Session A receives `AUDIO_STOP` and enters drain; a new physical `HID button down: 语音键` arrives before A cleanup fully retires; `late AUDIO_START ignored during drain` is recorded; the new physical press does not establish an independent new voice session/lifecycle. This is sufficient task input for a deterministic reconstruction, not a predeclared root-cause verdict.

## Staged roadmap

- `038-A ACTIVE`: rapid re-press admission — the only implementation slice authorized now.
- `038-B DEFERRED`: audio continuity evidence.
- `038-C DEFERRED`: Option-edge authority.
- `038-D DEFERRED`: interaction latency.
- `038-E DEFERRED`: runtime telemetry/log retention.
- `038-F DEFERRED`: privacy-preserving text-output observation.

## 038-A scope and contract

- Reconstruct the represented state transition from existing runtime/state-machine code and tests.
- Add a deterministic regression where Session A is in release/drain/cleanup and a new physical voice-key down arrives before A cleanup fully retires; the new interaction must not disappear silently.
- Select the narrowest architecture-consistent admission policy: safe handoff/cancellation of stale cleanup, explicit defer/replay, or independent admission after the conflicting resource boundary clears.
- Every physical voice-key down must have an observable terminal admission result: admitted, explicitly deferred, or explicitly rejected with a concrete reason.
- Keep old-session late BLE/audio packets isolated from a newly admitted session. Stale AUDIO_START/AUDIO_STOP, drain callbacks, timers, and micClose cleanup must not terminate or corrupt the new session.
- Add focused tests for ordinary single LONG behavior, rapid press during audio drain, output drain/cleanup if distinct, stale Session-A callback isolation, and no duplicate Option-down/up or micOpen/micClose from handoff.
- Run focused tests, full Swift tests, and release build.

## 038-A execution receipt

- **REGRESSION_REPRODUCED: YES.** `testRapidRepressDuringBLEAudioDrainIsDeferredAndReplayed` deterministically places Session A across release/stream cleanup, blocks the BLE admission boundary, delivers the Session B physical down, and verifies retention/replay rather than silent disappearance.
- **ROOT_CAUSE: INFERENCE.** The coordinator could start Session B while `BLEBridge.audioStopDrainWorkItem` still blocked admission; the existing late-AUDIO_START guard could then reject the new start. This is not claimed as independent hardware/runtime causal proof.
- **POLICY:** explicit defer/replay at the audio-drain admission boundary. The new physical press remains a `PendingRepress` with its session/down metadata, and replay is scheduled only after drain retirement on a fresh main-queue turn. A release before replay cancels it.
- **STALE SESSION ISOLATION:** Session A's late tail completion cannot terminate Session B in the regression; session IDs and existing tail/output guards remain authoritative, and the new replay is separated from old cleanup callback stack execution.
- **ADMISSION OBSERVABILITY:** physical voice-key paths now emit `VOICE_PRESS_ADMISSION` with `admitted`, `deferred`, or `rejected` and a concrete reason.
- **TESTS:** VoicePressCoordinatorTests 39/39 PASS; BLEBridgeTests 14/14 PASS; full `swift test` 406/406 PASS; `swift build -c release` PASS; `git diff --check` PASS.
- **CHANGED FILES:** `remote-orbit/Sources/RemoteOrbit/BLEBridge.swift`, `remote-orbit/Sources/RemoteOrbit/main.swift`, and `remote-orbit/Tests/RemoteOrbitTests/VoicePressCoordinatorTests.swift` only.
- **PROTECTED BOUNDARIES:** no AudioPipe, Adaptive Playout, BLE codec/timing, AUDIO_STOP reason interpretation, Option/noOptionEdge, text Accessibility, DiagnosticAuthority, logging retention/cadence, unrelated mappings, driver, packaging, installation, permission, or release changes.

## 038-A corrective delta — lifecycle completion

- The independent Web audit reports a possible stranded state: Session B waits on `audioDrain`, while a BLE transport reset/disconnect cancels and clears `audioStopDrainWorkItem` before normal drain completion, potentially bypassing the admission-available callback.
- This same-task corrective authorizes only deterministic reproduction of that lifecycle and the narrowest fix if reproduced.
- Required invariant: every transition of the BLE admission barrier from BLOCKED to CLEAR must resolve every retained press waiting specifically on that barrier as admitted/replayed or explicitly cancelled/rejected with a concrete reason.
- Required evidence: normal drain replay exactly once; cancelled/reset drain reaches a terminal B state; physical-up before retirement prevents replay; stale/cancelled Session A completion cannot mutate B; ordinary LONG remains unchanged; no duplicate mic or Option edges.
- **AUDIT_FINDING_REPRODUCED: YES.** The real `BLEBridge.clearTransportState` reset path cleared the active drain barrier without notifying the coordinator; B remained pending and no transport preparation occurred.
- **ROOT_CAUSE: FACT.** Normal `finishAudioStopAfterDrain` emitted the admission-available callback, but reset/cancellation cleanup did not.
- **SELECTED_LIFECYCLE_OWNER:** `BLEBridge`, at the shared barrier-retirement points. `clearTransportState` and normal completion each notify once after their cleanup/connection callbacks; stale completion is ignored when the work item is already cleared.
- **BARRIER_RETIREMENT_POLICY:** any active drain work item cleared by normal completion or reset/cancellation schedules one admission-available notification. The coordinator retains the existing replay policy; physical-up before replay cancels the retained press.
- **WHY_DEFERRED_REPRESS_CANNOT_REMAIN_STRANDED:** the only transitions that clear the BLE barrier now notify the coordinator; the coordinator either replays once when idle or drops a released press, and a cancelled old work item cannot emit a second notification.
- **NORMAL_DRAIN_REPLAY:** `testNormalAudioDrainCompletionReplaysDeferredRepressExactlyOnce` passes; one notification and one preparation, with a second stale completion producing neither.
- **CANCELLED_DRAIN:** `testCanceledAudioDrainCompletionAfterResetCannotReplayResolvedPressTwice` passes through reset cleanup, replays once, and rejects the later canceled completion as a no-op.
- **STALE CALLBACK / RELEASE:** the canceled-completion test and `testPhysicalUpBeforeAudioDrainRetirementDoesNotReplayDeferredRepress` pass; existing stale Session A and ordinary LONG tests also pass.
- **DUPLICATE MIC/OPTION GUARD:** replay preparation count is one, reset/completion notification count is one, and the lifecycle tests preserve the original `[Option-down, Option-up]` pair; existing repeated mic-open and Option ownership tests remain green.
- **FOCUSED TESTS:** VoicePressCoordinatorTests 39/39 PASS; BLEBridgeTests 17/17 PASS.
- **FULL SWIFT TEST:** 409/409 PASS. **RELEASE BUILD:** PASS. **DIFF CHECK:** PASS.
- **CORRECTIVE CHANGED FILES:** `remote-orbit/Sources/RemoteOrbit/BLEBridge.swift` and `remote-orbit/Tests/RemoteOrbitTests/BLEBridgeTests.swift`.

## 038-A corrective-2 delta — explicit stop lifecycle

- Corrective-2 start HEAD: `4f7d32e6768a60a474c8b20f1afde7d45ddd4ec6`, verified as the live head of the authorized branch before this paired control transition.
- Reproduce a RED regression through the production `BLEBridge.stop()` lifecycle while Session B waits on `.audioDrain`; do not satisfy this slice only through `resetTransportForTesting()`.
- Audit every production transition of `audioStopDrainWorkItem` from non-nil to nil and classify normal drain retirement, reset/disconnect, explicit stop, stale/canceled replacement, and test-only setup/cleanup.
- Implement the narrowest central lifecycle-owner correction so every production `BLOCKED → CLEAR` transition either retires through one authoritative mechanism or is proven unable to coexist with a deferred audio-drain repress.
- Preserve exactly-once retirement notifications, release-before-retirement cancellation, stale Session-A isolation, and existing mic/Option ownership. If the production stop path cannot coexist with a deferred press, or centralization requires broader transport redesign, stop and report the exact proof/conflict.
- Required verification: VoicePressCoordinator focused suite, BLEBridge focused suite, full `swift test`, `swift build -c release`, and `git diff --check`; then return to `WAITING_FOR_INDEPENDENT_WEB_AUDIT`.

## 038-A corrective-2 execution receipt

- **AUDIT_FINDING_REPRODUCED: YES.** The production-stop RED used `BLEBridge.stop()` itself while Session B waited on `.audioDrain`; before the fix, the barrier cleared with no admission notification, replay, or transport preparation.
- **PRODUCTION_STOP_PATH_REPRODUCTION: YES.** The new `testExplicitTransportStopRetiresAudioDrainBarrierAndReplaysDeferredRepressExactlyOnce` fails on the pre-fix implementation and passes after the correction.
- **ALL_BARRIER_CLEAR_SITES:** production clearing is centralized in `retireAudioStopDrainBarrier()`. `stop()` no longer clears independently; `clearTransportState()` and `finishAudioStopAfterDrain()` delegate to the helper; the accepted `AUDIO_START` path has no bypass clear; test setup remains explicitly test-only.
- **ROOT_CAUSE: FACT.** `stop()` cleared `audioStopDrainWorkItem` before `clearTransportState()` could observe and retire it, bypassing the only admission callback.
- **SELECTED_LIFECYCLE_OWNER:** `BLEBridge.retireAudioStopDrainBarrier()`; it cancels/nils only an active barrier and queues exactly one admission-available callback for that transition.
- **BARRIER_RETIREMENT_INVARIANT:** every production `BLOCKED → CLEAR` path resolves a retained `.audioDrain` press exactly once as replay/admit when still held, or cancellation when released; stale completion after clear is a no-op.
- **NORMAL_DRAIN_EVIDENCE:** `testNormalAudioDrainCompletionReplaysDeferredRepressExactlyOnce` PASS; one notification and one preparation, stale completion adds zero.
- **RESET_DISCONNECT_EVIDENCE:** `testCanceledAudioDrainCompletionAfterResetCannotReplayResolvedPressTwice` PASS; reset clears and replays once, canceled completion adds zero.
- **PRODUCTION_STOP_EVIDENCE:** `testExplicitTransportStopRetiresAudioDrainBarrierAndReplaysDeferredRepressExactlyOnce` PASS; real `stop()` clears and replays once, repeated stop adds zero.
- **STALE_COMPLETION_EVIDENCE:** normal, reset, and production-stop tests invoke the stale completion after retirement; notification and preparation counts remain unchanged.
- **RELEASE_BEFORE_RETIREMENT_EVIDENCE:** `testPhysicalUpBeforeAudioDrainRetirementDoesNotReplayDeferredRepress` PASS; the retained B is cleared without replay or preparation.
- **EXACTLY_ONCE_EVIDENCE:** normal, reset, stop, repeated stop/reset, and stale completion paths retain one notification and one preparation at most; no duplicate Option pair is observed in the lifecycle harness.
- **MIC_OPTION_OWNERSHIP_EVIDENCE:** replay path preparation count is one and the lifecycle harness preserves `[Option-down, Option-up]`; all existing mic/Option and ordinary LONG tests remain green. No coordinator, micOpen/micClose, Option-edge, or SHORT/LONG code changed.
- **FOCUSED TESTS:** `VoicePressCoordinatorTests` 39/39 PASS; `BLEBridgeTests` 18/18 PASS.
- **FULL SWIFT TEST:** 410/410 PASS. **RELEASE BUILD:** PASS. **DIFF CHECK:** PASS.
- **CHANGED FILES:** `remote-orbit/Sources/RemoteOrbit/BLEBridge.swift` and `remote-orbit/Tests/RemoteOrbitTests/BLEBridgeTests.swift` only.

## Non-goals

- Do not tune AudioPipe buffers.
- Do not introduce Adaptive Playout changes.
- Do not change BLE codec or packet timing.
- Do not reinterpret `AUDIO_STOP reason=0x02`.
- Do not repair the Option/noOptionEdge path.
- Do not add text-output Accessibility observers.
- Do not redesign DiagnosticAuthority.
- Do not change logging retention or AUDIO-METER cadence.
- Do not modify unrelated button mappings or gesture semantics.
- Do not bundle automatic mapping-backup cleanup.
- Do not perform opportunistic refactors.

## Authorized identity and lifecycle

- Authorized implementation branch: `codex/runtime-reliability-038-a-rapid-repress`.
- Authorized implementation worktree: `/private/tmp/remoteorbit-runtime-reliability-038-a-rapid-repress`.
- Implementation start HEAD: `b17194c498e8b7c31495e4a95de97a21a9e0893c`.
- Product implementation commit: `6f2c47d8bfc906c55d71c78c67243004708dd80a`; corrective product commit: `a9f1c242582f902a64a1edc3dc17e2c83e8c08d4`. Control-plane handoff commits follow them; the worktree is clean and the remote branch is aligned with the final control record.
- The exact branch, worktree, start HEAD, control head, and clean state are registered by this paired control commit before product mutation.
- Preserve the retained Task 037 worktree/branch as historical delivery state; do not use it as the Task 038 writer.
- Do not merge unless a later repository-governance transition explicitly authorizes merge. Do not install, package, release, change permissions, delete branches, or delete worktrees.

## Stop conditions

- If the deterministic regression cannot reproduce the state-machine failure represented by the runtime evidence, stop with `ROOT_CAUSE_NOT_REPRODUCED`; do not invent a fix.
- If the fix requires changing established SHORT/LONG semantics, stop and return the conflict.
- If fresh repository authority contradicts this card, repository authority wins; report the mismatch rather than overriding it.
- Stop for unexpected local work, another active writer/PR, scope expansion, unrelated test failure that cannot be separated, or unverifiable remote delivery identity.

## Next action

Independent Web audit of Draft PR #23. Do not merge, install, package, release, change permissions, or retire branches/worktrees. `HUMAN_UI_ACCEPTANCE: PENDING`; Task 037 deferred human acceptance remains unchanged.
