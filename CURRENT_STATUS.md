# CURRENT_STATUS

Last updated: 2026-11-01
State: `RO-RELEASE-048 — ACTIVE / RELEASE_AUTHORIZED`
Repository: `Lost0rz/RemoteOrbit`
Remote authority: `main`
Control parent: `7f1c763e60db8c9ecc4a696f4246d3ee9eaaea1a`
Release target baseline: `7f1c763e60db8c9ecc4a696f4246d3ee9eaaea1a`

## Accepted baseline

- Task 047 documentation/domain audit is closed and accepted.
- The exact source baseline authorized for this release is `7f1c763e60db8c9ecc4a696f4246d3ee9eaaea1a`.
- Source version metadata at that baseline is `0.2.15` / Build `44`.
- GitHub's latest published release before this task is `v0.2.14`; `v0.2.15` does not yet exist.
- The requested operation is release publication only; no product behavior redesign is authorized.

## Active release work

Task 048 is authorized to publish `RemoteOrbit v0.2.15` from the exact baseline above.

Authorized release mutations:
- add/update `RELEASE_NOTES_v0.2.15.md`;
- add a bounded one-shot GitHub Actions release workflow if required to perform authenticated release publication;
- build and verify the existing Universal 2 app + RemoteOrbitAudio driver + DMG using repository scripts;
- run the repository protocol/Swift tests required by the release gate;
- create tag `v0.2.15` targeting the exact release baseline;
- create the GitHub Release and upload `RemoteOrbit-0.2.15.dmg` plus checksum evidence;
- remove any one-shot release workflow after successful publication;
- reconcile controls and close the task after direct release verification.

## Safety boundary

- No Swift/product behavior change.
- No runtime installation, TCC, default-device or CoreAudio mutation on the user's machines.
- No version bump beyond existing `0.2.15` / Build `44`.
- Do not move the release tag away from the exact authorized baseline.
- Release success requires direct GitHub evidence that the release and asset exist.

## Release gate

Before publication, the release executor must verify:
- protocol self-tests PASS;
- full Swift tests PASS;
- package build succeeds;
- packaged executable is Universal 2;
- packaged metadata is `0.2.15` / Build `44`;
- DMG exists and has a recorded SHA-256 checksum.

## Current state

`ACTIVE / RELEASE_AUTHORIZED`

DOCUMENT_ALIGNMENT: `UNCHANGED`
