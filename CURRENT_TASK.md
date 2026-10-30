# RemoteOrbit Current Task

## RO-VOICE-PIPELINE-SIMPLIFICATION-042 — Corrective Candidate Preparation

Status: `READY_FOR_LOCAL_CORRECTIVE_CANDIDATE_PREPARATION`

Repository: `Lost0rz/RemoteOrbit`
Active branch: `codex/voice-pipeline-simplification-042`
Accepted corrective source: `b1736f2feedd7ed13e4520ecdfaa0c6bf6e9b332`
Incident record: `docs/incidents/2026-10-30-042-adopted-physical-grace-intent-race.md`
Frozen 041 observability baseline: `ac3132986197bfee4440bb8f388e3d2e5f478f03`

## Objective

Prepare and install one provenance-locked runtime candidate from the accepted second corrective source. Do not change product semantics.

The purpose is to retest the exact previously failing rapid open/close RC003 pattern after the adopted-physical stale-intent retirement corrective.

## Source/provenance contract

Before packaging, prove that any live branch commits after accepted source `b1736f2feedd7ed13e4520ecdfaa0c6bf6e9b332` are governance/control-only and do not change product source, tests, package scripts, driver code or version/signing behavior.

Use the established packaging/install flow only. The previous candidate used `./package-dmg.sh --reuse-driver`; use the current established equivalent if unchanged by authority.

## Authorized work

1. Fetch/reconcile the live 042 branch and read `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md`.
2. Use the canonical writer/worktree; require a clean worktree.
3. Verify accepted corrective source identity and control-only drift.
4. Build/package the exact corrective candidate with the existing release flow; no source/package-script edits.
5. Record app/DMG paths, SHA-256, bundle ID, version/build, architectures and signing state.
6. Quit the currently running older failed candidate cleanly.
7. Replace only `/Applications/RemoteOrbit.app` with the exact new candidate if the established flow supports it.
8. Do not replace/reload the installed CoreAudio driver; preserve driver identity.
9. Do not reset or mutate TCC.
10. Verify strongest available installed-vs-package provenance.
11. Launch the candidate and verify PID/executable path/version/build/bundle identity.
12. Verify existing RemoteOrbit Mic, RC003 BLE/HID and diagnostic journal/CLI readiness without mutation.
13. Update `CURRENT_STATUS.md` and `CURRENT_TASK.md` together with observed preparation evidence.
14. Push only the existing 042 branch, verify exact local/remote equality and stop at `READY_FOR_HUMAN_CORRECTIVE_RUNTIME_RETEST`.

## Explicitly not authorized

Do NOT:

- modify product source/tests/package scripts;
- change adopted-physical retirement logic;
- globally reclassify UNKNOWN;
- change long-lived READY or strict READY;
- change ATVV protocol/codec;
- change Gate C ring or Gate D 45 ms reserve;
- replace/reload the driver;
- reset TCC;
- merge/tag/release/publish;
- create Gate F;
- perform or approve the human runtime retest.

If packaging/install requires any prohibited mutation, STOP and report the blocker.

## Required preparation receipt

Return observed values for:

- start/final control HEAD;
- accepted corrective source;
- product-source diff from accepted source;
- clean worktree before/after;
- build/package commands and result;
- app/DMG artifact paths and SHA-256;
- bundle ID/version/build/architectures/signing;
- install result and installed provenance;
- running PID/path/version/build;
- RemoteOrbit Mic readiness;
- BLE/HID readiness;
- diagnostic capture readiness;
- source/package-script/driver/TCC mutation flags;
- merge/tag/release/Gate F flags;
- human corrective runtime retest = PENDING;
- control alignment and unresolved items.

## Human boundary

After candidate preparation, stop. The user owns the RC003 retest. The first retest should reproduce the prior stress condition: rapid repeated press/release/open-close cycles without restarting RemoteOrbit or reconnecting RC003, while checking waveform, recognized speech and continued next-session admission.
