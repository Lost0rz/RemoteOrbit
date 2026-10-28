# RemoteOrbit Current Task

## RO-SHORTCUT-RECORDER-EXCLUSIVE-CAPTURE-037 — Task 037

- Status: ACTIVE — IMPLEMENTATION ACTIVE.
- Task class: CORRECTIVE / EXECUTION.
- Repository: `Lost0rz/RemoteOrbit`.
- Canonical repository: `/Volumes/Jack-Dev/Projects/remoteorbit`.
- Audited activation parent: `ea41f4ca93674fd70b9730c272eb3e2abee4d768`.
- Task 037 control head: `ef09f80813cd868ede8a63bf3e9724fe46b43b0f`.

## Objective

Fix the custom shortcut recorder so system/global shortcuts can be recorded without executing their existing macOS action during recording. The recorder must exclusively own one complete physical keyboard gesture from the first swallowed edge through final release.

Required product examples:

- Command-Space records Command-Space without opening Spotlight.
- Command-Shift-4 records Command-Shift-4 without initiating screenshot capture.

This is a shortcut-recorder event-ownership corrective. It is not a Voice corrective or a general keyboard-remapping redesign.

## Scope

- Dedicated `ShortcutCaptureMonitor` using an active `CGEventTap` at `.cghidEventTap`, `.headInsertEventTap`, with `.defaultTap` and keyDown/keyUp/flagsChanged interest.
- Neutral-start gating, complete physical suppression, synthetic-event pass-through, chord freeze, release-boundary commit, pure-modifier support, autorepeat suppression, cancellation drain, tap failure reporting, and state reset.
- Shortcut recorder UI/controller integration in `SettingsView.swift`; preview on chord freeze and `onRecord` only after complete release.
- Focused state-machine tests and required regression/build/self-test verification.

## Non-goals and protected authorities

- No Voice behavior, BLE/audio, audio-driver, packaging/install/release, application-template, mapping-store/schema, or unrelated cleanup changes.
- Do not extend or semantically redesign `EventSuppressor`.
- Do not modify `KeyInjector` output/injection semantics or `KeyInjector.syntheticMarker`.
- Do not modify `VoiceOptionTrigger.swift`, `VoiceTriggerKey.swift`, `BLEBridge.swift`, audio/driver code, or mapping persistence/schema.
- Do not use NSEvent global/local monitoring as the suppression mechanism and do not add a local-monitor fallback.
- Do not request or change TCC/privacy permissions.

## Authorized identity and lifecycle

- Authorized branch: `codex/shortcut-recorder-exclusive-capture-v1`.
- Authorized worktree: `/private/tmp/remoteorbit-shortcut-recorder-exclusive-capture-v1`.
- Implementation start HEAD: `ef09f80813cd868ede8a63bf3e9724fe46b43b0f`.
- The exact branch, worktree, start HEAD, canonical control head, and clean state are registered by this paired control commit before product mutation.
- Push the authorized branch and open exactly one Draft PR against `main` only after required implementation verification passes.
- Do not merge, install `/Applications/RemoteOrbit.app`, package/release a DMG, delete the branch, or delete the worktree.

## Behavioral contract

1. State flow conceptually supports `WAITING_FOR_NEUTRAL → ARMED → CHORD_FROZEN → DRAINING_RELEASE → COMMIT`.
2. If Command/Control/Option/Shift/Fn is held when recording begins, install the boundary but wait for neutral; do not infer a half-existing chord.
3. While armed/capturing, swallow all owned physical keyDown, autorepeat, keyUp, modifier down, and modifier-release edges by returning nil from the active tap.
4. Events carrying `KeyInjector.syntheticMarker` pass through unchanged and never alter capture state.
5. Freeze the first valid non-repeat primary keyDown into the existing `KeyChord` representation; update preview but do not call `onRecord` yet.
6. Commit only after the primary key and every participating modifier have been released; then terminate capture and dismiss as existing flow requires.
7. Preserve pure Command/Control/Option/Shift/Fn recording after a complete press/release gesture.
8. Cancel/Clear/dismiss during an owned gesture enters drain-only termination and removes the tap only after neutral; no swallowed-down/leaked-up sequence.
9. Tap creation/health failure reports a clear recorder error, records nothing, and never falls back to NSEvent local monitoring.

## Expected files

New:

- `remote-orbit/Sources/RemoteOrbit/KeyMapping/ShortcutCaptureMonitor.swift`
- `remote-orbit/Tests/RemoteOrbitTests/ShortcutCaptureMonitorTests.swift`

Modified:

- `remote-orbit/Sources/RemoteOrbit/KeyMapping/SettingsView.swift`

Control files:

- `CURRENT_STATUS.md`
- `CURRENT_TASK.md`

`AGENTS.md` must remain unchanged.

## Verification contract

From `remote-orbit` in the implementation worktree:

```text
swift test --filter ShortcutCaptureMonitorTests
swift test
swift build -c release
./run-self-tests.sh
```

Record exact results/counts. Source-diff verification must prove `EventSuppressor.swift`, `KeyInjector.swift`, Voice sources, audio/driver sources, and mapping persistence/schema are unchanged. Synthetic injection is not proof of real macOS system-shortcut suppression.

Required focused cases include plain key, Command-Space, Command-Shift-4 exact chord, Option-A, pure modifier, autorepeat, synthetic marker pass-through, pre-held modifier neutral wait, cancellation drain, and session reset; tap-factory failure must prove explicit failure without local-monitor fallback when that abstraction is used.

## Acceptance and stop conditions

- Local automated verification is implementation evidence only; `HUMAN_UI_ACCEPTANCE: PENDING` until the user explicitly reports PASS/FAIL for real Command-Space, Command-Shift-4, Option-A, pure modifier, and post-cancel restoration behavior.
- Target final development state: `WAITING_FOR_INDEPENDENT_WEB_AUDIT`.
- Stop for stale/inconsistent control plane, unexpected local work, another active writer/branch/worktree/PR, scope expansion, inability to enforce the CGEventTap boundary, unrelated test failure that cannot be separated, or unverifiable remote delivery identity.
- On any stop, preserve evidence and report the exact reason; do not reset, clean, stash, prune, overwrite, or improvise a broader fix.

## Next action

Implement the bounded shortcut-capture change in the registered implementation worktree. Product mutation is authorized only in this worktree and only within the scope above.
