# RemoteOrbit Current Task

## RO-RELEASE-048 — Publish RemoteOrbit v0.2.15

Status: `ACTIVE / RELEASE_AUTHORIZED`
TASK_CLASS: `RELEASE / DISTRIBUTION`
Repository: `Lost0rz/RemoteOrbit`
Control parent: `7f1c763e60db8c9ecc4a696f4246d3ee9eaaea1a`
Exact release target: `7f1c763e60db8c9ecc4a696f4246d3ee9eaaea1a`
Version: `0.2.15`
Build: `44`
Tag: `v0.2.15`

## Objective

Publish the current accepted RemoteOrbit baseline as GitHub Release `v0.2.15`, using the exact pre-release-control baseline as the tag target and attaching a newly built DMG produced by the repository's existing packaging path.

## Authorized scope

1. Prepare durable release notes for v0.2.15.
2. Re-run release-gate verification against the exact target baseline.
3. Build the RemoteOrbitAudio driver, Universal 2 app, and DMG using existing repository scripts.
4. Verify packaged version/build, architecture, signing verification and SHA-256 checksum.
5. Create lightweight tag `v0.2.15` targeting exactly `7f1c763e60db8c9ecc4a696f4246d3ee9eaaea1a`.
6. Publish GitHub Release `RemoteOrbit v0.2.15` and attach `RemoteOrbit-0.2.15.dmg` and its checksum file.
7. Verify the published release/tag/assets through GitHub evidence.
8. Remove any one-shot release workflow introduced solely to perform this authenticated publication.
9. Update `CURRENT_STATUS.md` and `CURRENT_TASK.md` together at closeout.

## Release content boundary

The release should summarize the accepted changes since v0.2.14, especially:
- simplification to the single LONG-only remote voice contract and retirement of Persistent/Dual Receiver/Receiver-B/local-mic voice-button semantics;
- voice pipeline stability, rapid repress/release ownership and receiver-readiness corrections;
- audio data-plane/pll/outbound drain and RemoteOrbitAudio routing hardening;
- long-term diagnostics, bounded observability, read-only export and diagnostics gating;
- settings/product-surface simplification, icon/branding refresh and current documentation/domain authority;
- repository CI/governance baseline.

Do not claim unobserved user-runtime acceptance or root cause beyond accepted evidence.

## Non-goals

- No product source change.
- No new feature.
- No app installation or host runtime mutation.
- No release version change beyond v0.2.15 / Build 44.
- No release of a different commit if `main` advances.

## Completion gate

Task 048 closes only when:
- release-gate tests/build/package checks PASS;
- tag `v0.2.15` resolves to the exact authorized baseline;
- GitHub Release `v0.2.15` is published and non-draft/non-prerelease;
- DMG and checksum assets are present;
- release publication is re-read from GitHub;
- one-shot release automation, if used, is removed from live `main`;
- control files are reconciled in one final commit.

DOCUMENT_ALIGNMENT: `UNCHANGED`
