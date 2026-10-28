# CURRENT_STATUS

Last updated: 2026-10-28
State: RELEASE V0.2.15 — LOCAL_DMG_SOAK_CANDIDATE_ACTIVE
Repository: Lost0rz/RemoteOrbit

## Repository authority

- Canonical development repository: `/Volumes/Jack-Dev/Projects/remoteorbit`.
- Canonical branch: `main`.
- Verified origin: `https://github.com/Lost0rz/RemoteOrbit.git`.
- Active candidate branch: `codex/release-v0.2.15`.
- PR #25: `Release RemoteOrbit v0.2.15` remains Draft/Open/Unmerged.
- Candidate version: `0.2.15` / build `44` / Universal 2.
- Public release state: NOT RELEASED.
- No `v0.2.15` tag or GitHub Release is authorized during the soak period.
- Task 038-B remains terminal with `ROOT_CAUSE_STATUS = NARROWED_NOT_ESTABLISHED`; `038-C/D/E/F` remain deferred.

## Owner decision

The owner changed the release plan: do not continue fighting the hosted CI path and do not publish v0.2.15 yet.

Instead:

1. build a verified local DMG from the current candidate branch;
2. install/run that candidate locally for a longer real-world observation period;
3. collect fresh continuity logs under the exact candidate runtime identity;
4. review stability and logs after the soak period;
5. only then decide whether to merge/tag/publish v0.2.15 or begin another corrective cycle.

Durable soak plan:

`docs/diagnostics/2026-10-28-v0.2.15-local-soak-plan.md`

## Hosted CI disposition

The remote macOS release attempt never reached repository execution because GitHub did not assign a runner (`runner_id=0`, `steps=[]`). Repeated reruns did not change that boundary.

That hosted-release path is no longer the active next action. The push-triggered release workflow has already been removed from the live candidate branch, while the failed attempt remains in Git history as evidence.

## Candidate scope

Already prepared:

- `remote-orbit/Packaging/Info.plist` -> `0.2.15 (44)`;
- `RELEASE_NOTES_v0.2.15.md`;
- 038-A / shortcut-recorder / 038-B accepted code already present in the candidate lineage;
- no new speculative AudioPipe/BLE corrective.

## Local packaging gate

The local Mac executor must build from the live candidate branch and prove:

- `swift test` PASS;
- `remote-orbit/run-self-tests.sh` PASS;
- driver build succeeds;
- `package-dmg.sh` succeeds;
- packaged app is `com.lost0rz.RemoteOrbit`;
- version/build = `0.2.15 (44)`;
- executable contains arm64 + x86_64;
- codesign/designated requirement is valid;
- embedded `RemoteOrbitDiagnosticSourceHead` equals the exact candidate commit used for the build;
- DMG mounts and contains the expected app/Applications/Documentation structure;
- DMG SHA-256 is recorded.

A packaging-only corrective is allowed only if a fresh packaging failure directly requires it and product/runtime semantics remain unchanged.

## Observation mode

Continuity evidence remains opt-in:

`REMOTE_ORBIT_CONTINUITY_EVIDENCE=1`

The local candidate should be used naturally. Do not manufacture weak Bluetooth, synthetic triggers, artificial load, or deliberate underruns.

Later analysis must bind logs to:

- app path;
- bundle ID;
- version/build;
- executable SHA-256;
- embedded source head;
- diagnostic environment;
- observation window.

## Current next action

Build and verify the local v0.2.15 DMG candidate, install it on the owner's Mac, start the opt-in diagnostic runtime, and enter a longer soak period. Do not merge PR #25, create `v0.2.15`, or publish GitHub Release during this phase.
