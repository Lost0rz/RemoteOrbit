# RemoteOrbit Current Task

## Current task — RUNTIME-IDENTITY BASELINE RELEASE PREPARATION

- **Status:** ACTIVE / VERIFY INSTALLED BASELINE, THEN PREPARE RELEASE CANDIDATE
- **Task ID:** `RO-RUNTIME-BASELINE-RELEASE-035`
- **Control parent:** `8e4bc7a06f2025d5b0abdfca82f68002df95ef7a`
- **Canonical path:** `/Volumes/Jack-Dev/Projects/remoteorbit`
- **Conditional release target:** `v0.2.14` / Build `43`
- **Authorized release branch:** `codex/release-v0.2.14-baseline`
- **Authorized release worktree:** `/private/tmp/remoteorbit-release-v0.2.14-baseline`

## Goal
Verify the exact installed/running RemoteOrbit identity that the user has been testing and, only if it is product-equivalent to the accepted current `main`, prepare that behavior as the next formal baseline release without changing product behavior.

## Phase A — mandatory read-only runtime identity gate
Read `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md`, `README.md`, `SETUP_NOTES.md`, the current packaging files, and the prior `v0.2.13` release commit/notes before release work.

Collect at minimum:
- canonical local HEAD / `origin/main` and cleanliness;
- installed app path `/Applications/RemoteOrbit.app`;
- Bundle ID;
- `CFBundleShortVersionString`;
- `CFBundleVersion`;
- `RemoteOrbitDiagnosticSourceHead`;
- executable SHA-256;
- executable architectures;
- code-signature designated requirement;
- running PID/path/start time when running;
- proof that the running executable belongs to that installed app bundle.

Then prove product equivalence between the installed app's stamped source HEAD and current accepted `main`:
- product/source and packaging behavior must not differ except for later control/documentation-only changes;
- if the source HEAD is missing/unresolvable, the installed app is not the expected bundle, the executable differs from the running process, or product equivalence is not proven: STOP with no release mutation.

## Phase B — release-candidate preparation, only after Phase A PASS
Create only:
- worktree `/private/tmp/remoteorbit-release-v0.2.14-baseline`;
- branch `codex/release-v0.2.14-baseline` from the fresh control HEAD.

Allowed repository changes on that branch are limited to:
1. `remote-orbit/Packaging/Info.plist`
   - `CFBundleShortVersionString`: `0.2.14`
   - `CFBundleVersion`: `43`
2. new `RELEASE_NOTES_v0.2.14.md`

The release notes must describe the accepted dual-receiver baseline and explicitly record the deferred Codex short-mode local-microphone-resume verification issue. Do not claim that deferred behavior is fixed or fully validated.

No other product/test/runtime/configuration file may change.

## Validation
At minimum:
- `git diff --check`;
- focused voice/dual-receiver tests relevant to the accepted baseline;
- full Swift test suite;
- `./remote-orbit/run-self-tests.sh`;
- `./remote-orbit/package-app.sh`;
- verify packaged app Bundle ID/version/build/source stamp;
- verify Universal 2 (`arm64` + `x86_64`);
- `codesign --verify --deep --strict`;
- verify packaged executable hash is recorded;
- verify bundled `RemoteOrbitAudio.driver` presence or explicitly report its absence as a release blocker;
- compare changed paths against the exact allowed two-path manifest.

Do not install or launch the newly packaged candidate during this task.

## Prior-release pattern
The previous `v0.2.13` release used branch `codex/release-v0.2.13`, changed only release notes plus `remote-orbit/Packaging/Info.plist`, merged through PR #11, then tagged/released. Follow the same release-only pattern unless current repository evidence proves a newer accepted release procedure.

## Deferred known issue — out of scope
Codex short-press voice mode uses the Mac/local-or-external microphone path; remote long hold takes over with remote audio. The return/resume of local microphone capture after remote hold has not yet been independently accepted. Preserve current behavior unchanged and carry this as a known deferred issue in release notes.

## Stop boundary
After pushing the release-candidate branch and opening the PR, stop at:

`WAITING_FOR_INDEPENDENT_WEB_AUDIT`

Do not merge the PR, create/push tag `v0.2.14`, publish a GitHub Release, upload a DMG, install the candidate, replace `/Applications/RemoteOrbit.app`, restart the app, modify the audio driver, restart CoreAudio, alter TCC, or perform additional lifecycle cleanup under this task phase.

## Protected objects
Do not modify, clean, reset, stash, prune, delete, or reuse any of the eight non-canonical protected worktrees retained by Task 034.
