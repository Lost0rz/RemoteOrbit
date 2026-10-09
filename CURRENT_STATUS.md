# CURRENT_STATUS

Last updated: 2026-10-09
State: TASK 035 PUBLISHED / READY FOR WEB CLOSEOUT
Repository: `Lost0rz/RemoteOrbit`

## Release
- Task ID: `RO-RUNTIME-BASELINE-RELEASE-035`.
- Publication control baseline: `0d13e64df2b7aa1f191edf20d34b4152ce52c31f`.
- PR #21 is CLOSED / MERGED at controlled merge commit `46dc94f58e67d5da38420047f009d3f311321108`.
- Annotated tag `v0.2.14` is pushed; tag object `5eb34cc1cf36c3dcfdef3df7d0c430262ed7b6c2` peels to the controlled merge commit.
- Public GitHub Release: https://github.com/Lost0rz/RemoteOrbit/releases/tag/v0.2.14
- Release name: `RemoteOrbit v0.2.14`; draft: NO; prerelease: NO.
- Uploaded asset: `RemoteOrbit-0.2.14.dmg`, 5,928,820 bytes, digest `sha256:6f45831c6cc1d0fcca71e7d7db6b85e6c0864cc778a1fac730921a0eaa0bc9fa`.

## Release commit validation carried forward from PR #21
- Focused voice suites: PASS; full Swift suite: 394/394 PASS; self-tests: 3/3 PASS.
- Prepublication package build, app identity/version/build/source stamp, Universal 2 architectures, app signature, and bundled driver signature: PASS.

## Build and artifact validation
- Built from detached merge commit `46dc94f58e67d5da38420047f009d3f311321108` with `./package-dmg.sh`.
- Local DMG: `/private/tmp/remoteorbit-v0.2.14-publish/dist/RemoteOrbit-0.2.14.dmg`.
- Local DMG SHA-256 and GitHub asset digest match; size is 5,928,820 bytes; `hdiutil verify` PASS.
- Packaged app: Bundle ID `com.lost0rz.RemoteOrbit`, version `0.2.14`, build `43`, source stamp `46dc94f58e67d5da38420047f009d3f311321108`, architectures `x86_64 arm64`, codesign PASS.
- Bundled `RemoteOrbitAudio.driver`: present, architectures `x86_64 arm64`, codesign PASS.
- Product source changes: NONE. Test source changes: NONE. Installed app/driver changes: NONE.
- The build emitted a non-fatal BlackHole 0.7.1 deployment-target warning (10.10; current Xcode supports 10.13+); the build succeeded and packaged artifact checks passed.

## Checkout state and release handoff
- Canonical checkout: `/Volumes/Jack-Dev/Projects/remoteorbit`; branch `main` was clean at the publication control baseline before this closeout update.
- Publication worktree: `/private/tmp/remoteorbit-v0.2.14-publish`, detached at the merge commit and clean after packaging. Retained to preserve the verified artifact for web closeout; no lifecycle cleanup was performed.
- The requested full tag fetch reported a pre-existing local `v0.2.8` conflict with the remote tag. That local tag was preserved; `main` was fast-forwarded and the `v0.2.14` remote tag was checked directly and verified at the exact target.
- Ready for web closeout using the public Release URL and verified asset digest above.

## Deferred known issue
Codex short Voice Chat local/external microphone capture resumption after remote LONG remains `KNOWN_DEFERRED / NOT FIXED / NOT INDEPENDENTLY ACCEPTED`.

## Boundary
No product/test edits, installed-app/driver replacement, RemoteOrbit/CoreAudio restart, TCC/settings/mapping changes, or lifecycle cleanup were performed.
