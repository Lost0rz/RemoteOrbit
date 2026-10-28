# RemoteOrbit Current Task

## RO-RELEASE-V0.2.15 — Stability + Diagnostics Baseline Release

Status: `REMOTE MACOS ACTIONS RELEASE ACTIVE / CONTROL RECONCILED`

Repository: `Lost0rz/RemoteOrbit`

Canonical repository: `/Volumes/Jack-Dev/Projects/remoteorbit`

## Objective

Publish RemoteOrbit `v0.2.15` / build `44` as the next stable diagnostics baseline after merged 038-A / 038-B work, using a GitHub-hosted Apple-silicon macOS release workflow so the owner does not need to run the release locally.

This is a release task, not an audio corrective task.

## Release authority

- Control-transition head on `main`: `8f71cde21df6ca1f5a831a8b5390abbfde61e9d9`.
- Active release branch: `codex/release-v0.2.15`.
- Release target: `v0.2.15`, build `44`, Universal 2.
- PR #25: `Release RemoteOrbit v0.2.15`.
- Previous release: `v0.2.14`, build `43`.
- 038-B root-cause verdict remains `NARROWED_NOT_ESTABLISHED`.

## Control reconciliation

A split control write was detected at `d47eb1fd258f850f2f1ed8a6d7b8b7fd66997f46`. No build/merge/tag/release action is authorized from that inconsistent state.

The authoritative transition must be the next direct-child commit that updates this file and `CURRENT_STATUS.md` together and adds `.github/workflows/release-v0.2.15.yml`. That atomic commit supersedes the split write without rewriting history.

## Owner-authorized remote release transition

The owner explicitly requested that files be updated remotely and the release be published remotely.

The project had no existing GitHub Actions release workflow. This task authorizes one release-specific workflow:

`.github/workflows/release-v0.2.15.yml`

It may run only for `codex/release-v0.2.15` and may use GitHub's repository token only for:

- marking PR #25 ready after hosted release verification passes;
- merging PR #25 after the verified candidate head is rechecked;
- pushing annotated tag `v0.2.15` at the exact merge commit;
- creating GitHub Release `RemoteOrbit v0.2.15`;
- uploading `RemoteOrbit-0.2.15.dmg`.

## Authorized changes

The release branch may contain only:

1. `remote-orbit/Packaging/Info.plist` with `0.2.15 (44)`;
2. `RELEASE_NOTES_v0.2.15.md`;
3. `CURRENT_STATUS.md` / `CURRENT_TASK.md` lifecycle/provenance changes;
4. `.github/workflows/release-v0.2.15.yml` for this bounded remote release;
5. a narrowly justified packaging-only correction if fresh GitHub-hosted macOS evidence reproduces a concrete packaging blocker.

No product source corrective is authorized.

## Release verification contract

The hosted macOS workflow must stop on any failure and must complete these gates before publication:

1. run on GitHub-hosted `macos-15` arm64;
2. verify branch, version `0.2.15`, build `44`;
3. run `swift test`;
4. run `remote-orbit/run-self-tests.sh`;
5. run `package-dmg.sh`, including the established driver and app packaging flow;
6. verify candidate app:
   - bundle `com.lost0rz.RemoteOrbit`;
   - version/build `0.2.15 (44)`;
   - executable contains `arm64` and `x86_64`;
   - codesign verification passes;
   - designated requirement remains `identifier "com.lost0rz.RemoteOrbit"`;
   - `RemoteOrbitDiagnosticSourceHead` equals the exact candidate head;
7. verify candidate DMG mounts with `RemoteOrbit.app`, `Applications`, and `Documentation`;
8. recheck PR #25 head still equals the verified candidate;
9. mark PR #25 ready and merge using normal merge semantics;
10. checkout the exact merge commit and rebuild the DMG;
11. verify the rebuilt app's embedded diagnostic source head equals the merge commit;
12. compute final DMG SHA-256;
13. create annotated tag `v0.2.15` at the exact merge commit;
14. publish GitHub Release `RemoteOrbit v0.2.15` with the rebuilt DMG and `RELEASE_NOTES_v0.2.15.md`.

## Diagnostic observation after release

Continuity evidence stays opt-in:

`REMOTE_ORBIT_CONTINUITY_EVIDENCE=1`

Do not make the ledger always-on in normal product launch.

## Stop conditions

STOP if:

- branch/PR head drifts after candidate verification;
- product source changes become necessary;
- test/self-test fails;
- driver/app/DMG packaging fails for an unresolved reason;
- universal architecture, bundle version, codesign, designated requirement, or embedded source-head verification fails;
- PR merge fails;
- tag already exists unexpectedly or points elsewhere;
- GitHub Release/asset creation fails;
- release artifact provenance cannot be established.

A failed hosted run does not authorize bypassing the failed gate. A packaging-only correction requires fresh failure evidence and must remain packaging-only.

## Non-goals

- No remaining audio root-cause fix.
- No finer-grained continuity probe.
- No 038-C/D/E/F.
- No TCC/CoreAudio/runtime mutation.
- No speculative performance tuning.
- No always-on diagnostics change.

## Completion

Complete only when:

- PR #25 is merged from a hosted-macOS-verified head;
- annotated tag `v0.2.15` resolves to the exact release merge commit;
- GitHub Release `RemoteOrbit v0.2.15` is published;
- asset `RemoteOrbit-0.2.15.dmg` is attached;
- tag/release/asset provenance is independently re-fetched;
- control records are updated with the final release identity and remaining `NARROWED_NOT_ESTABLISHED` diagnostic state.
