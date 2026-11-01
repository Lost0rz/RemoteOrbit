# CURRENT_STATUS

Last updated: 2026-11-01
State: `RO-RELEASE-048 — CLOSED / RELEASE_PUBLISHED`
Repository: `Lost0rz/RemoteOrbit`
Remote authority: `main`
Release target baseline: `7f1c763e60db8c9ecc4a696f4246d3ee9eaaea1a`

## Accepted release baseline

- RemoteOrbit `v0.2.15` is published as a final GitHub Release.
- Version: `0.2.15`
- Build: `44`
- Tag: `v0.2.15`
- Tag target: `7f1c763e60db8c9ecc4a696f4246d3ee9eaaea1a`
- GitHub Release id: `430474517`
- Release is non-draft and non-prerelease.
- The release target is the exact Task 047 closeout baseline; subsequent release-control commits are not part of the product tag.

## Published assets

- `RemoteOrbit-0.2.15.dmg`
  - GitHub asset size: `3,637,708` bytes
  - SHA-256: `18fdb5c2eed873e195f86d635e927b11707ef201fc723c0cd03cb675ffd57676`
- `RemoteOrbit-0.2.15.dmg.sha256`

`RELEASE_NOTES_v0.2.15.md` is retained on `main` as the durable repository copy of the published release notes.

## Release verification

One-shot release workflow run `41292366775`: `SUCCESS`.

Against the exact release target baseline:
- release identity check: PASS
- protocol self-tests: PASS
- full Swift tests: PASS
- RemoteOrbitAudio driver + DMG build: PASS
- packaged version/build/source-head verification: PASS
- Universal 2 architecture verification: PASS
- code-signature verification: PASS
- GitHub Release creation: PASS
- DMG/checksum upload: PASS
- published tag/release/assets verification: PASS

Direct GitHub re-read confirms `refs/tags/v0.2.15` resolves exactly to `7f1c763e60db8c9ecc4a696f4246d3ee9eaaea1a`.

## Repository state after release

- The bounded one-shot `.github/workflows/release-v0.2.15.yml` automation is removed by Task 048 closeout and is not retained as a standing release authority.
- The durable routine CI workflow remains `.github/workflows/remoteorbit-ci.yml`.
- No Swift/product behavior was changed by Task 048.
- No user-machine app/driver/CoreAudio/TCC/default-device state was mutated by this release task.
- Main may contain governance/release-note commits after the v0.2.15 tag; those do not change the released source baseline.

## Current documentation authority

- `README.md` — current product/repository landing page.
- `SETUP_NOTES.md` — install, validation and troubleshooting guide.
- `docs/DOMAIN_MAP.md` — current derived Domain/capability navigation projection.
- `docs/diagnostics/ADR-0001..0003` — durable diagnostic architecture decisions.
- `docs/incidents/` and root `RELEASE_NOTES_v*.md` — historical/release evidence; they do not override current product authority.

## Next state

No product implementation or release mutation is authorized by this closeout. Any further source/runtime/packaging/install/release or repository-lifecycle mutation requires a new governed `CURRENT_TASK.md` transition.

DOCUMENT_ALIGNMENT: `UPDATED`
