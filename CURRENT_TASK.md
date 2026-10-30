# RemoteOrbit Current Task

## RO-VOICE-PIPELINE-SIMPLIFICATION-042 — Candidate Runtime Preparation

Status: `READY_FOR_LOCAL_CANDIDATE_PREPARATION`

Repository: `Lost0rz/RemoteOrbit`

Active branch: `codex/voice-pipeline-simplification-042`

Frozen evidence baseline: `ac3132986197bfee4440bb8f388e3d2e5f478f03`

Accepted semantic heads:

- Gate A: `50b1d9efabe15f04d5479b39af227d0e6f43a4e3`
- Gate B: `ae0bf10874d34ce556b4b73a506b22f6a9a1a412`
- Gate C: `9abdebc21a1e03c79ab0ac960bf2d9902c24b1d5`
- Gate D: `9cdbf6f5190d9ed453d7f15cf2e8192973cc62ad`
- Gate E / final source candidate: `2d09b6d77f9f75aa46bb4a13838cd22d5589f524`

## Objective

Prepare one provenance-locked installed candidate for human hardware/natural-use acceptance without changing accepted product source.

This is not Gate F and is not a source-construction phase.

## Candidate identity contract

The product source is frozen at:

`2d09b6d77f9f75aa46bb4a13838cd22d5589f524`

The live branch may contain later control-only commits. Before building, prove that the diff from the accepted semantic head to the live control head contains no product-source/package-script change beyond the two governance files. If this is false, stop.

Build/package/install must use the repository's established release/candidate flow. Do not invent a new packaging system.

## Authorized work

1. Fetch the live 042 branch and read `AGENTS.md`, `CURRENT_STATUS.md`, and this file.
2. Reuse one clean canonical writer/worktree.
3. Verify local/remote exact control-head alignment and prove the accepted product source identity above.
4. Re-run the minimum provenance checks required by the repository before packaging; do not repeat broad source construction unless the established packaging flow requires it.
5. Build the existing Release candidate using the established repository flow.
6. Produce the candidate app/DMG artifact using the established packaging scripts without changing source, version policy, signing policy, or driver contents.
7. Record artifact path, app version/build, architectures, code-signing identity/status, bundle identifier, artifact SHA-256, and source/control heads.
8. Install/replace `/Applications/RemoteOrbit.app` with that exact candidate only if the established repository flow supports it.
9. Verify the installed app is byte/provenance-equivalent to the packaged candidate using the strongest available repository-supported identity checks.
10. Launch the installed candidate and verify process identity/version/bundle ID and basic runtime health.
11. Prepare the existing bounded 041/042 diagnostics/log export path for the subsequent human natural-use exercise.
12. Update `CURRENT_STATUS.md` and `CURRENT_TASK.md` together with the actual preparation receipt and stop at `READY_FOR_HUMAN_RUNTIME_ACCEPTANCE` if preparation succeeds.

## Explicitly not authorized

Do NOT:

- modify product source;
- change Gate A-E semantics;
- change the selected 45 ms reserve;
- change BLE/ATVV, AudioPipe, ring, driver, mappings, or profile behavior;
- change package scripts just to make packaging succeed;
- bump version/build unless the existing candidate flow requires a deterministic generated build value without source mutation;
- reset or automate TCC permissions;
- reinstall/reload the CoreAudio driver unless the existing installed driver is missing and the task is explicitly re-authorized;
- mutate Air runtime outside installing/launching the exact candidate app;
- merge, tag, release, publish, or open a release PR;
- create Gate F;
- perform speculative repairs if runtime preparation fails.

If Accessibility/microphone/TCC permission is missing, report the exact blocker and stop for human action; do not reset privacy databases.

## Preparation verification

At minimum report:

1. live branch/control HEAD;
2. accepted semantic source HEAD;
3. proof that control-only descendants do not alter product/package source;
4. clean worktree before and after preparation;
5. exact package/build command(s) used by the established flow;
6. Release build result;
7. artifact path and SHA-256;
8. `.app` bundle ID;
9. app version and build number;
10. arm64/x86_64 architectures present as expected by the established release flow;
11. code-signing verification result;
12. installed app path and installed identity;
13. running process path/PID/version after launch;
14. RemoteOrbit Mic 2ch presence/readiness without driver mutation;
15. BLE/HID basic readiness after launch;
16. diagnostic/log capture path ready for the human exercise;
17. no source/package-script/driver/TCC mutation.

## Completion / stop state

On successful preparation:

- update `CURRENT_STATUS.md` and `CURRENT_TASK.md` together;
- commit/push only governance/evidence records if repository governance requires them;
- leave accepted product source unchanged;
- verify exact local/remote branch equality;
- stop at `READY_FOR_HUMAN_RUNTIME_ACCEPTANCE`;
- do not perform the human acceptance on the user's behalf;
- do not merge/tag/release.

If blocked, stop at a truthful blocker state with evidence and do not repair outside authority.
