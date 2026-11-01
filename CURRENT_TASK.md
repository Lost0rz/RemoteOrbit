# RemoteOrbit Current Task

## RO-RELEASE-048 — Publish RemoteOrbit v0.2.15

Status: `CLOSED / RELEASE_PUBLISHED`
TASK_CLASS: `RELEASE / DISTRIBUTION`
Repository: `Lost0rz/RemoteOrbit`
Start control parent: `7f1c763e60db8c9ecc4a696f4246d3ee9eaaea1a`
Exact release target: `7f1c763e60db8c9ecc4a696f4246d3ee9eaaea1a`
Version: `0.2.15`
Build: `44`
Tag: `v0.2.15`
Release id: `430474517`

## Objective result

PASS. The accepted RemoteOrbit baseline was published as final GitHub Release `v0.2.15`, with the tag fixed to the exact pre-release-control baseline and with a newly built DMG plus checksum asset.

## Completed scope

1. Added durable `RELEASE_NOTES_v0.2.15.md` describing the accepted baseline and changes since v0.2.14.
2. Authorized and used a bounded one-shot GitHub Actions release workflow on the repository-scoped RemoteOrbit Mac runner.
3. Checked out and verified the exact release baseline independently from the release-control head.
4. Re-ran protocol self-tests and the full Swift test suite against that exact baseline.
5. Built the pinned RemoteOrbitAudio driver, Universal 2 RemoteOrbit app and release DMG through existing repository packaging scripts.
6. Verified version `0.2.15`, Build `44`, embedded source head, Universal 2 architecture and code signature.
7. Generated a SHA-256 checksum for the DMG.
8. Created final GitHub Release `RemoteOrbit v0.2.15` and tag `v0.2.15`.
9. Uploaded:
   - `RemoteOrbit-0.2.15.dmg`
   - `RemoteOrbit-0.2.15.dmg.sha256`
10. Re-read the published Release and tag from GitHub and verified the tag resolves exactly to `7f1c763e60db8c9ecc4a696f4246d3ee9eaaea1a`.
11. Removed the one-shot release workflow from live `main` at closeout; it is not a durable release authority.

## Published evidence

- Release workflow run: `41292366775` — SUCCESS
- GitHub Release id: `430474517`
- DMG SHA-256: `18fdb5c2eed873e195f86d635e927b11707ef201fc723c0cd03cb675ffd57676`
- Release state: final, non-draft, non-prerelease
- Tag target: exact authorized baseline

## Preserved boundaries

- No Swift/product behavior change.
- No version bump beyond existing `0.2.15` / Build `44`.
- No tag movement away from the authorized baseline.
- No user-machine installation, driver replacement, CoreAudio restart, TCC change or default-device mutation.
- CI/release automation is not treated as a substitute for user-owned real-hardware/runtime acceptance.

## Closeout

Task 048 is closed. `RELEASE_NOTES_v0.2.15.md` remains as release history; the temporary release workflow is removed. Any further product, runtime, packaging, install, release or repository-lifecycle mutation requires a new governed task/control transition.

DOCUMENT_ALIGNMENT: `UPDATED`
