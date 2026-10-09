# RemoteOrbit Current Task

## Current task — RUNTIME BASELINE RELEASE PUBLICATION

- **Status:** USER AUTHORIZED / MERGE PR #21, TAG v0.2.14, PUBLISH RELEASE
- **Task ID:** `RO-RUNTIME-BASELINE-RELEASE-035`
- **Control parent:** `4f1c788ab9b34a9e911d7f6ede15208c5ecbc883`
- **Canonical path:** `/Volumes/Jack-Dev/Projects/remoteorbit`
- **Release target:** `v0.2.14` / Build `43`
- **Release branch:** `codex/release-v0.2.14-baseline`
- **Release commit:** `6208266122414db3f3caf5852585eb24ed1b1a71`
- **Release PR:** `#21`

## Accepted audit evidence
PR #21 passed independent Web audit. The candidate contains exactly one release commit and exactly two changed files: `RELEASE_NOTES_v0.2.14.md` and `remote-orbit/Packaging/Info.plist`. The version/build bump is `0.2.13/42 -> 0.2.14/43`. No product or test source changed.

The candidate passed focused voice suites, 394/394 full Swift tests, 3/3 self-tests, package identity/source-stamp checks, Universal-2 architecture and app codesign. The bundled `RemoteOrbitAudio.driver` blocker was resolved by building the ignored artifact from the pinned driver build script; the packaged driver is present, Universal 2 and codesign PASS. The installed/running app and installed driver were not changed.

## Authorized publication steps
1. Fresh-check `main` and PR #21 head identity.
2. Merge PR #21 without altering the audited release payload.
3. Verify merged `main` contains the release commit semantics and only the expected release payload in addition to control-plane changes.
4. Create tag `v0.2.14` at the accepted merged release state.
5. Publish the GitHub Release using `RELEASE_NOTES_v0.2.14.md` as the release body and the existing approved release artifact procedure.
6. Record final release/tag/merge identities in the control plane.

## Prohibited
No new product/test edits. No rebase or rewrite of the audited release commit unless a fresh audit is performed. Do not install/replace `/Applications/RemoteOrbit.app` or the audio driver, restart RemoteOrbit/CoreAudio, change TCC/settings/mappings, or perform unrelated lifecycle cleanup as part of publication.

## Deferred known issue
Codex short Voice Chat local/external microphone capture resumption after remote LONG remains deferred. v0.2.14 must not claim this behavior is fixed or independently accepted.
