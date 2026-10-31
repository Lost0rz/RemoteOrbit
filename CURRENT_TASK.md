# RemoteOrbit Current Task

## RO-BRAND-ICON-UNIFICATION-044 — IN PROGRESS

Status: `IN_PROGRESS`

Repository: `Lost0rz/RemoteOrbit`
Canonical branch: `main`
Active task branch: `codex/brand-icon-unification-044`

## Authority

User authorized a bounded visual-brand implementation on 2026-10-31: create a canonical RemoteOrbit vector mark and replace the inconsistent Settings/About and menu-bar icon treatments.

Task 043 (`RO-IME-READINESS-PROMPT-SYNC-043`) remains a separate follow-on voice/IME task and is not modified by this work.

## Objective

Unify RemoteOrbit iconography around one recognizable `remote + orbit` mother mark:

- add an editable canonical SVG vector asset;
- keep the existing full-color application icon as the Dock/app treatment;
- make Settings/About show the actual application icon instead of a separately drawn green SF-Symbol tile;
- make the macOS menu bar use a monochrome RemoteOrbit template mark rather than swapping unrelated SF Symbols by status;
- keep operational state in menu/status text; any future icon-state decoration must preserve the mother mark.

## Implemented

- `remote-orbit/Brand/RemoteOrbitMark.svg` is the canonical editable vector mother mark.
- `ProductBranding.swift` now uses `NSApp.applicationIconImage` for Settings/About.
- `ProductBrandMark.menuBarTemplateImage(size:)` renders the canonical mark as a monochrome macOS template image.
- Existing full-color application icon is intentionally retained.

## Remaining authorized action

Apply the bounded `main.swift` wiring change in a complete local checkout:

- replace only `setStatusIcon(systemName:color:)` so it assigns `ProductBrandMark.menuBarTemplateImage(size: 18)`;
- preserve the existing method signature/callers so ready/waiting/connecting/error/recording status logic and menu text remain untouched;
- run focused build/tests and inspect Settings/About + menu bar;
- update control state and create a reviewable PR after verification.

A deterministic patch script was produced for this one-method local change because this remote-only GitHub connector cannot safely rewrite the >300 KB `main.swift` from truncated read output.

## Scope

Authorized source changes are limited to product branding assets/UI plumbing needed for the icon system, plus focused tests or verification helpers where useful.

Expected affected surfaces:

- `remote-orbit/Brand/`
- `remote-orbit/Sources/RemoteOrbit/ProductBranding.swift`
- the bounded status-item icon rendering code in `remote-orbit/Sources/RemoteOrbit/main.swift`
- packaging/resource inclusion only if required for the vector/template asset
- `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md`

## Non-goals

- No BLE, HID, AudioPipe, voice-session, IME timing/readiness, diagnostic semantics, or remote-control behavior changes.
- No driver/CoreAudio/TCC/LaunchAgent mutation.
- No app installation, release, tag, or merge to `main` without a separate acceptance decision.
- Do not redesign the accepted full-color app icon unless required to make the canonical mark technically consistent.

## Acceptance

1. A single editable RemoteOrbit vector mother mark exists and visually reads as `remote + orbit` at small sizes.
2. Settings/About no longer hardcodes the old green `circle.dotted.and.circle` tile and instead follows the application identity.
3. The menu-bar brand silhouette remains stable across ready/waiting/connecting/error/recording states; status remains available in text.
4. Menu-bar artwork is template-compatible for macOS light/dark menu bars.
5. Focused source/build verification passes without touching voice/audio behavior.
6. Human visual acceptance remains user-owned.

## Stop boundary

Stop after implementation, focused verification, remote branch delivery, and a reviewable PR. Do not merge, install, release, or advance Task 043 automatically.
