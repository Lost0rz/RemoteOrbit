# RemoteOrbit Current Task

## RO-RELEASE-V0.2.15 — Stability + Diagnostics Baseline Release

Status: `BLOCKED_BEFORE_HOSTED_MACOS_RUNNER_ASSIGNMENT`

Repository: `Lost0rz/RemoteOrbit`

Canonical repository: `/Volumes/Jack-Dev/Projects/remoteorbit`

## Objective

Publish RemoteOrbit `v0.2.15` / build `44` as the next stable diagnostics baseline so the owner can run the released build for a longer real-world observation period and later analyze fresh logs.

This remains a release task, not an audio corrective task.

## Release authority

- Control-transition head on `main`: `8f71cde21df6ca1f5a831a8b5390abbfde61e9d9`.
- Active release branch: `codex/release-v0.2.15`.
- PR #25: `Release RemoteOrbit v0.2.15`.
- Target: `v0.2.15`, build `44`, Universal 2.
- Previous release: `v0.2.14`, build `43`.
- 038-B root-cause verdict remains `NARROWED_NOT_ESTABLISHED`.

## Prepared release delta

Authorized release metadata already exists:

1. `remote-orbit/Packaging/Info.plist` -> `0.2.15 (44)`;
2. `RELEASE_NOTES_v0.2.15.md`;
3. `CURRENT_STATUS.md` / `CURRENT_TASK.md` lifecycle/provenance.

No product audio/BLE/HID/Option/shortcut corrective is authorized.

## Remote publication attempt

The owner explicitly requested a fully remote release. A bounded release workflow was added at atomic control head `ed0cd313f6d754bdde98fcad2ea2115f7889b005` to run on GitHub-hosted `macos-15` and gate all publication on successful tests/build/DMG provenance.

Fresh platform evidence:

- Actions run `40697742964`;
- job `122848932358`;
- requested runner label `macos-15`;
- conclusion `failure`;
- `runner_id=0`;
- empty runner name;
- zero executed steps;
- duration about two seconds.

No checkout or repository command ran. Therefore this is not evidence of a RemoteOrbit test/build/package failure. It is a hosted-runner assignment/platform blocker. The exact account-side cause is not established by the available repository evidence.

## Current authorization after blocker

STOP publication.

Do not:

- mark PR #25 ready or merge it;
- create `v0.2.15` tag;
- publish a source-only GitHub Release as a substitute for the missing DMG;
- reuse or relabel the v0.2.14 DMG;
- claim any Swift/self-test/app/DMG PASS from the failed hosted run;
- add product-code work to bypass the runner blocker.

The push-triggered workflow is removed from the active release branch after recording the failure so subsequent control-only pushes do not repeatedly execute a known-blocked job. The failed workflow remains recoverable from commit `ed0cd313f6d754bdde98fcad2ea2115f7889b005`.

## Resume gate

Release execution may resume only after a real macOS execution surface is available to this repository, such as:

- GitHub-hosted `macos-15` can actually be assigned; or
- a self-hosted `macOS/ARM64` runner is explicitly registered for `Lost0rz/RemoteOrbit`.

When resumed, restore/run the bounded release workflow or execute equivalent verified release gates:

1. `swift test`;
2. `remote-orbit/run-self-tests.sh`;
3. established driver/app/DMG packaging;
4. app identity/version/arm64+x86_64/codesign/designated-requirement/source-head checks;
5. DMG mount/content/SHA-256 checks;
6. only then merge PR #25;
7. rebuild from exact merge commit;
8. tag exact merge commit as `v0.2.15`;
9. publish `RemoteOrbit-0.2.15.dmg` with the GitHub Release;
10. independently re-fetch release/tag/asset provenance.

## Diagnostic observation after release

Continuity evidence remains opt-in:

`REMOTE_ORBIT_CONTINUITY_EVIDENCE=1`

Do not make the ledger always-on.

## Completion

This task is not complete. It completes only after a verified v0.2.15 DMG is published from the exact tagged release commit and the final control plane records that provenance.
