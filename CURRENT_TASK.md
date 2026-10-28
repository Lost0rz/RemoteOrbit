# RemoteOrbit Current Task

## RO-RELEASE-V0.2.15 — Stability + Diagnostics Baseline Release

Status: `RELEASE BRANCH ACTIVE / LOCAL MACOS VERIFICATION REQUIRED`

Repository: `Lost0rz/RemoteOrbit`

Canonical repository: `/Volumes/Jack-Dev/Projects/remoteorbit`

## Objective

Publish RemoteOrbit `v0.2.15` / build `44` as the next stable diagnostics baseline after the merged 038-A / 038-B work, so the owner can run the released build for a longer observation period and later analyze fresh logs.

This task is a release task, not a new audio corrective task.

## Release authority

- Control-transition head on `main`: `8f71cde21df6ca1f5a831a8b5390abbfde61e9d9`.
- Active release branch: `codex/release-v0.2.15`.
- Release branch start head: `8f71cde21df6ca1f5a831a8b5390abbfde61e9d9`.
- Previous public release: `v0.2.14`, build `43`.
- Release target: `v0.2.15`, build `44`, Universal 2.
- PR #24 / 038-B is merged at `b4dbd60d6c27c756bcf735eff050bd29a8324617`.
- 038-B root-cause verdict remains `NARROWED_NOT_ESTABLISHED`.

## Authorized release changes

The release branch may change only:

1. `remote-orbit/Packaging/Info.plist`
   - `CFBundleShortVersionString = 0.2.15`
   - `CFBundleVersion = 44`
2. `RELEASE_NOTES_v0.2.15.md`;
3. `CURRENT_STATUS.md` / `CURRENT_TASK.md` for lifecycle/provenance;
4. a narrowly justified packaging-only correction if local macOS release verification reproduces a concrete blocker.

No product source corrective is authorized.

## Release notes contract

The release notes must state clearly:

- this is a stability/diagnostics baseline, not a claim that the remaining audio-continuity root cause is fixed;
- rapid re-press reliability work is included;
- shortcut recorder exclusive-capture/restoration hardening is included;
- the new opt-in BLE/decode/PCM/AudioPipe continuity evidence path is included;
- decoder rejection and overflow are downgraded by the 038-B evidence set;
- BLE cadence is supported as a recurring contributor, not an exclusive cause;
- PCM aggregate supply causality is downgraded;
- active-stream underrun remains a fact;
- final text omission remains unverified;
- continuity evidence remains opt-in rather than default-on.

## Diagnostic observation after release

For the owner's longer post-release observation period, preserve the audited opt-in boundary:

`REMOTE_ORBIT_CONTINUITY_EVIDENCE=1`

Do not silently make the continuity ledger always-on in normal app launch.

The later log review must bind evidence to:

- app path;
- bundle ID;
- version/build;
- executable SHA-256;
- tag/release commit;
- diagnostic environment;
- observation window.

## Local macOS release execution

The local release executor must:

1. fetch `main` and `codex/release-v0.2.15`;
2. create/select one clean release worktree from the exact remote branch;
3. prove no unique/unpushed work and no conflicting release writer;
4. verify the branch contains only the authorized release delta before packaging;
5. run applicable Swift tests/self-tests;
6. build the required audio driver if the established DMG flow expects it;
7. run `remote-orbit/package-app.sh`;
8. verify packaged `RemoteOrbit.app`:
   - bundle `com.lost0rz.RemoteOrbit`;
   - version/build `0.2.15 (44)`;
   - arm64 + x86_64;
   - designated requirement `identifier "com.lost0rz.RemoteOrbit"`;
   - embedded `RemoteOrbitDiagnosticSourceHead` equals the exact release candidate commit;
9. run `package-dmg.sh`;
10. verify the DMG name `RemoteOrbit-0.2.15.dmg`, contents and SHA-256;
11. open or update a release PR to `main` and complete the release merge only after evidence passes;
12. tag the exact merged release commit as `v0.2.15`;
13. publish GitHub Release `RemoteOrbit v0.2.15` with the DMG and `RELEASE_NOTES_v0.2.15.md`;
14. re-fetch and verify release/tag/asset provenance;
15. update control records with the final release identity;
16. close the release worktree/branch locally when safe.

## Required return evidence

- release branch start/final/remote heads;
- changed paths;
- exact tests that ran and their results;
- release build result;
- app bundle identity/version/architecture/codesign;
- DMG path/name/SHA-256;
- PR number/state and merge commit;
- tag target;
- GitHub Release URL/id;
- uploaded asset name/size/digest;
- hosted CI status (`NO_HOSTED_CI` if absent);
- release worktree state and final disposition.

## Stop conditions

STOP if:

- `main` or the release branch drifts unexpectedly;
- product source changes appear necessary;
- packaging requires a material redesign;
- version/build identity is inconsistent;
- app/DMG provenance cannot be established;
- tests/build/package fail for an unresolved reason;
- tag/release would point to a commit different from the verified candidate;
- unique/unpushed local work is discovered.

## Non-goals

- No attempt to solve the remaining audio root cause.
- No finer-grained continuity probe.
- No 038-C/D/E/F execution.
- No TCC reset.
- No driver semantic change.
- No speculative performance tuning.
- No always-on diagnostic mode change.

## Completion

Complete only when a verified `RemoteOrbit-0.2.15.dmg` is published from the exact tagged release commit and the control plane records both the release provenance and the remaining diagnostic uncertainty.
