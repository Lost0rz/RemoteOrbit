# CURRENT_STATUS

Last updated: 2026-10-29
State: RO-MAPPING-CONFIG-SIMPLIFY-040 — BOUNDED_SETTINGS_CORRECTIVE_IN_PROGRESS
Repository: Lost0rz/RemoteOrbit

## Current authority

- Canonical repository: `/Volumes/Jack-Dev/Projects/remoteorbit`.
- Task baseline: `origin/main` at `8f71cde21df6ca1f5a831a8b5390abbfde61e9d9`.
- Active implementation branch: `codex/mapping-config-simplify-040`.
- Active writer worktree: `/private/tmp/remoteorbit-mapping-config-simplify-040`.
- Delivered implementation commit: `c3b8c74ee933f666bcc9688be9554d9b79416993`.
- Verified remote delivery: `origin/codex/mapping-config-simplify-040` contains the delivered implementation and paired control alignment.
- Current corrective authorization: the owner authorized a bounded Settings corrective on this same branch/worktree for deterministic mapping-page entry state and observable debug-recording persistence; no new writer is created.
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

## Acceptance state

- Design mode: `DESIGN_IMPLEMENT`.
- Implementation: delivered baseline at `c3b8c74ee933f666bcc9688be9554d9b79416993`; bounded corrective in progress.
- Automated verification: prior baseline PASS; corrective verification pending.
- Retirement residue check: PASS — no retired mapping backup/history identifiers remain in production or tests.
- `RO-OBSERVABILITY-039` changed: NO.
- PR #25 changed: NO.
- Old backup files deleted: NO.
- Remote delivery: `PUSHED_VERIFIED`; local and remote branch heads match exactly.
- Independent Web audit: remains the post-corrective gate, not run or pre-claimed here.
- AI-rendered inspection: not part of this corrective; existing accepted Settings / Control Center UI is frozen.
- Human UI acceptance: PASS for the owner-frozen Settings / Control Center and import/export checks; no new visual acceptance is claimed for this non-redesign corrective.

## Next

Complete bounded corrective implementation and verification, push only this branch, then stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`. Do not merge, tag, release, modify PR #25, or modify the Air validation runtime.
