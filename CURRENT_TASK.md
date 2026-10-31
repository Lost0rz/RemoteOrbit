# RemoteOrbit Current Task

## RO-IME-READINESS-PROMPT-SYNC-043 — main integration / merge gate

Status: `SOURCE_AUDIT_PASS / PR_CI_PENDING`
TASK_CLASS: `INTEGRATE / MERGE`
Repository: `Lost0rz/RemoteOrbit`
Integration branch: `codex/task043-main-integration`
Integration base: `main@75d042acf8c116d8a465b987da4257c6af7ff357`
Audited source authority: `e4af810b9a981eaec4f31b2863ea59285504dda4`
User authorization: source-audit PASS may proceed directly to merge; final human audit/runtime test is deferred until after merge.

## Authorized integration

Use a fresh integration tree from current main. Preserve main's durable self-hosted CI authority and import only the already-audited Task 043 semantic delta:

- `remote-orbit/Sources/RemoteOrbit/main.swift`
- `remote-orbit/Sources/RemoteOrbit/VoiceReceiverReadiness.swift`
- `remote-orbit/Tests/RemoteOrbitTests/VoiceBoundaryOrderingTests.swift`
- `remote-orbit/Tests/RemoteOrbitTests/VoiceInputSourceDiagnosticsTests.swift`
- `remote-orbit/Tests/RemoteOrbitTests/VoiceKeyFilterTests.swift`
- `remote-orbit/Tests/RemoteOrbitTests/VoicePressCoordinatorTests.swift`
- `remote-orbit/Tests/RemoteOrbitTests/VoiceReceiverReadinessTests.swift`
- `remote-orbit/Tests/RemoteOrbitTests/VoiceTriggerRuntimeTests.swift`
- `docs/design/2026-10-31-043-long-only-voice-gate-audit.md`
- `docs/design/2026-10-31-043-long-only-voice-gate-corrective.md`
- `docs/design/2026-10-31-043-long-only-voice-gate-final-audit-addendum.md`
- merged durable LONG-only invariant in `AGENTS.md`;
- these control files.

Do not import stale Task 043 control history wholesale. Do not change BLEBridge, AudioPipe, ATVV, driver, packaging, TCC, CoreAudio or installed runtime.

## Merge gates

1. PR targets live `main` and its head is the exact integration commit being audited.
2. PR diff is limited to the authorized paths above and preserves `.github/workflows/remoteorbit-ci.yml`.
3. Durable CI is actually picked up by `remoteorbit-macmini` under `[self-hosted, macOS, ARM64, remoteorbit]` and all required checks pass.
4. Live `main` has not moved incompatibly before merge; if it moved, reconcile rather than force.
5. Merge uses `expected_head_sha` and no stale/force merge.

## After merge

Update `CURRENT_STATUS.md` and `CURRENT_TASK.md` together on merged `main` to record `TASK_043_MERGED / HUMAN_ACCEPTANCE_DEFERRED`.

Do not install/release or claim human PASS. The user will perform the final combined human audit/runtime test later. Task 045 remains blocked until that acceptance/closeout unless explicitly reauthorized.
