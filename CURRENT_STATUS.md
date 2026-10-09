# CURRENT_STATUS

Last updated: 2026-10-09
State: TASK 035 WEB AUDIT PASS / RELEASE PR READY / MERGE NOT YET AUTHORIZED
Repository: `Lost0rz/RemoteOrbit`

## Task 035 accepted runtime baseline
The installed/running RemoteOrbit app remains the accepted product baseline:
- installed app: `/Applications/RemoteOrbit.app`;
- Bundle ID: `com.lost0rz.RemoteOrbit`;
- installed version/build: `0.2.13` / `42`;
- installed source stamp: `f938b919e288a481f5eacaf9aad9c254dcf0cffe`;
- installed executable SHA-256: `104d4bf0cad8f7316ceea8c8e21568737d3ba3eea0f3c44207107a1159eb850e`;
- running PID observed during Task 035: `39949`;
- installed runtime product-equivalent to accepted main: YES.

No installed app, running process, driver, CoreAudio, TCC, settings, mapping, product source, or test source mutation occurred during release preparation.

## v0.2.14 release candidate
- release branch: `codex/release-v0.2.14-baseline`;
- release commit: `6208266122414db3f3caf5852585eb24ed1b1a71`;
- PR: `#21` (`Release RemoteOrbit v0.2.14 baseline`), OPEN, non-draft, mergeable;
- PR base: `main`;
- PR head: `codex/release-v0.2.14-baseline`;
- changed files: exactly `RELEASE_NOTES_v0.2.14.md` and `remote-orbit/Packaging/Info.plist`;
- version/build: `0.2.14` / `43`;
- product source changes: NONE;
- test source changes: NONE.

Validation already accepted from the executor:
- focused voice suites: PASS;
- full Swift suite: 394/394 PASS;
- self-tests: 3/3 PASS;
- package build: PASS;
- packaged app Bundle ID/version/build/source stamp: PASS;
- Universal 2 (`x86_64 arm64`): PASS;
- app codesign: PASS;
- rebuilt bundled `RemoteOrbitAudio.driver`: present, correct Bundle ID, Universal 2, codesign PASS;
- release worktree clean after packaging;
- local/remote release branch heads match.

## Independent Web audit
Web independently verified PR #21 is OPEN, non-draft and mergeable at head `6208266122414db3f3caf5852585eb24ed1b1a71`, and that the PR changes exactly two files. The patches are limited to release notes plus the version/build bump `0.2.13/42 -> 0.2.14/43`. The release notes correctly preserve the accepted dual-receiver behavior and explicitly retain the deferred Codex short-mode local-microphone-resume uncertainty without claiming it fixed.

No GitHub commit status checks are currently reported for the release commit; this is recorded as an observed absence of remote status checks, not as a failure of the local validation evidence above.

## Deferred known issue
Codex short Voice Chat uses the local/external microphone path for the short action; remote LONG takes over with remote audio. Local microphone capture resumption after remote LONG remains `KNOWN_DEFERRED / NOT FIXED / NOT INDEPENDENTLY ACCEPTED` and is not a v0.2.14 blocker for the frozen baseline.

## Current boundary
Independent Web audit: PASS.

Merge, tag creation, GitHub Release publication, DMG upload, installed-runtime replacement, driver installation, CoreAudio restart, TCC changes, additional product development, and lifecycle cleanup are NOT authorized until the user explicitly authorizes the next release transition.
