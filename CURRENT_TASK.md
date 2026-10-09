# RemoteOrbit Current Task

## Current task — FINAL v0.2.14 PUBLICATION

- **Status:** PR #21 MERGED / CREATE TAG + GITHUB RELEASE + DMG
- **Task ID:** `RO-RUNTIME-BASELINE-RELEASE-035`
- **Control parent:** `46dc94f58e67d5da38420047f009d3f311321108`
- **Canonical path:** `/Volumes/Jack-Dev/Projects/remoteorbit`
- **Release target:** `v0.2.14` / Build `43`
- **Release tag target:** `46dc94f58e67d5da38420047f009d3f311321108`
- **Merged PR:** `#21`
- **Audited release commit:** `6208266122414db3f3caf5852585eb24ed1b1a71`

## Goal
Complete publication only. The product baseline and release payload are already accepted and merged. No new code or behavior change is authorized.

## Required publication actions
1. Fresh-sync canonical main and verify it contains the controlled merge.
2. Verify tag `v0.2.14` does not already exist.
3. Create annotated or lightweight tag `v0.2.14` pointing exactly to `46dc94f58e67d5da38420047f009d3f311321108`, then push that tag.
4. From an exact checkout of the tag target, build the normal DMG using the repository release packaging flow. The packaging script may rebuild the ignored driver artifact; this is build-only and must not install it.
5. Verify DMG exists, record SHA-256, and verify the packaged app/driver identity remains `0.2.14` / Build `43`, Universal 2, codesign PASS.
6. Publish a GitHub Release named `RemoteOrbit v0.2.14`, using `RELEASE_NOTES_v0.2.14.md` as the body, tag `v0.2.14`, and attach `RemoteOrbit-0.2.14.dmg`.
7. Verify the published release is non-draft, non-prerelease, tag is correct, and uploaded asset digest/size are recorded.
8. Update control plane with final merge/tag/release identities and close Task 035.

## Prohibited
No product/test edits. No tag retargeting after creation. No installation/replacement of `/Applications/RemoteOrbit.app` or the audio driver. No RemoteOrbit/CoreAudio restart. No TCC/settings/mapping changes. No lifecycle cleanup.

## Deferred known issue
Codex short Voice Chat local/external microphone capture resumption after remote LONG remains deferred and is not fixed by v0.2.14.
