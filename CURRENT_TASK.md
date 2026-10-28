# RemoteOrbit Current Task

## RO-SHORTCUT-RECORDER-EXCLUSIVE-CAPTURE-037 — Task 037

- Status: MERGE AUTHORIZED — HUMAN ACCEPTANCE DEFERRED.
- Task class: CORRECTIVE / EXECUTION.
- Repository: `Lost0rz/RemoteOrbit`.
- Canonical repository: `/Volumes/Jack-Dev/Projects/remoteorbit`.
- Task 037 control head: `ef09f80813cd868ede8a63bf3e9724fe46b43b0f`.
- Implementation commit: `24ad60d020c73cb306d6258c50575ba64571f01c`.
- Pre-merge Web-audit handoff commit: `26f7a85b74af2a1be22438ce95c6042144da8ed2`.
- Active PR: `https://github.com/Lost0rz/RemoteOrbit/pull/22`.

## Objective

Fix the custom shortcut recorder so system/global shortcuts can be recorded without executing their existing macOS action during recording. The recorder exclusively owns one complete physical keyboard gesture from the first swallowed edge through final release.

Required product examples remain:

- Command-Space records Command-Space without opening Spotlight.
- Command-Shift-4 records Command-Shift-4 without initiating screenshot capture.

## Scope and protected authorities

- Dedicated `ShortcutCaptureMonitor` uses an active `CGEventTap` at `.cghidEventTap`, `.headInsertEventTap`, with `.defaultTap` and keyDown/keyUp/flagsChanged interest.
- Neutral-start gating, complete physical suppression, synthetic-event pass-through, chord freeze, release-boundary commit, pure-modifier support, autorepeat suppression, cancellation drain, tap failure reporting, and state reset are in scope.
- `SettingsView.swift` integrates the recorder monitor/controller.
- No Voice behavior, BLE/audio, audio-driver, packaging/install/release, mapping-store/schema, or unrelated cleanup changes are authorized.
- `EventSuppressor` and `KeyInjector` semantics remain protected and unchanged.

## Verification and audit

- Focused `ShortcutCaptureMonitorTests`: PASS — 11/11.
- Full `swift test`: PASS — 405/405.
- Release build: PASS.
- Self-tests: PASS — 3/3.
- Independent Web CODE_DIFF audit of PR #22: PASS.
- PR scope inspection confirmed only `CURRENT_STATUS.md`, `CURRENT_TASK.md`, `SettingsView.swift`, new `ShortcutCaptureMonitor.swift`, and new `ShortcutCaptureMonitorTests.swift` changed through the audited handoff.

## Human acceptance deferral

- `HUMAN_UI_ACCEPTANCE: PENDING`.
- The user explicitly authorized merge before human acceptance so Task 037 can be tested later together with subsequent changes.
- Pending human acceptance must not be reported as PASS merely because automated tests or Web code audit passed.
- Deferred acceptance still needs real macOS checks for Command-Space, Command-Shift-4, Option-A, pure modifier, and post-cancel/close restoration.

## Authorized merge transition

- User authorization supersedes the previous task-local rule that human acceptance must occur before merge.
- Merge PR #22 only after this paired control transition is the exact live PR head and the PR remains mergeable against `main`.
- Mark the Draft PR ready for review if GitHub requires it before merge.
- Merge only PR #22; do not merge unrelated work.
- After merge, update `CURRENT_STATUS.md` and `CURRENT_TASK.md` together on `main` with the actual merge commit and state `MERGED — HUMAN ACCEPTANCE DEFERRED`.
- Do not install, package, release, delete the worktree/branch, or start unrelated product mutation as part of the merge operation.

## Next action

Publish this paired merge-authorization control commit to `codex/shortcut-recorder-exclusive-capture-v1`, verify it is the exact PR #22 head, mark the PR ready if necessary, merge it, then create the paired post-merge control transition on `main`. Preserve `HUMAN_UI_ACCEPTANCE: PENDING` for later combined manual acceptance.
