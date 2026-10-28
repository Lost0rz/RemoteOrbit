# RemoteOrbit Current Task

## RO-RELEASE-V0.2.15 — Stability + Diagnostics Baseline Release

Status: `AUTHORIZED / RELEASE PREPARATION`

Repository: `Lost0rz/RemoteOrbit`

Canonical repository: `/Volumes/Jack-Dev/Projects/remoteorbit`

## Objective

Publish RemoteOrbit `v0.2.15` / build `44` as the next stable diagnostic baseline after the merged 038-A / 038-B work, so the owner can run the released build for a longer observation period and later analyze fresh logs.

This task is a release task, not a new audio corrective task.

## Release baseline

- Transition parent: `30134cc9a8a705409b28440b5f2215091f6a5e81`.
- Previous public release: `v0.2.14`, build `43`.
- Release target: `v0.2.15`, build `44`, Universal 2.
- PR #24 / 038-B is merged at `b4dbd60d6c27c756bcf735eff050bd29a8324617`.
- 038-B durable closeout: `docs/diagnostics/2026-10-28-task-038-b-audio-continuity-closeout.md`.
- 038-B root-cause verdict remains `NARROWED_NOT_ESTABLISHED`.
- No safe new product corrective is authorized before this release.

## Authorized release branch

Create one release branch from the authoritative release-transition head:

`codex/release-v0.2.15`

The branch is the only writer for release metadata/packaging changes until merge or explicit abandonment.

## Authorized changes

Only the following release-preparation changes are authorized unless a verification failure proves a smaller necessary packaging correction:

1. `remote-orbit/Packaging/Info.plist`
   - `CFBundleShortVersionString = 0.2.15`
   - `CFBundleVersion = 44`
2. add `RELEASE_NOTES_v0.2.15.md`;
3. update control records as required by release lifecycle/provenance;
4. packaging-only corrections required to reproduce the established app/DMG release contract, but only if a concrete release failure is reproduced and the correction is narrowly justified.

Do not modify product audio, BLE, HID, shortcut, Option, queue, buffer, timing, codec, or voice semantics for this release.

## Release notes contract

The v0.2.15 notes must state clearly:

- this is a stability/diagnostics baseline, not a claim that the audio-continuity root cause is fixed;
- rapid re-press reliability work is included;
- shortcut recorder exclusive-capture/restoration hardening is included;
- the new opt-in BLE/decode/PCM/AudioPipe continuity evidence path is included;
- decoder rejection and overflow were downgraded by the 038-B evidence set;
- BLE cadence is supported as a recurring contributor, not an exclusive cause;
- PCM aggregate supply causality was downgraded;
- active-stream underrun remains a fact;
- final text omission remains unverified;
- continuity evidence remains opt-in rather than default-on.

## Diagnostic observation after release

The owner intends to run v0.2.15 for a longer period and later analyze fresh logs.

For that observation period, preserve the audited opt-in boundary:

`REMOTE_ORBIT_CONTINUITY_EVIDENCE=1`

Do not silently make the continuity ledger always-on in normal app launch.

A post-release observation run should preserve release identity in its evidence receipt:

- app path;
- bundle ID;
- version/build;
- executable SHA-256;
- tag/release commit;
- diagnostic environment enabled;
- observation window.

## Local macOS release execution

The local release executor must:

1. fetch/reconcile `main` and this release branch;
2. prove no conflicting active writer for the same release metadata;
3. run applicable tests/self-tests;
4. build the required audio driver if the established DMG flow expects it;
5. run `remote-orbit/package-app.sh`;
6. verify packaged `RemoteOrbit.app`:
   - bundle `com.lost0rz.RemoteOrbit`;
   - version/build `0.2.15 (44)`;
   - arm64 + x86_64;
   - designated requirement `identifier "com.lost0rz.RemoteOrbit"`;
   - embedded `RemoteOrbitDiagnosticSourceHead` equals the exact release candidate commit;
7. run `package-dmg.sh`;
8. verify DMG includes the intended app/driver/install surfaces and is named `RemoteOrbit-0.2.15.dmg`;
9. report SHA-256 of the final DMG;
10. open/merge the release PR only after the release gate passes;
11. tag the exact merged release commit as `v0.2.15`;
12. publish GitHub Release `RemoteOrbit v0.2.15` with the DMG and `RELEASE_NOTES_v0.2.15.md`;
13. re-fetch release/tag/asset metadata and prove provenance.

## Required verification

At minimum report:

- release branch start/final/remote heads;
- changed paths;
- focused/full test results that actually ran;
- release build result;
- app bundle identity/version/architecture/codesign;
- DMG path/name/SHA-256;
- PR state and merge commit;
- tag target;
- GitHub Release URL/id;
- uploaded asset name/size/digest;
- whether hosted CI existed (`NO_HOSTED_CI` if absent);
- worktree status and local release-worktree lifecycle state.

## Stop conditions

STOP rather than silently expanding scope if:

- `main` or the release branch drifts unexpectedly;
- product source changes appear necessary;
- packaging requires a material redesign;
- version/build identity is inconsistent;
- app/DMG provenance cannot be established;
- tests/build/package fail for an unresolved reason;
- tag/release would point to a commit different from the verified release candidate;
- unique/unpushed local work is discovered.

## Non-goals

- No attempt to solve the remaining audio root cause.
- No new continuity probe granularity.
- No 038-C/D/E/F execution.
- No TCC/permission reset.
- No driver semantic change.
- No speculative performance tuning.
- No always-on diagnostic mode change.

## Completion

This task is complete only when the verified v0.2.15 DMG is published against the exact tagged release commit and the control plane records the release identity and remaining diagnostic uncertainty.
