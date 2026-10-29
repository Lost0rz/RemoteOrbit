# CURRENT_STATUS

Last updated: 2026-10-29
State: RO-MAPPING-CONFIG-SIMPLIFY-040 — WAITING_FOR_INDEPENDENT_WEB_AUDIT
Repository: Lost0rz/RemoteOrbit

## Current authority

- Canonical repository: `/Volumes/Jack-Dev/Projects/remoteorbit`.
- Task baseline: `origin/main` at `8f71cde21df6ca1f5a831a8b5390abbfde61e9d9`.
- Active implementation branch: `codex/mapping-config-simplify-040`.
- Active writer worktree: `/private/tmp/remoteorbit-mapping-config-simplify-040`.
- Delivered implementation commit: `c3b8c74ee933f666bcc9688be9554d9b79416993`.
- Delivered corrective commit: `9669420ecfd65034ebeb61ade08386dd0ca20659`.
- Delivered structured-evidence implementation commit: `21255f3`.
- Final control reconciliation is the paired update to `CURRENT_STATUS.md` and `CURRENT_TASK.md` on this same branch; its exact published SHA and the resulting remote head are recorded in the completion receipt.
- The pre-follow-up remote/control snapshot was reconciled at `d0c11d7b74d70f3ba5e4fbb9b70f1d451644df66`; no stale `718a…` identity remains.
- No new writer was created; the bounded follow-up is complete and the branch now stops at the independent Web-audit gate.
- `AGENTS.md` remains the durable repository rule authority; `CURRENT_TASK.md` is the single active implementation authorization for this branch.
- `RO-OBSERVABILITY-039` continues separately as owner-run Air natural-use observation on `codex/observability-039`; that branch is frozen for product writes while evidence is collected.
- PR #25 / `codex/release-v0.2.15` remains Draft/Open/Unmerged and is not part of this task.

## Delivered implementation

- `SettingsView` now exposes one compact “配置导入与导出” surface with manual JSON export/import and concise feedback only.
- `MappingStore` retains canonical atomic JSON persistence, backward-compatible decode behavior, manual import/export, and the UserDefaults compatibility mirror while removing automatic snapshots, recovery scanning, and backup-specific APIs/errors.
- `AppStorage.prepare()` no longer creates the retired mapping-backup directory.
- Existing user backup files were not deleted.

## Product boundaries

This task must not change:

- actual button mapping semantics;
- app-template routing or Active-template behavior;
- advanced gesture semantics;
- voice trigger / persistent voice behavior;
- BLE, audio, HID, diagnostics, driver, or Air-validation behavior.

## Current corrective scope

- Mapping-page entry resets only the Settings editor navigation state to Global / 通用 and Microphone / 语音键; it must not mutate mappings, templates, Active Template, runtime routing, or button semantics.
- Debug recording follows the existing production chain from the Settings toggle through BLEBridge, AUDIO_START, WavRecorder, filesystem writes, and close; failures must become observable evidence without changing BLE/ATVV, AudioPipe, codec, gesture, or persistence semantics.
- Existing Settings / Control Center UI acceptance and manual JSON import/export acceptance are owner-frozen as PASS and are not being redesigned or re-audited.
- Existing backup files are not deleted; RO-OBSERVABILITY-039, PR #25, and the Air runtime remain out of scope.

## Delivered corrective

- Mapping editor entry now resets only Settings navigation state to Global / 通用, Microphone / 语音键, and no template target; user-selected App/template editing remains available until leaving the section.
- Recording toggle and `AUDIO_START` now expose persisted enable state, recorder creation outcome, WAV/RAW paths, write/close failures, and final file sizes; recorder creation is throwing/observable instead of silent optional nil.
- Recording sessions use unique filenames and never delete or overwrite existing captures during recorder initialization.
- `ROOT_CAUSE_DEBUG_RECORDING`: the owner-reported live session remains `UNKNOWN` because no Air/hardware session was run in this task. Direct source defects confirmed at the recorder boundary were silent creation failure handling and same-millisecond filename collision with pre-existing-file deletion; local production-chain seams now prove the enabled/disabled, create, write, close, and filesystem behavior.

## Delivered structured-evidence follow-up

- `WavRecorder` now emits persistent `audio.capture.recording_create_failed`, `audio.capture.recording_write_failed`, and `audio.capture.recording_close_failed` events directly through `DiagnosticAuthority`, independent of `AppStorage.loggingEnabled`.
- Structured payloads contain only bounded operation, failure category, and reason tokens; they contain no audio content, dictated text, or raw recording paths. Existing recording lifecycle events and successful WAV/RAW behavior remain unchanged.
- Focused tests cover creation failure with runtime logging disabled, write/close failure evidence paths, lifecycle-only successful recordings, valid WAV/RAW finalization, unique sessions, and payload non-leakage.

## Acceptance state

- Design mode: `DESIGN_IMPLEMENT`.
- Implementation: delivered baseline plus corrective at `9669420ecfd65034ebeb61ade08386dd0ca20659`.
- Automated verification: PASS — focused mapping/recording 21/21; full Swift 431/431; release build PASS; `git diff --check` PASS.
- Retirement residue check: PASS — no retired mapping backup/history identifiers remain in production or tests.
- `RO-OBSERVABILITY-039` changed: NO.
- PR #25 changed: NO.
- Old backup files deleted: NO.
- Remote delivery: final paired control update is ready for publication; exact final local/control/remote heads are verified after push in the completion receipt.
- Corrective PR: `#26` Draft/Open/Unmerged — `https://github.com/Lost0rz/RemoteOrbit/pull/26`.
- Independent Web audit: `WAITING_FOR_INDEPENDENT_WEB_AUDIT`; no independent Web PASS is claimed.
- AI-rendered inspection: not part of this corrective; existing accepted Settings / Control Center UI is frozen.
- Human UI acceptance: PASS for the owner-frozen Settings / Control Center and import/export checks; no new visual acceptance is claimed for this non-redesign corrective.

## Next

The structured recording-evidence follow-up is complete. Publish only this branch, verify exact local/control/remote heads and PR #26, then stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`. Do not merge, tag, release, modify PR #25, or modify the Air validation runtime.
