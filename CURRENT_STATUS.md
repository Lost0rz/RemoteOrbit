# CURRENT_STATUS

Last updated: 2026-10-28
State: RELEASE V0.2.15 — REMOTE MACOS ACTIONS RELEASE ACTIVE / CONTROL RECONCILED
Repository: Lost0rz/RemoteOrbit

## Repository authority

- Canonical development repository: `/Volumes/Jack-Dev/Projects/remoteorbit`.
- Canonical branch: `main`.
- Verified origin: `https://github.com/Lost0rz/RemoteOrbit.git`.
- Release-transition control head on `main`: `8f71cde21df6ca1f5a831a8b5390abbfde61e9d9`.
- Active release branch: `codex/release-v0.2.15`.
- PR #25: `Release RemoteOrbit v0.2.15`.
- Previous public release: `v0.2.14` / build `43`.
- Target release: `v0.2.15` / build `44` / Universal 2.
- Task 038-B product/evidence work is terminal; root-cause status remains `NARROWED_NOT_ESTABLISHED`.
- `038-C/D/E/F` remain deferred.

## Control reconciliation

A split control-plane write was detected at branch head `d47eb1fd258f850f2f1ed8a6d7b8b7fd66997f46`: `CURRENT_STATUS.md` advanced before `CURRENT_TASK.md` and the workflow were published. No release build, merge, tag or publication was allowed from that inconsistent state.

This state supersedes that split write through one atomic direct-child commit that updates `CURRENT_STATUS.md` and `CURRENT_TASK.md` together and adds the authorized release workflow. That atomic commit is the authoritative remote-release transition.

## Owner release decision

The owner explicitly requested that release preparation and publication be completed remotely rather than on the local Mac.

The repository previously had no `.github/workflows` release automation. A bounded release workflow is authorized for this release so GitHub's hosted Apple-silicon macOS runner can execute the same repository-native Swift/driver/app/DMG packaging flow before merge and publication.

Authorized remote release workflow:

`.github/workflows/release-v0.2.15.yml`

Runner: `macos-15` (GitHub-hosted arm64 macOS).

## Release scope

Release metadata already prepared:

- `remote-orbit/Packaging/Info.plist` -> `0.2.15 (44)`;
- `RELEASE_NOTES_v0.2.15.md`;
- `CURRENT_STATUS.md` / `CURRENT_TASK.md` lifecycle records.

The remote-release transition additionally authorizes only the release workflow above and narrowly justified packaging-only corrections if fresh hosted-macOS evidence reproduces a packaging blocker.

No product audio/BLE/HID/Option/shortcut corrective is authorized.

## Included accepted work since v0.2.14

- Task 038-A rapid re-press reliability work;
- shortcut-recorder exclusive-capture/restoration hardening;
- opt-in BLE/decode/PCM/AudioPipe continuity correlation;
- real-time probe observer-effect corrections;
- stable AUDIO_START-before-HID capture/session correlation;
- durable 038-B evidence conclusions.

## Diagnostic boundary

The 038-B continuity ledger remains opt-in. Normal app launch does not enable it automatically.

Post-release observation must use:

`REMOTE_ORBIT_CONTINUITY_EVIDENCE=1`

The release does not claim the continuity root cause is fixed.

## Remote release gate

The GitHub-hosted macOS workflow must, in order:

1. verify exact branch/version/build identity;
2. run `swift test`;
3. run `remote-orbit/run-self-tests.sh`;
4. run repository-native `package-dmg.sh` on Apple-silicon macOS;
5. verify candidate app bundle/version/build, arm64+x86_64 executable, codesign/designated requirement, embedded source head and DMG contents/SHA-256;
6. only after candidate PASS, mark PR #25 ready and merge it;
7. checkout the exact merge commit and rebuild the DMG so `RemoteOrbitDiagnosticSourceHead` equals the merged release commit;
8. verify the merged artifact again;
9. create annotated tag `v0.2.15` at that exact merge commit;
10. publish GitHub Release `RemoteOrbit v0.2.15` with `RemoteOrbit-0.2.15.dmg`;
11. re-fetch workflow/release/tag/asset evidence and then update the control plane with final provenance.

Any failed test/build/package/provenance/merge/tag/release step is a STOP. The workflow must not publish a release after an unresolved failure.

## Current next action

Publish the reconciled remote-release transition to `codex/release-v0.2.15`, observe the hosted macOS run, and accept v0.2.15 as released only after tag/release/DMG provenance is independently re-fetched.
