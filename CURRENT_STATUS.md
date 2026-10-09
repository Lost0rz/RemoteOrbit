# CURRENT_STATUS

Last updated: 2026-10-09
State: TASK 035 CLOSED / v0.2.14 PUBLISHED AND WEB-ACCEPTED
Repository: `Lost0rz/RemoteOrbit`

## Accepted release baseline
- Task ID: `RO-RUNTIME-BASELINE-RELEASE-035`.
- PR #21: CLOSED / MERGED.
- Controlled merge commit: `46dc94f58e67d5da38420047f009d3f311321108`.
- Annotated tag: `v0.2.14`; tag object `5eb34cc1cf36c3dcfdef3df7d0c430262ed7b6c2` peels exactly to the controlled merge commit.
- Public GitHub Release: https://github.com/Lost0rz/RemoteOrbit/releases/tag/v0.2.14
- Release name: `RemoteOrbit v0.2.14`; draft: NO; prerelease: NO.
- Release asset: `RemoteOrbit-0.2.14.dmg`, 5,928,820 bytes, digest `sha256:6f45831c6cc1d0fcca71e7d7db6b85e6c0864cc778a1fac730921a0eaa0bc9fa`.

## Validation accepted
- Focused voice suites: PASS.
- Full Swift suite: 394/394 PASS.
- Self-tests: 3/3 PASS.
- Final DMG `hdiutil verify`: PASS.
- Packaged app: Bundle ID `com.lost0rz.RemoteOrbit`, version `0.2.14`, build `43`, source stamp `46dc94f58e67d5da38420047f009d3f311321108`, Universal 2, codesign PASS.
- Bundled `RemoteOrbitAudio.driver`: present, Universal 2, codesign PASS.
- Local DMG digest and GitHub release-asset digest/size match.
- Product source changes during release publication: NONE.
- Test source changes during release publication: NONE.
- Installed app/driver/runtime changes during publication: NONE.

## Independent Web closeout
Web independently verified the live release, tag object and peeled commit target, asset name/size/digest, and remote `main` publication closeout state. Task 035 is accepted and closed.

## Deferred known issue
Codex short Voice Chat local/external microphone capture resumption after remote LONG remains `KNOWN_DEFERRED / NOT FIXED / NOT INDEPENDENTLY ACCEPTED`. It is not part of the v0.2.14 acceptance claim.

## Remaining lifecycle boundary
The publication worktree `/private/tmp/remoteorbit-v0.2.14-publish` was retained after packaging. The pre-existing local `v0.2.8` tag conflict was not modified. Neither item is authorized for cleanup under this closed task. Any cleanup or further product work requires a new control-plane task.
