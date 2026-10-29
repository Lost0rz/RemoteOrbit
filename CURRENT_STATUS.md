# CURRENT_STATUS

Last updated: 2026-10-29
State: RO-MAPPING-CONFIG-SIMPLIFY-040 — AUTHORIZED / READY_FOR_IMPLEMENTATION
Repository: Lost0rz/RemoteOrbit

## Current authority

- Canonical repository: `/Volumes/Jack-Dev/Projects/remoteorbit`.
- Task baseline: `origin/main` at `8f71cde21df6ca1f5a831a8b5390abbfde61e9d9`.
- Active implementation branch: `codex/mapping-config-simplify-040`.
- `AGENTS.md` remains the durable repository rule authority; `CURRENT_TASK.md` is the single active implementation authorization for this branch.
- `RO-OBSERVABILITY-039` continues separately as owner-run Air natural-use observation on `codex/observability-039`; that branch is frozen for product writes while evidence is collected.
- PR #25 / `codex/release-v0.2.15` remains Draft/Open/Unmerged and is not part of this task.

## Verified simplification finding

The current local mapping-configuration surface is materially overbuilt for the owner's actual workflow:

- Settings UI exposes an automatic-backup card, recent backup history, restore actions, and an “open backup folder” action in addition to manual export/import.
- `MappingStore` creates history snapshots before ordinary configuration saves, before import/restore, during migration, and for invalid configuration payloads; it also scans prior backup history for automatic recovery.
- `AppStorage.prepare()` creates the mapping-backup directory on every launch.

The owner explicitly wants the mapping-configuration workflow reduced to manual export/import only. Automatic backup/history management is no longer a product requirement.

## Target product state

- Replace the backup/history UI with one lightweight “配置导入与导出” surface.
- Keep only manual `导出当前配置…` and `导入配置…` actions plus concise success/error feedback.
- Import may use a small confirmation explaining that it replaces the current mapping configuration and does not create an automatic backup.
- Remove recent-backup history, restore-from-backup actions, backup-folder navigation, backup date formatting, and restore-specific UI state.
- Retire automatic mapping snapshot generation and automatic recovery from historical backup files.
- Preserve the canonical file-backed configuration, atomic writes, JSON import/export contract, schema compatibility, and existing UserDefaults compatibility mirror unless a concrete incompatibility requires a narrower corrective.
- Do not automatically delete old backup files already present on user machines; they become inert historical residue.

## Product boundaries

This task must not change:

- actual button mapping semantics;
- app-template routing or Active-template behavior;
- advanced gesture semantics;
- voice trigger / persistent voice behavior;
- BLE, audio, HID, diagnostics, driver, or Air-validation behavior.

## Acceptance state

- Design mode: `DESIGN_IMPLEMENT`.
- Implementation: pending local executor.
- Automated verification: pending.
- Independent Web audit: pending after remote delivery.
- Human UI acceptance: pending owner review.

## Next

Local executor implements the bounded simplification on `codex/mapping-config-simplify-040`, verifies import/export and mapping regressions, pushes the exact branch, and stops at `WAITING_FOR_INDEPENDENT_WEB_AUDIT` without merge/release.
