# RemoteOrbit Current Task

## RO-BRAND-ICON-UNIFICATION-044 — WAITING FOR HUMAN UI ACCEPTANCE

Status: `WAITING_FOR_HUMAN_UI_ACCEPTANCE`

Repository: `Lost0rz/RemoteOrbit`
Canonical branch: `main`
Active task branch: `codex/brand-icon-unification-044`

## Authority

User authorized a bounded visual-brand implementation on 2026-10-31: create a canonical RemoteOrbit vector mark and replace the inconsistent Settings/About and menu-bar icon treatments.

Task 043 (`RO-IME-READINESS-PROMPT-SYNC-043`) remains a separate follow-on voice/IME task and is not modified by this work.

## Objective

Unify RemoteOrbit iconography around one recognizable `remote + orbit` mother mark:

- keep a single editable canonical SVG vector asset;
- retain the existing full-color application icon as the Dock/app treatment;
- make Settings/About follow the actual application icon;
- make the macOS menu bar use a stable monochrome RemoteOrbit template mark rather than swapping unrelated SF Symbols by state;
- keep operational state in menu/status text.

## Implemented

- `remote-orbit/Brand/RemoteOrbitMark.svg` is the canonical editable vector mother mark.
- `ProductBranding.swift` uses `NSApp.applicationIconImage` for Settings/About.
- `ProductBrandMark.menuBarTemplateImage(size:)` renders the canonical `remote + orbit` mark as a macOS template image with `isTemplate = true`.
- `main.swift` now keeps the existing `setStatusIcon(systemName:color:)` call boundary but always assigns `ProductBrandMark.menuBarTemplateImage(size: 18)`; state-specific SF Symbol/color arguments no longer replace the brand silhouette.
- Existing ready/waiting/connecting/error/recording decision logic and status/menu text are preserved.
- Existing full-color application/Dock icon remains unchanged.

## Verification

- Direct commit diff for the large `main.swift` rewrite was verified before branch publication: exactly one file changed, limited to the `setStatusIcon` implementation (`+2/-26`).
- Static source checks establish that Settings follows `NSApp.applicationIconImage`, the menu renderer is template-compatible, the canonical SVG exists, and the status-item call site uses the RemoteOrbit mark.
- No BLE, HID, AudioPipe, voice-session, IME, driver, CoreAudio, TCC, or LaunchAgent source/behavior change is part of this task.
- `swift test` / `swift build`: `NOT_RUN_REMOTE_ENVIRONMENT`. Attempted GitHub Actions jobs failed at runner startup before any repository step executed; this is not a code/test failure and is not promoted to PASS.
- Installed runtime verification: `NOT_RUN`; installation is outside Task 044 authority.
- Human UI acceptance: `PENDING`.

## Remaining authorized action

User syncs `codex/brand-icon-unification-044` locally, builds/runs the development candidate, and visually checks:

1. Settings/About shows the current app icon rather than the old green tile.
2. Menu bar shows the stable monochrome RemoteOrbit `remote + orbit` mark in macOS light/dark appearance.
3. Status/menu text still communicates ready/waiting/connecting/error/recording state.

After explicit human acceptance, Task 044 may be closed/merged only under a separate authorized transition. Do not merge, install, release, or advance Task 043 automatically.

## Non-goals / stop boundary

- No BLE, HID, AudioPipe, voice-session, IME timing/readiness, diagnostic semantics, or remote-control behavior changes.
- No driver/CoreAudio/TCC/LaunchAgent mutation.
- No app installation, release, tag, or merge to `main` without a separate acceptance decision.
- Stop at remote branch + reviewable PR with human UI acceptance pending.
