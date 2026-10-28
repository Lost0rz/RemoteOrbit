# RemoteOrbit Current Task

## RO-RUNTIME-RELIABILITY-038 — Task 038

- Status: ACTIVE — 038-A RAPID REPRESS ADMISSION.
- Task class: RUNTIME RELIABILITY / CORRECTIVE EXECUTION.
- Repository: `Lost0rz/RemoteOrbit`.
- Canonical repository: `/Volumes/Jack-Dev/Projects/remoteorbit`.
- Task 038 is a new task. Task 037 is merged and has no further product-code mutation authority.
- Task 038 control head: `b17194c498e8b7c31495e4a95de97a21a9e0893c`.

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
- The exact branch, worktree, start HEAD, control head, and clean state are registered by this paired control commit before product mutation.
- Preserve the retained Task 037 worktree/branch as historical delivery state; do not use it as the Task 038 writer.
- Do not merge unless a later repository-governance transition explicitly authorizes merge. Do not install, package, release, change permissions, delete branches, or delete worktrees.

## Stop conditions

- If the deterministic regression cannot reproduce the state-machine failure represented by the runtime evidence, stop with `ROOT_CAUSE_NOT_REPRODUCED`; do not invent a fix.
- If the fix requires changing established SHORT/LONG semantics, stop and return the conflict.
- If fresh repository authority contradicts this card, repository authority wins; report the mismatch rather than overriding it.
- Stop for unexpected local work, another active writer/PR, scope expansion, unrelated test failure that cannot be separated, or unverifiable remote delivery identity.

## Next action

Add the deterministic regression as the first product-boundary change in the registered Task 038-A worktree. Do not predeclare PASS, CLOSED, merge readiness, or root cause.
