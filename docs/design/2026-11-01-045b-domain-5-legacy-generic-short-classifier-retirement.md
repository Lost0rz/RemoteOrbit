# Task 045B Domain 5 — Legacy Generic Short Classifier Runtime Retirement

Date: 2026-11-01
Status: ACCEPTED DESIGN / IMPLEMENTATION BOUNDARY FROZEN
Task: `RO-DIAGNOSTICS-LEGACY-RETIREMENT-045`
Canonical audit basis: `main@fa49bb4fe38fd87a7ed36ab7bccfcfe2259434c6`

## Design question

After retiring the user surface, persisted Persistent/Receiver-B authority, Persistent runtime, and Dual Receiver runtime, what remaining voice-runtime code is genuinely obsolete and can be removed without weakening the current Gate-A LONG-only path?

A second question is whether the physical/local-microphone AVCapture implementation should be removed in the same change.

## Verified constraints

- Production microphone admission has converged to one path: `AppController.beginVoicePress(...)` calls the coordinator with `directSession: true` and `longOnlyAdmission: true` for both HID and filter-fallback entrypoints.
- The current product contract is SHORT `<300 ms` no-op and LONG `>=300 ms` direct remote voice.
- The coordinator still carries an older non-direct `.pending` / `.holding` classifier, short callback plumbing, local-microphone short selection and a separate legacy tail/repress lifecycle.
- `handleVoiceShortTap(...)`, `AppController.bypassesShortClassification(for:)`, and `VoicePressCoordinator.usesLocalMicrophone(forShortBinding:)` have no production caller.
- `DisabledShortClassifierTests.swift` verifies only the old classifier path.
- Current direct rapid-repress, output-drain, candidate, tombstone/suppression and transport-loss mechanisms are separate from that old classifier and remain product-critical.
- Historical symbol names do not establish ownership. `VoicePressCoordinator.tailDrainDelay`, despite its name, is still used by the current mapped-edge suppression quiet-period path.
- `AudioPipe` still contains a substantial local/external microphone AVCapture/permission subsystem. Once the dead classifier callers are removed it should have no production demand, but deleting it is a separate cross-module audio/permission change.

## Selected option

### Domain 5: retire only the generic non-direct short classifier runtime

Remove the obsolete coordinator/AppController classifier and short-action plumbing now, and simplify the voice-entry API so the current direct LONG-only authority is explicit rather than hidden behind booleans for dead modes.

Do not delete the AudioPipe local-microphone implementation in this domain. Removing its callers is allowed; the implementation itself becomes the subject of Domain 6.

### Rationale

This keeps one retirement domain equal to one ownership boundary:

- Domain 5 owns coordinator/input-policy state that no production caller can reach.
- Domain 6 will own the now-orphaned AVCapture/permission/audio implementation.

Combining both would make a single change simultaneously rewrite coordinator state, application routing, AVFoundation permission behavior and the audio data plane. That would increase regression ambiguity and violate the serial module-by-module retirement model.

## Rejected alternatives

### Delete classifier + AudioPipe local mic together

Rejected for Domain 5. It crosses state-machine and audio/permission ownership and makes failures harder to attribute.

### Keep the generic classifier indefinitely because tests still exercise it

Rejected. The tests are historical coverage of a path with no production caller; tests do not make a dead product authority live.

### Delete all short/audio/tail-named primitives

Rejected. Some historically named suppression and quiet-period primitives are current LONG-only correctness mechanisms. Ownership is determined by live callers, not naming.

## Ownership implications

After Domain 5, the voice runtime should have one production admission model:

`physical candidate → 300 ms LONG confirmation → direct opening → streaming → draining → idle`

The coordinator may still use direct pending-repress ownership internally for rapid consecutive LONG sessions. That is not the retired generic `.pending` classifier state and must remain.

Current primary trigger configuration continues to be owned by `VoiceInputProfile` / `VoiceInputProfileStore` and primary `RemoteVoiceKeyMapping`.

Receiver readiness continues to project current direct states only.

## Authorized retirement boundary

Retire when proven legacy-only:

- `.pending` / `.holding` `VoicePressCoordinator.State` cases;
- non-direct branch and dead mode-selection arguments of `VoicePressCoordinator.keyDown(...)`;
- short-action callback and local-microphone selection state in the coordinator;
- old hold classifier timer/promotion;
- legacy long-input and tail-work-item lifecycle;
- release-bounce state that only protects the retired path;
- legacy-only `PendingRepress` payload and activation branch;
- legacy-only remote drain/session bookkeeping distinct from direct drain ownership;
- dead AppController short-binding/classifier helpers and short-action dispatch;
- HUD/readiness projection cases that only represent retired coordinator states;
- dedicated obsolete classifier tests and legacy-only cases in mixed suites.

## Explicit retained boundary

Retain without semantic change:

- `holdActivationThreshold == 0.30` as the current LONG threshold;
- long-only candidate/timer and physical-attempt ownership;
- direct session opening/streaming/draining;
- direct pending-repress and hardware pending-repress handoff;
- short tombstone and late mapped-edge suppression;
- synthetic handoff/fallback;
- hardware Option gate/replay/held-UP acknowledgement;
- pre-HID physical candidate;
- direct output drain and post-release grace;
- BLE/ATVV/AudioPipe remote transport/buffer/IOProc;
- primary mapping/profile runtime and its reconfiguration/rollback safety;
- diagnostics gate and recording independence;
- `VoiceKeyFilter`/EventSuppressor live suppression primitives;
- `tailDrainDelay` or behaviorally identical suppression quiet-period delay while its current caller remains;
- lower-level `VoiceOptionTrigger` operations with current non-legacy callers.

## Domain 6 freeze

The following remains unchanged in Domain 5 and is audited separately afterward:

- `AudioPipe.localMicrophoneCaptureRequested` and related state;
- `setLocalMicrophoneCaptureEnabled(...)`;
- AVFoundation microphone authorization/request flow;
- AVCapture session/input/output/delegate setup;
- start/stop local microphone capture;
- local-microphone sample scheduling and diagnostics/counters.

Domain 5 is expected to leave this implementation with no production caller. That absence is evidence for Domain 6, not permission to delete it early.

## Verification implications

The implementation must prove both absence and preservation:

- no generic `.pending` / `.holding` production classifier remains;
- production entry no longer exposes dead short-binding/classifier-mode selection;
- no short/local-mic classifier helper has a production caller;
- current Gate-A short-no-op/long-only behavior remains covered;
- repeated SHORT-prefix→LONG, rapid repress, mapped-edge suppression, tombstone handoff, transport loss and output drain stay green;
- current primary runtime/profile/mapping coverage stays green;
- readiness/HUD behavior remains correct for direct states;
- AudioPipe local-microphone implementation is byte-for-byte/source unchanged by Domain 5;
- full Swift, Release, durable CI and Universal2 packaging remain green.

## Consequences

The main coordinator becomes materially smaller and has one product voice admission model. Historical classifier-specific test count will fall; this is expected and must not be treated as coverage loss when current claims remain in direct-path suites.

The repository will temporarily contain an orphaned AudioPipe local-microphone subsystem until Domain 6. This is deliberate to preserve bounded attribution.

## Reversibility

The retirement remains recoverable from Git history. No stored user data or external schema is deleted in Domain 5.

## Task reconciliation

`TASK_RECONCILIATION_REQUIRED: YES`

Reason: Domain 4 is now merged/closed and the active execution authorization must advance to the newly audited Domain 5 boundary before local mutation.

Durable document: this file.
