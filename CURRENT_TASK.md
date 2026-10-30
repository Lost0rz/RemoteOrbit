# RemoteOrbit Current Task

## RO-VOICE-PIPELINE-SIMPLIFICATION-042 — Corrective Candidate Preparation

Status: `READY_FOR_LOCAL_CORRECTIVE_CANDIDATE_PREPARATION`

Repository: `Lost0rz/RemoteOrbit`
Active branch: `codex/voice-pipeline-simplification-042`

Frozen evidence baseline: `ac3132986197bfee4440bb8f388e3d2e5f478f03`
Previous failed runtime candidate source: `2d09b6d77f9f75aa46bb4a13838cd22d5589f524`
Accepted corrective source: `7dfd2e0c9ab71d3fa437be9b4c5cfac1282d9b1c`
Incident record: `docs/incidents/2026-10-30-042-no-waveform-physical-htt-admission-race.md`

## Objective

Prepare and install one provenance-locked runtime candidate from the independently accepted Physical-HTT admission corrective, without changing product source, so the user can retest the original no-waveform failure on real RC003 hardware.

This is not Gate F and is not a source-construction phase.

## Corrective identity contract

Product source is frozen at:

`7dfd2e0c9ab71d3fa437be9b4c5cfac1282d9b1c`

The live branch may contain later control-only descendants. Before building, prove that the diff from the accepted corrective source to the live control HEAD contains no product-source/package-script change beyond governance files. If false, STOP.

Use only the repository's established build/package/install flow. Do not modify source or packaging machinery to make this preparation succeed.

## Authorized work

1. Fetch the live 042 branch and read `AGENTS.md`, `CURRENT_STATUS.md`, and this file.
2. Reuse one clean canonical writer/worktree and fast-forward to the live branch.
3. Verify local/remote exact alignment and prove the accepted corrective source identity above.
4. Prove any descendant drift after `7dfd2e0...` is governance-only before building.
5. Build/package using the established repository flow (including `./package-dmg.sh` if still canonical) without changing product/package source.
6. Record exact build/package commands and results.
7. Record app/DMG artifact paths, hashes, bundle ID, version/build, architectures, signing result, accepted corrective source HEAD and live control HEAD.
8. Quit the currently running old RemoteOrbit candidate cleanly.
9. Install/replace only `/Applications/RemoteOrbit.app` with the exact corrective candidate if the established flow supports it.
10. Do NOT replace/reload the installed CoreAudio driver.
11. Do NOT reset or manipulate TCC.
12. Verify installed app provenance against the packaged corrective candidate using the strongest existing repository-supported identity checks.
13. Launch the installed corrective candidate and verify process identity/basic runtime readiness: app path/PID/version, RemoteOrbit Mic process-level readiness, RC003 BLE/HID readiness, and existing diagnostics availability.
14. Update `CURRENT_STATUS.md` and `CURRENT_TASK.md` together with the actual candidate-preparation receipt and stop at `READY_FOR_HUMAN_CORRECTIVE_RUNTIME_RETEST`.

## Explicitly not authorized

Do NOT:

- modify product source or tests;
- modify package scripts;
- change Physical-HTT corrective semantics;
- change Gate A-E semantics;
- change Gate B long-lived READY or strict READY;
- change ATVV protocol/codec/framing/capabilities;
- change Gate C ring/capacity/overflow policy;
- change Gate D 45 ms reserve;
- change gain/limiter/resampling;
- reset TCC;
- install/reload/replace the CoreAudio driver;
- merge, tag, release, publish, or create a release PR;
- create Gate F;
- self-approve the human runtime retest;
- perform speculative source repair if candidate preparation or runtime readiness fails.

If candidate preparation requires a source/package/driver/TCC change, STOP and report the exact dependency.

## Required preparation verification

Report at minimum:

1. live branch/control HEAD;
2. accepted corrective source HEAD;
3. proof that post-corrective descendants are governance-only;
4. clean worktree before/after;
5. exact build/package commands;
6. Release/package result;
7. artifact paths and SHA-256;
8. Bundle ID/version/build/architectures;
9. codesign verification;
10. installed app path and identity;
11. installed/package provenance method and result;
12. running executable path/PID/version;
13. RemoteOrbit Mic readiness without driver mutation;
14. BLE/HID readiness;
15. diagnostic journal/CLI readiness;
16. `SOURCE_CHANGED=NO`;
17. `PACKAGE_SCRIPT_CHANGED=NO`;
18. `DRIVER_CHANGED=NO`;
19. `TCC_RESET=NO`;
20. `MERGE_TAG_RELEASE=NO`.

## Human retest boundary

After successful preparation, STOP. The user owns the runtime retest.

The first human retest must target the exact regression rather than broad feature acceptance:

1. confirm the first RC003 voice press produces Doubao waveform/audio;
2. release and allow normal retirement;
3. without restarting RemoteOrbit or disconnecting ATVV, perform at least 5 subsequent voice presses while Gate B READY transport is reused;
4. each press must be admitted and must produce usable waveform/audio;
5. include at least one immediate-speech press and one short utterance;
6. if any press opens Doubao with no waveform, preserve that fresh failure and export diagnostics before changing runtime state.

A human PASS plus evidence from the corrective candidate is required before merge/release consideration.

## Delivery / stop state

If candidate preparation succeeds:

- update `CURRENT_STATUS.md` and `CURRENT_TASK.md` together;
- commit/push only governance/evidence records on the existing 042 branch if required;
- verify exact local/remote equality;
- stop at `READY_FOR_HUMAN_CORRECTIVE_RUNTIME_RETEST`;
- do not perform the human acceptance on the user's behalf;
- do not merge/tag/release.

Return actual observed evidence only. Do not predeclare successful runtime repair.
