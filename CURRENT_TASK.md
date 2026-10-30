# RemoteOrbit Current Task

## RO-VOICE-PIPELINE-SIMPLIFICATION-042 — Final RC003 Runtime Acceptance

Status: `SOURCE_AUDIT_PASS / HUMAN_RUNTIME_ACCEPTANCE_PENDING`

Repository: `Lost0rz/RemoteOrbit`
Active branch: `codex/voice-pipeline-simplification-042`
Source candidate: `ef606a3f712304cf43da2e9fb849a87a0bb02a1b`
Evidence/design authority: `docs/incidents/2026-10-30-042-host-mic-open-rapid-repress.md`

## Audit transition

Independent Web `CODE_DIFF` audit accepted the final Task 042 corrective at `ef606a3f712304cf43da2e9fb849a87a0bb02a1b`.

The prior blocker is closed at source level: B physical transport supersession now terminally retires A's transport ownership while preserving B candidate PCM, A completes its existing output-drain and hardware trigger-UP/replay-ACK lifecycle, and B then promotes through the existing route/adoption path.

This PASS does not establish runtime/hardware acceptance and does not authorize merge/tag/release.

## Objective

Prepare a fresh installed RemoteOrbit candidate from the accepted source state and hand it to the user for RC003 hardware acceptance.

The runtime preparation is only a provenance-preserving build/package/install step. It must not alter product behavior or widen Task 042 scope.

## Authorized runtime preparation

1. Fetch/reconcile the existing Task 042 branch and verify the local product source corresponds to the accepted source state plus any control-only descendant.
2. Build/package the app using the existing repository scripts/process.
3. Replace `/Applications/RemoteOrbit.app` with the fresh candidate and launch it.
4. Verify installed/running identity: source provenance, executable hash, bundle ID, version/build, architectures, app path and PID.
5. Confirm RemoteOrbit starts normally and existing diagnostic/runtime logs are available.
6. Update `CURRENT_STATUS.md` and `CURRENT_TASK.md` only as needed to record the runtime-preparation receipt and transition to `READY_FOR_HUMAN_RUNTIME_ACCEPTANCE`, then push and verify remote delivery.
7. Stop. The user owns the hardware acceptance run.

## Human RC003 acceptance focus

The user should exercise:

- several normal press/release voice inputs;
- 20–30 natural rapid release/re-press cycles;
- several extreme chained press/release/re-press groups;
- speech during rapid holds, specifically checking that waveform/input activation always produces actual transcription;
- release behavior, specifically checking that the waveform does not remain abnormally active or leave a stuck session.

A short residual tail consistent with the intentional output-drain behavior is not by itself a failure. Persistent/stuck waveform, no-text despite a valid speaking hold, missing first speech, or a new session being closed/blocked by an old session is a failure.

If a failure occurs, do not repair first. Record approximate time/sequence if possible and preserve the fresh logs for analysis.

## Boundary

- No product-source corrective in this phase.
- No audio-driver reinstall or mutation.
- No TCC reset.
- No broad probe work.
- No merge/tag/release/Gate F.
- No AI claim of human acceptance.
- If packaging/install requires a source change, driver/TCC mutation, or source identity cannot be reconciled, STOP and return evidence.

## Required return

Return actual observed runtime-preparation evidence:

- start/final/local/remote identities;
- source-equivalence/provenance result;
- build/package/install result;
- installed app path;
- bundle ID and version/build;
- executable architectures and SHA-256;
- launched PID/process path;
- driver/TCC unchanged confirmation;
- runtime/log readiness;
- repo changed paths, if any;
- control state and remote-delivery verification;
- unresolved blockers.

On successful preparation, stop at `READY_FOR_HUMAN_RUNTIME_ACCEPTANCE` and wait for the user's explicit hardware result.