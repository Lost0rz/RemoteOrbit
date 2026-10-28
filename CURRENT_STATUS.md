# CURRENT_STATUS

Last updated: 2026-10-28
State: RELEASE V0.2.15 — RELEASE BRANCH ACTIVE
Repository: Lost0rz/RemoteOrbit

## Repository authority

- Canonical development repository: `/Volumes/Jack-Dev/Projects/remoteorbit`.
- Canonical branch: `main`.
- Verified origin: `https://github.com/Lost0rz/RemoteOrbit.git`.
- Release-transition control head on `main`: `8f71cde21df6ca1f5a831a8b5390abbfde61e9d9`.
- Active release branch: `codex/release-v0.2.15`.
- Release branch start head: `8f71cde21df6ca1f5a831a8b5390abbfde61e9d9`.
- PR #24 (`038-B Audio Continuity Evidence`) is merged at `b4dbd60d6c27c756bcf735eff050bd29a8324617`.
- Durable 038-B closeout: `docs/diagnostics/2026-10-28-task-038-b-audio-continuity-closeout.md`.
- Task 038-B product/evidence work is terminal. Its local historical worktree still has a local-host cleanup obligation but is frozen/read-only by authority and cannot resume overlapping product writes.
- `038-C/D/E/F` remain deferred.

## Release target

- marketing version: `0.2.15`
- build: `44`
- architecture: Universal 2
- release class: stability + diagnostics baseline
- predecessor release: `v0.2.14` / build `43`

The release does **not** claim that the audio-continuity root cause is fixed. Final 038-B root-cause status remains `NARROWED_NOT_ESTABLISHED`.

## Release metadata prepared

The release branch is authorized to contain only release metadata/control changes unless local macOS packaging reproduces a concrete packaging-only blocker.

Prepared release delta:

- `remote-orbit/Packaging/Info.plist` -> `0.2.15 (44)`;
- `RELEASE_NOTES_v0.2.15.md` added;
- release control records aligned to the active release branch.

No product audio/BLE/HID/shortcut/Option semantics are changed by this metadata preparation.

## Included accepted work since v0.2.14

Repository comparison `v0.2.14...main` shows the release line is 73 commits ahead and includes:

- rapid re-press admission / runtime reliability 038-A;
- shortcut recorder exclusive-capture/restoration hardening;
- opt-in BLE/decode/PCM/AudioPipe continuity correlation;
- observer-effect corrections for the real-time diagnostic path;
- stable AUDIO_START-before-HID continuity capture identity;
- runtime evidence and durable 038-B conclusions.

## Diagnostic observation boundary

The 038-B continuity ledger remains opt-in. Normal app launch does not enable it automatically.

For the owner's post-release observation run, launch the installed v0.2.15 runtime with:

`REMOTE_ORBIT_CONTINUITY_EVIDENCE=1`

Do not change the product default to always-on continuity capture solely for this release.

## Release gate

Publication requires local macOS evidence for the exact release branch candidate:

1. applicable Swift tests/self-tests;
2. established audio-driver build when required by DMG packaging;
3. `remote-orbit/package-app.sh` PASS;
4. packaged app version/build `0.2.15 (44)`;
5. universal arm64 + x86_64 executable;
6. codesign/designated requirement verification;
7. `RemoteOrbitDiagnosticSourceHead` equals the exact release candidate commit;
8. `package-dmg.sh` PASS;
9. DMG identity/name/SHA-256 verified;
10. release PR merge;
11. exact tag `v0.2.15` on the merged release commit;
12. GitHub Release `RemoteOrbit v0.2.15` with `RemoteOrbit-0.2.15.dmg`;
13. published tag/release/asset provenance re-fetched and verified.

If hosted CI is absent, report `NO_HOSTED_CI`; do not call absence a PASS.

## Current next action

Local macOS release executor must fetch `codex/release-v0.2.15`, build and verify the candidate, then complete PR merge/tag/GitHub Release only if all release gates pass.
