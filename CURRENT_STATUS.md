# CURRENT_STATUS

Last updated: 2026-10-28
State: RELEASE V0.2.15 — BLOCKED_BEFORE_HOSTED_MACOS_RUNNER_ASSIGNMENT
Repository: Lost0rz/RemoteOrbit

## Repository authority

- Canonical development repository: `/Volumes/Jack-Dev/Projects/remoteorbit`.
- Canonical branch: `main`.
- Verified origin: `https://github.com/Lost0rz/RemoteOrbit.git`.
- Release-transition control head on `main`: `8f71cde21df6ca1f5a831a8b5390abbfde61e9d9`.
- Active release branch: `codex/release-v0.2.15`.
- PR #25: `Release RemoteOrbit v0.2.15`.
- Target release: `v0.2.15` / build `44` / Universal 2.
- PR remains unmerged; tag `v0.2.15` and GitHub Release `RemoteOrbit v0.2.15` must not be claimed until a verified DMG exists.
- 038-B root-cause status remains `NARROWED_NOT_ESTABLISHED`; `038-C/D/E/F` remain deferred.

## Control reconciliation

A split control-plane write at `d47eb1fd258f850f2f1ed8a6d7b8b7fd66997f46` was superseded by atomic control transition `ed0cd313f6d754bdde98fcad2ea2115f7889b005`, which updated `CURRENT_STATUS.md` and `CURRENT_TASK.md` together and added the bounded hosted release workflow. No release mutation occurred from the split state.

## Remote hosted-release attempt

The owner explicitly authorized a fully remote release. The repository had no prior GitHub Actions workflow, so a release-specific workflow was added at `ed0cd313f6d754bdde98fcad2ea2115f7889b005` to use GitHub-hosted `macos-15` and perform tests, driver/app/DMG packaging, merge, exact-merge rebuild, tag and GitHub Release publication only after all gates passed.

Observed GitHub Actions evidence:

- workflow run: `40697742964`
- workflow: `RemoteOrbit v0.2.15 remote release`
- head: `ed0cd313f6d754bdde98fcad2ea2115f7889b005`
- job: `122848932358`
- requested label: `macos-15`
- status: `completed`
- conclusion: `failure`
- `runner_id = 0`
- `runner_name = ""`
- `steps = []`
- job interval: `2026-10-28T13:34:56Z`–`13:34:58Z`

Therefore no repository checkout, test, Swift compilation, driver build, app build, DMG build, PR merge, tag or release-publication step executed.

GitHub's current hosted-runner documentation lists `macos-15` as a valid arm64 hosted runner label for private repositories. The observed failure is therefore classified at the hosted-runner assignment/platform boundary, not as a RemoteOrbit build/test failure. The exact account-side reason (for example billing/spending/availability policy) is not exposed by the available repository API evidence and remains unverified.

## Release metadata already prepared

- `remote-orbit/Packaging/Info.plist` -> `0.2.15 (44)`;
- `RELEASE_NOTES_v0.2.15.md`;
- release control records.

No product audio/BLE/HID/Option/shortcut corrective was added.

## Safety disposition

Because no macOS runner was assigned, there is no verified `RemoteOrbit-0.2.15.dmg`. Publishing a source-only GitHub Release or reusing a previous DMG would not satisfy the owner's goal of running the new merged code and would break release provenance.

The push-triggered release workflow is removed from the active branch after this failed platform attempt so unrelated control updates do not repeatedly launch a known-blocked hosted job. The failed workflow remains preserved in Git history at `ed0cd313f6d754bdde98fcad2ea2115f7889b005`.

## Diagnostic boundary

The 038-B continuity ledger remains opt-in:

`REMOTE_ORBIT_CONTINUITY_EVIDENCE=1`

v0.2.15 must not claim that the audio-continuity root cause is fixed.

## Current next action

STOP release publication at the hosted-runner boundary. Resume only after a macOS execution surface is actually available for this repository (for example GitHub-hosted macOS becomes assignable, or a RemoteOrbit-scoped self-hosted macOS runner is explicitly registered). Then re-run the existing release gates before merge/tag/publication.
