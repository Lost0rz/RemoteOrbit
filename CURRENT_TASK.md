# RemoteOrbit Current Task

## RO-RELEASE-V0.2.15 — Local DMG Soak Candidate

Status: `LOCAL_DMG_SOAK_CANDIDATE_ACTIVE`

Repository: `Lost0rz/RemoteOrbit`

Canonical repository: `/Volumes/Jack-Dev/Projects/remoteorbit`

## Objective

Build RemoteOrbit `0.2.15` / build `44` locally as a verified Universal 2 DMG candidate, install it on the owner's Mac, and run it naturally for a longer observation period before deciding whether the candidate should become the public `v0.2.15` release.

This is a local candidate/soak task. It is not a formal publication task and not a new audio corrective task.

## Authority

- Active branch: `codex/release-v0.2.15`.
- PR #25 remains Draft/Open/Unmerged.
- Candidate version/build: `0.2.15 (44)`.
- Previous public release: `v0.2.14 (43)`.
- 038-B root-cause verdict remains `NARROWED_NOT_ESTABLISHED`.
- Durable soak plan: `docs/diagnostics/2026-10-28-v0.2.15-local-soak-plan.md`.

## Authorized actions

1. Reconcile/fetch the live candidate branch.
2. Use one clean local candidate worktree.
3. Run release-proportional tests and self-tests.
4. Build the existing audio driver using the repository-supported script.
5. Build/package the app and DMG using the established repository scripts.
6. Apply only a narrowly justified packaging-only corrective if fresh local evidence proves one is required and product/runtime semantics are unchanged.
7. Verify candidate identity/provenance.
8. Install the verified candidate locally.
9. Launch the installed candidate with opt-in continuity evidence for the soak period.
10. Record runtime identity and later review fresh logs.
11. Update control records with local packaging/install identity and soak state.

## Required local packaging verification

Run the applicable repository release checks, including:

- `swift test`;
- `remote-orbit/run-self-tests.sh`;
- `remote-orbit-audio-driver/build-driver.sh`;
- `package-dmg.sh`.

Verify the generated candidate:

- bundle ID `com.lost0rz.RemoteOrbit`;
- version/build `0.2.15 (44)`;
- executable architectures include arm64 and x86_64;
- codesign verification succeeds;
- designated requirement remains `identifier "com.lost0rz.RemoteOrbit"`;
- `RemoteOrbitDiagnosticSourceHead` equals the exact candidate commit used for the build;
- DMG mounts successfully;
- expected app, Applications shortcut and Documentation are present;
- DMG SHA-256 is recorded.

## Installation / soak

After packaging verification, install the local candidate to:

`/Applications/RemoteOrbit.app`

Preserve normal user-owned macOS permission/TCC decisions; do not reset permissions merely for the soak.

For continuity observation, launch the installed binary with:

`REMOTE_ORBIT_CONTINUITY_EVIDENCE=1`

Use the app naturally for an extended period. Do not intentionally create weak Bluetooth, CPU stress, synthetic input, repeated failure loops, or artificial underruns.

Record the running candidate identity:

- executable path;
- PID;
- bundle ID;
- version/build;
- executable SHA-256;
- embedded source head;
- diagnostic environment;
- observation start time.

## Explicit non-goals / STOP

During the soak phase:

- do NOT merge PR #25;
- do NOT create tag `v0.2.15`;
- do NOT publish GitHub Release;
- do NOT reactivate hosted release CI as the active path;
- do NOT implement speculative AudioPipe/BLE fixes;
- do NOT begin 038-C/D/E/F;
- do NOT claim the audio root cause is fixed.

STOP if:

- candidate branch identity drifts unexpectedly;
- unique/unpushed local work conflicts with the candidate;
- tests or packaging fail for an unresolved reason;
- packaged version/architecture/codesign/source-head identity is inconsistent;
- installing the candidate would require unrelated product or system mutation.

## Completion of this phase

This phase is complete only when:

1. a verified local `RemoteOrbit-0.2.15.dmg` exists;
2. its SHA-256 and exact candidate source head are recorded;
3. the candidate is installed and launched with the intended diagnostic environment;
4. the control plane records `LOCAL_SOAK_ACTIVE`.

Formal publication remains a separate later decision after the soak/log review.
