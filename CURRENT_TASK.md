# RemoteOrbit Current Task

## Current task — RUNTIME BASELINE RELEASE WEB AUDIT

- **Status:** WEB AUDIT PASS / WAITING FOR USER RELEASE AUTHORIZATION
- **Task ID:** `RO-RUNTIME-BASELINE-RELEASE-035`
- **Control parent:** `73be7edb38522a19880c76c01897c20ade3afeaa`
- **Canonical path:** `/Volumes/Jack-Dev/Projects/remoteorbit`
- **Release target:** `v0.2.14` / Build `43`
- **Release branch:** `codex/release-v0.2.14-baseline`
- **Release commit:** `6208266122414db3f3caf5852585eb24ed1b1a71`
- **Release PR:** `#21`

## Accepted execution evidence
Task 035 verified that the installed/running `0.2.13 (42)` app stamped from `f938b919e288a481f5eacaf9aad9c254dcf0cffe` is product-equivalent to the accepted main product tree. Release preparation changed only `RELEASE_NOTES_v0.2.14.md` and `remote-orbit/Packaging/Info.plist`.

The release candidate passed the focused voice suites, 394/394 full Swift tests, 3/3 self-tests, packaging identity/version/build/source-stamp checks, Universal-2 architecture verification and app codesign. The missing bundled-driver blocker was then remediated only by building the ignored `remote-orbit-audio-driver/build/RemoteOrbitAudio.driver` artifact from the existing pinned build script; the driver was not installed. Repackaging then embedded the driver successfully and its Bundle ID, architectures and codesign verified.

The release worktree remained clean after packaging and the committed release HEAD remained `6208266122414db3f3caf5852585eb24ed1b1a71`. The branch was pushed and PR #21 was created against `main`.

## Independent Web audit result
PASS.

Web independently verified:
- PR #21 is OPEN, non-draft and mergeable;
- base is `main`;
- head is `codex/release-v0.2.14-baseline` at `6208266122414db3f3caf5852585eb24ed1b1a71`;
- PR contains one commit and exactly two changed files;
- the only changed paths are `RELEASE_NOTES_v0.2.14.md` and `remote-orbit/Packaging/Info.plist`;
- `Info.plist` changes only `0.2.13 -> 0.2.14` and `42 -> 43`;
- release notes accurately describe the accepted dual-receiver baseline and explicitly preserve the unresolved Codex short-mode local-microphone-resume issue as deferred, not fixed or validated;
- no GitHub commit status checks are currently reported for the release commit.

## Deferred known issue
Codex short Voice Chat local/external microphone capture resumption after remote LONG remains deferred and out of scope. v0.2.14 must not claim this behavior is fixed or independently accepted.

## Current stop boundary
WAITING FOR USER RELEASE AUTHORIZATION.

Do not merge PR #21, create/move tag `v0.2.14`, publish a GitHub Release, upload a DMG, install/replace `/Applications/RemoteOrbit.app`, install/replace the audio driver, restart RemoteOrbit/CoreAudio, change TCC/settings/mappings, modify product/test source, or perform lifecycle cleanup unless a new explicitly authorized release transition is recorded in `CURRENT_STATUS.md` and `CURRENT_TASK.md` together.
