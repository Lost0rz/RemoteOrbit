# RemoteOrbit Current Task

## Current task — RUNTIME BASELINE RELEASE BLOCKER REMEDIATION

- **Status:** ACTIVE / BUILD BUNDLED DRIVER ARTIFACT, REPACKAGE, THEN PUSH PR
- **Task ID:** `RO-RUNTIME-BASELINE-RELEASE-035`
- **Control parent:** `8a2c67d0f0962a1b78bded0b402c69eb5573b79e`
- **Canonical path:** `/Volumes/Jack-Dev/Projects/remoteorbit`
- **Release target:** `v0.2.14` / Build `43`
- **Authorized release branch:** `codex/release-v0.2.14-baseline`
- **Authorized release worktree:** `/private/tmp/remoteorbit-release-v0.2.14-baseline`
- **Existing release candidate commit:** `6208266122414db3f3caf5852585eb24ed1b1a71`

## Accepted evidence before remediation
Phase A runtime/source equivalence is accepted. The installed/running `0.2.13 (42)` app stamped from `f938b919e288a481f5eacaf9aad9c254dcf0cffe` is product-equivalent to current accepted main. The release candidate changed exactly two paths, passed focused tests, 394/394 full Swift tests, 3/3 self-tests, packaging identity/version/build/source-stamp/Universal-2/codesign checks, then stopped because the packaged app did not contain `RemoteOrbitAudio.driver`.

No release branch push, PR, merge, tag, GitHub Release, installation, runtime replacement, or driver change has occurred.

## Authorized blocker remediation
Use only the existing release worktree and existing release candidate commit. Before mutation, revalidate:
- fresh remote/canonical control HEAD;
- canonical clean main;
- release worktree path/branch;
- release branch local HEAD exactly `6208266122414db3f3caf5852585eb24ed1b1a71`;
- release worktree has no tracked or untracked source changes;
- remote release branch is still absent;
- diff from the release base contains exactly `RELEASE_NOTES_v0.2.14.md` and `remote-orbit/Packaging/Info.plist`.

Then the only newly authorized build-side effect is:

`./remote-orbit-audio-driver/build-driver.sh`

This may create ignored files under `remote-orbit-audio-driver/build/`. It must not modify tracked or untracked repository source. Do not edit the driver source/build script to make the build pass.

Verify the generated driver at minimum:
- exact path `remote-orbit-audio-driver/build/RemoteOrbitAudio.driver` exists;
- driver executable exists;
- driver Bundle ID is recorded;
- driver executable architecture(s) are recorded;
- driver executable SHA-256 is recorded;
- `codesign --verify --deep --strict` passes.

Then rerun `./remote-orbit/package-app.sh` from the same release candidate commit. Verify at minimum:
- packaged Bundle ID `com.lost0rz.RemoteOrbit`;
- version `0.2.14`;
- build `43`;
- `RemoteOrbitDiagnosticSourceHead` equals `6208266122414db3f3caf5852585eb24ed1b1a71`;
- packaged app executable contains `arm64` and `x86_64`;
- app codesign verification passes;
- `Contents/Resources/RemoteOrbitAudio.driver` exists;
- embedded driver executable exists, driver Bundle ID/architectures/SHA-256 are recorded, and embedded driver codesign verification passes.

After packaging, `git status --porcelain -uall` must remain empty and the committed release diff against the release base/main merge-base must still contain exactly the two authorized release paths. Any product/test/build-script/driver-source/config tracked change is a STOP.

If all checks pass, push only `codex/release-v0.2.14-baseline`, verify local/remote branch HEAD match, create exactly one PR to `main` titled `Release RemoteOrbit v0.2.14 baseline`, then stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`.

## Prohibited
Do not install the generated driver. Do not run any driver install script. Do not replace `/Applications/RemoteOrbit.app`. Do not launch/restart/kill RemoteOrbit. Do not restart CoreAudio. Do not change TCC/settings/mappings. Do not modify product or test source. Do not create or move tag `v0.2.14`. Do not publish/upload a GitHub Release or DMG. Do not merge the PR. Do not perform lifecycle cleanup or touch protected historical worktrees.

## Deferred known issue
Codex short-press Voice Chat local/external microphone capture resumption after remote LONG remains deferred and out of scope. Preserve current behavior unchanged and keep the issue stated in `RELEASE_NOTES_v0.2.14.md`.

## Stop boundary
Success stops at `WAITING_FOR_INDEPENDENT_WEB_AUDIT` after branch push and PR creation. Any identity/scope drift, driver build failure, missing embedded driver, signature failure, unexpected repository change, or control-head drift stops before push/PR or at the earliest safe boundary.
