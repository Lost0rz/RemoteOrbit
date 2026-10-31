# RemoteOrbit Current Task

## RO-VOICE-PIPELINE-SIMPLIFICATION-042 — RC003 Runtime Failure Corrective

Status: `RC003_RUNTIME_ACCEPTANCE_FAIL / CORRECTIVE_REQUIRED`

Repository: `Lost0rz/RemoteOrbit`
Active branch: `codex/voice-pipeline-simplification-042`
Failed runtime source candidate: `ef606a3f712304cf43da2e9fb849a87a0bb02a1b`
Evidence/design authorities:
- `docs/incidents/2026-10-30-042-host-mic-open-rapid-repress.md`
- `docs/incidents/2026-10-31-042-rc003-runtime-owner-race.md`

## Objective

Fix the two RC003-confirmed residual rapid-repress failures without regressing the already accepted Task 042 transport/candidate/output ownership model.

This remains Task 042. Do not create a successor task merely because the human runtime gate found another bounded corrective.

## Required corrective A — production hardware pending-owner timing

The deployed hardware ordering proves that A's immediate Option gate can resolve `noOptionEdge` before the mapped Option DOWN arrives. In that case A has no `heldHardwareOptionSessionID` or pending replay-UP owner even though the coordinator still owns A's direct session/output drain.

A rapid B direct re-press must still be able to establish a pending hardware-DOWN capture owner based on the coordinator's authorized `directOutputDrain` deferral state.

Required semantics:

1. add an explicit/narrow pending-hardware begin mode for this direct-output-drain path that can arm B even when the filter has no old held/replay-UP owner;
2. the begin result must be observed, not discarded; coordinator state must distinguish `armed while awaiting old-UP acknowledgement`, `armed with no old-UP owner`, and failure (an equivalent explicit representation is acceptable);
3. never set `pendingDirectHardwareRepressAwaitingOldUp` when no old hardware-UP acknowledgement can actually arrive;
4. B mapped Option DOWN must be captured/suppressed while B is pending; it must not pass to Doubao before B can own the corresponding RemoteOrbit route/session;
5. B promotion requires both conditions: A terminal/output/trigger ownership is complete and B's mapped DOWN has actually been captured. Correctness must not depend on which condition arrives first;
6. once both are true, reuse the existing promotion/replay path so B's trigger DOWN, direct session, candidate adoption and route opening remain atomic;
7. early B physical UP must keep the existing cancellation/tombstone/no-trigger-leak behavior;
8. a pending-owner arm/capture failure must be surfaced and safely cancelled, never converted into a deferred session that later fails as `pending_hardware_repress_owner_missing`.

Do not globally loosen hardware ownership or allow arbitrary mapped events to be captured without an active direct-output-drain B owner.

## Required corrective B — terminal released HOST_MIC_OPEN drain supersession

The fresh runtime proves that a physically released HOST_MIC_OPEN stream can still be inside its normal 350 ms AUDIO_STOP drain when a new explicit physical B `AUDIO_START reason=0x03` / different stream ID arrives.

Extend transport supersession only when all required terminal evidence is present:

- old stream is the released HOST_MIC_OPEN voice session;
- released-host grace belongs to that old session and records physical release;
- AUDIO_STOP drain is active with a real pending stop reason;
- incoming start is physical reason `0x03` and has a different stream ID.

Then:

- retire only A's BLE ingress/drain ownership;
- retire the released host voice intent locally so no stale MIC_CLOSE can target B;
- preserve A's already queued output tail;
- begin B as `.preHIDPhysical` with the existing transport epoch/generation protection;
- use the existing physical-transport-superseded coordinator lifecycle so A output/trigger retirement remains serialized ahead of B promotion;
- retain READY.

Unreleased HOST_MIC_OPEN, non-0x03, same-stream and normal no-replacement tail behavior remain unchanged.

## Required deterministic regressions

At minimum prove:

1. exact deployed no-owner ordering: A gate resolves `noOptionEdge`; A mapped DOWN/UP are not filter-owned; B transport candidate arrives during A terminal/output ownership; B raw HID DOWN creates a pending owner; B mapped DOWN is captured instead of passed; A completes; B then promotes and adopts/renders candidate PCM;
2. the same lifecycle when A completes before B mapped DOWN reaches the filter — promotion waits for the captured B DOWN rather than rejecting/cancelling prematurely;
3. pending begin failure is handled explicitly and cannot leave a deferred B that later reports `pending_hardware_repress_owner_missing`;
4. early B UP still cancels without replay/trigger leakage;
5. existing old-UP-owned rapid-repress path and replay-ACK ordering stay green;
6. released HOST_MIC_OPEN + active drain + physical reason03/new stream ID supersedes immediately;
7. stale host grace/MIC_CLOSE/drain callbacks cannot close or retire B;
8. unreleased host, non-0x03 and same-stream cases do not use the new host-drain supersession;
9. normal 350 ms tail, 180 ms debounce policy, READY, candidate PCM isolation, A-terminal/B-preservation, Gate C/D and ATVV protocol regressions stay green.

Also run the relevant prior Task 042 suites, full Swift tests, arm64/x86_64 Release builds, ATVV protocol self-tests and `git diff --check`.

## Boundary

- No arbitrary Doubao post-processing delay/re-arm timer in this corrective.
- No broad probe work; evidence is sufficient.
- No global 350 ms reduction/removal.
- No global debounce disable/reduction.
- No parallel ambiguous ATVV epochs.
- No global UNKNOWN remap.
- No driver/CoreAudio/TCC changes.
- No package/install/hardware retest before independent Web source audit.
- No merge/tag/release/Gate F.

If the smallest implementation requires widening these boundaries, STOP and return the dependency/evidence instead of expanding scope.

## Required return

Return:

- start/final/local/remote identity;
- exact validation of both runtime findings;
- pending-hardware begin/result/readiness model;
- proof B mapped DOWN cannot pass early in the failing sequence;
- two-condition A-complete/B-down-captured promotion evidence;
- HOST terminal-drain supersession predicate and stale-close protection;
- RED/GREEN evidence for the new exact-order tests;
- focused/full tests, release builds, protocol self-tests and diff check;
- changed paths;
- preserved-boundary flags;
- unresolved issues;
- next safe action.

After successful implementation, update `CURRENT_STATUS.md` and `CURRENT_TASK.md` together, push only the existing Task 042 branch, verify remote delivery, and stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`. Do not package/install before that audit.
