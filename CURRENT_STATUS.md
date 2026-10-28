# CURRENT_STATUS

Last updated: 2026-10-28
State: RELEASE V0.2.15 PREPARATION
Repository: Lost0rz/RemoteOrbit

## Repository authority

- Canonical development repository: `/Volumes/Jack-Dev/Projects/remoteorbit`.
- Canonical branch: `main`.
- Verified origin: `https://github.com/Lost0rz/RemoteOrbit.git`.
- Release-transition parent: `30134cc9a8a705409b28440b5f2215091f6a5e81`.
- PR #24 (`038-B Audio Continuity Evidence`) is merged at `b4dbd60d6c27c756bcf735eff050bd29a8324617`.
- Durable 038-B closeout: `docs/diagnostics/2026-10-28-task-038-b-audio-continuity-closeout.md`.
- Task 038-B product/evidence work is terminal. Its local `/private/tmp/remoteorbit-runtime-reliability-038-b-continuity-evidence` workspace still has a local-host cleanup obligation; remote evidence does not prove that local worktree is physically closed.
- The retained 038-B workspace is frozen/read-only by authority and may not resume product writes without a new transition, so it does not authorize or overlap this release task.
- `038-C/D/E/F` remain deferred.

## Release decision

The owner explicitly authorized a new release after the 038-B evidence phase because there is no currently justified product corrective to apply safely.

Release target:

- marketing version: `0.2.15`
- build: `44`
- architecture: Universal 2
- release class: stability + diagnostics baseline
- predecessor release: `v0.2.14` / build `43`

The release does **not** claim that the audio-continuity root cause is fixed. Final 038-B root-cause status remains `NARROWED_NOT_ESTABLISHED`.

## Delta since v0.2.14

Repository comparison `v0.2.14...main` shows the release line is 73 commits ahead and includes the following accepted work:

- rapid re-press admission / runtime reliability 038-A;
- shortcut recorder exclusive capture and restoration hardening;
- opt-in audio-continuity correlation across BLE -> decode -> PCM submission -> AudioPipe render/underrun;
- observer-effect corrections that remove shared diagnostic lock/dictionary work from the real-time render/submission path;
- stable AUDIO_START-before-HID capture/session correlation;
- runtime evidence and durable diagnostic conclusions.

This release preparation itself must not add speculative audio/BLE correction.

## Diagnostic observation boundary

The 038-B continuity ledger is intentionally opt-in. Normal app launch does not enable it automatically.

For the owner's post-release observation run, the installed v0.2.15 app should be launched in the existing diagnostic mode with:

`REMOTE_ORBIT_CONTINUITY_EVIDENCE=1`

Do not change the product default to always-on continuity capture solely for this release. This preserves the audited default-off production path while allowing a bounded owner-operated observation period.

## Release verification requirements

Before publication, the local macOS release executor must prove the exact release candidate identity and run proportional release checks:

1. reconcile/fetch `main` and create/use the authorized release branch;
2. bump `remote-orbit/Packaging/Info.plist` to `0.2.15 (44)`;
3. add `RELEASE_NOTES_v0.2.15.md` with the accepted scope and known unresolved audio-continuity limitation;
4. run the applicable Swift tests/self-tests;
5. build the audio driver used by the DMG if required by the established packaging flow;
6. run `remote-orbit/package-app.sh` and verify app identity/version/architectures/codesign;
7. run `package-dmg.sh` and verify the DMG contents/version;
8. merge the release PR only after release evidence passes;
9. create tag `v0.2.15` at the exact merged release commit;
10. publish GitHub Release `RemoteOrbit v0.2.15` with `RemoteOrbit-0.2.15.dmg` and the release notes;
11. verify the published asset digest and release/tag/commit provenance.

No hosted CI status is assumed; if none exists, report `NO_HOSTED_CI` rather than PASS.

## Current next action

Prepare the v0.2.15 release branch/metadata, then hand the exact branch to the local macOS release executor for build/package/release verification. Do not publish a release artifact that has not been built and inspected on macOS.
