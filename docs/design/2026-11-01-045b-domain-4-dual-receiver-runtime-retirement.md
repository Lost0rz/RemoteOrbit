# Task 045B Domain 4 — Dual Receiver Runtime Retirement

Date: 2026-11-01
Audit basis: `main@e8118342f43154a6b2a93cd70b679f4ef52f366b`
Status: `ACCEPTED DESIGN / READY FOR IMPLEMENTATION HANDOFF`

## Design question

Can the obsolete Dual Receiver A/B voice runtime be removed as one bounded domain now that its user surface, persisted preference authority, and Persistent runtime have already been retired, without altering the current Gate-A LONG-only voice path or generic correctness machinery?

## Verified facts

- Production RC003 microphone input is already Gate-A direct LONG-only. `HIDButtonDownPolicy.resolve(...)` is called from production with `dualReceiverVoiceMode: .legacy`.
- `handleDualReceiverMicrophoneEdge(isDown:at:)` remains implemented but has no production caller in current `main.swift`.
- `applySecondaryVoiceTriggerKey(...)` has no product caller after Domains 1–2; its remaining use is its own main-thread forwarding path and Dual tests.
- `configureDualReceiverVoiceMode(...)` is reachable only from the retired Receiver-B runtime configuration seam.
- Three standalone Dual source files remain: `DualReceiverVoiceMode.swift`, `DualReceiverVoiceGestureRecognizer.swift`, and `DualReceiverMappedTriggerState.swift`.
- AppController still owns the dead A/B runtime island: recognizer/mode/mapped state, Receiver-B runtime key, A→B mapping arm, B→A restore, reconfiguration gate, prewarm/physical-down/active-gesture ownership, and Dual-only diagnostics.
- VoicePressCoordinator still contains Dual-only classified-gate/classified-hold state (`classifiedDualReceiverHold`, `classifiedDualReceiverTriggerKey`, `prearmedDualReceiverHardwareGateSessionID`) and associated begin/cancel/complete branches.
- The current LONG-only path does not use those Dual-only classified seams. Its live correctness ownership remains the private LONG candidate, short tombstone, mapped-edge suppression, suppression handoff, pending direct repress, held Option-UP acknowledgement, output drain, pre-HID candidate, BLE transport and AudioPipe lifecycle.
- Lower-level suppression helpers with historical `AudioOnly` naming remain live for current LONG-only handoff and must not be retired by name.

## Selected option

Retire the complete **Dual Receiver runtime/state-machine island** now, including its A/B mapping transaction and Dual-only coordinator seams, while preserving the single-profile primary mapping authority and all current LONG-only ownership machinery.

This domain is intentionally narrower than “delete all legacy classifier code.” Generic historical short/local-microphone/classifier seams that are not Dual-specific remain frozen for a later domain so regression attribution stays clear.

## RETIRE NOW

### Standalone sources

Delete:

- `remote-orbit/Sources/RemoteOrbit/DualReceiverVoiceMode.swift`
- `remote-orbit/Sources/RemoteOrbit/DualReceiverVoiceGestureRecognizer.swift`
- `remote-orbit/Sources/RemoteOrbit/DualReceiverMappedTriggerState.swift`

### AppController / main.swift

Remove Dual-only runtime ownership and orchestration, including where present:

- `dualReceiverVoiceGestureRecognizer` and `dualReceiverVoiceMode`;
- `currentSecondaryMomentaryVoiceTriggerKey` and `initialSecondaryMomentaryVoiceTriggerKey` runtime-only seams;
- `currentDualReceiverShortBinding`;
- `dualReceiverMappedTriggerState`;
- Dual reconfiguration/mapping gate and generation state;
- Dual prewarm/physical-down/active-gesture state;
- `configureDualReceiverVoiceMode(...)`;
- `applySecondaryVoiceTriggerKey(...)`;
- `handleDualReceiverMicrophoneEdge(...)` and event dispatch;
- A→B secondary mapping arm and B→A primary restore transaction;
- Dual-specific HID-removal/BLE-loss cleanup and diagnostics;
- Dual-only readiness/state fields that become unreferenced after removal.

The retained production mapping is the single selected `VoiceInputProfile` trigger applied through `RemoteVoiceKeyMapping` and its existing verification/readback path.

### VoicePressCoordinator

Remove only Dual-specific coordinator seams proven to have no retained non-Dual caller, including where applicable:

- `classifiedDualReceiverHold`;
- `classifiedDualReceiverTriggerKey`;
- `prearmedDualReceiverHardwareGateSessionID`;
- `beginClassifiedHardwareGate(...)`;
- `beginClassifiedHardwareHold(...)`;
- `cancelClassifiedHardwareGate(...)`;
- Dual-only classified hold admission/trigger/output-drain branches;
- Dual-only fields in `PendingRepress` if no retained caller remains.

Do not collapse or redesign generic `VoicePressCoordinator.State`, pending/holding/drain, or direct-session behavior merely because Dual used those states.

### HID policy

`HIDButtonDownPolicy` may drop its `dualReceiverVoiceMode` input and active-Dual exception once the Dual mode type is removed, preserving the existing production policy for microphone live physical candidates and generic advanced/repeat behavior.

### Tests

Delete Dual-only suites after checking for generic assertions:

- `DualReceiverVoiceGestureRecognizerTests.swift`
- `DualReceiverVoiceModeTests.swift`
- `DualReceiverVoiceSettingsTests.swift`
- `DualReceiverVoiceTransactionTests.swift`

Remove Dual-only cases/harness fields from `VoiceTriggerRuntimeTests.swift`, `HIDButtonDownPolicyTests.swift`, and other directly affected suites.

Before deleting a Dual assertion, rehome it only if it describes a still-live generic/current contract not already covered by retained suites. Do not retain dead Dual tests merely to preserve test count.

## KEEP

Do not delete, redesign, or weaken:

- `VoiceInputProfile` / `VoiceInputProfileStore` and profile ID authority;
- `.voiceKeyDefault` Codable compatibility and mapping schema;
- primary `RemoteVoiceKeyMapping`, hidutil mapping application and readback verification;
- Gate-A LONG-only candidate/direct-session lifecycle;
- SHORT `<300 ms` no-op and LONG `>=300 ms` direct voice contract;
- repeated SHORT-prefix → final LONG recovery;
- rapid LONG/release/LONG and pending direct repress ownership;
- short-discard tombstone ownership;
- late mapped Option down/up/flags suppression;
- LONG-only suppression handoff;
- hardware Option deferral/replay/held-UP acknowledgement;
- synthetic fallback;
- pre-HID physical candidate;
- output drain/tail/grace;
- BLE READY/reuse, ATVV and AudioPipe data path;
- `EventSuppressor` and generic `HardwareOptionGate` ownership;
- diagnostics runtime gate and independent recording control;
- generic non-Dual legacy short-action/local-microphone classifier seams for a later domain;
- historical documentation/plans as historical evidence.

In particular, do not remove or cosmetically rename a lower-level suppression helper solely because its historical symbol contains `AudioOnly`; actual live LONG-only call ownership controls classification.

## FROZEN FOR LATER DOMAIN

- remaining generic legacy short/local-microphone classifier code not required for Dual removal;
- cosmetic renaming/refactoring of tombstone/suppression primitives;
- historical Dual design/incident documents;
- final broad legacy residue cleanup and Wave D resource/regression audit.

## Rejected alternatives

### Delete all remaining classifier/pending/holding code with Dual

Rejected. Some generic historical seams remain independently classifiable and should be retired in a later domain. Combining them with Dual makes regressions harder to attribute.

### Keep Dual because its tests are extensive

Rejected. Test volume does not establish production authority. The current product surface and persistence authority are gone, production HID policy uses `.legacy`, and the Dual edge handler has no product caller.

### Delete primary mapping together with A/B mapping

Rejected. The selected profile still requires one primary physical trigger mapping and readback verification. Domain 4 removes the secondary transactional mapping authority, not the current single-profile mapping.

## Compatibility / data

No user-data migration is required. Domain 2 already made Receiver-B preference bytes inert. Domain 4 does not actively delete those historical UserDefaults bytes.

Historical Git/docs remain available for rollback and forensic reference.

## Verification implications

A successful implementation must prove both absence and preservation:

1. all three standalone Dual source files are absent;
2. AppController has no Receiver-B/Dual mode/recognizer/mapped-state/A↔B mapping transaction runtime;
3. no production or test-only path can call `handleDualReceiverMicrophoneEdge` or configure Receiver B because those seams are absent;
4. VoicePressCoordinator no longer has Dual-only classified gate/hold ownership;
5. HID button policy no longer depends on Dual mode while retaining current microphone live-candidate and generic button behavior;
6. selected profile primary mapping/readback remains green;
7. current LONG-only regression remains green, especially repeated SHORT→LONG, rapid repress, tombstone/suppression handoff, synthetic fallback, transport loss and output drain;
8. diagnostics gate, recording independence, BLE/AudioPipe and receiver readiness remain green.

Then run focused changed-boundary tests, full `swift test`, `swift build -c release`, `git diff --check`, durable self-hosted CI, and Universal2 build-only packaging smoke.

## Consequences

- Removes a substantial dead A/B mapping/state-machine island after its product/config authorities are already gone.
- Leaves a smaller set of generic historical classifier/local-microphone seams for a later, independently auditable domain.
- Reduces mapping and ownership complexity without changing the current user-visible voice contract.

## Reversibility

High. Source-only retirement is recoverable through Git history; no installed runtime or user data is mutated by this domain.

## Reversal trigger

Stop and reconcile if fresh implementation evidence proves a proposed Dual-only symbol is required by the current Gate-A LONG-only path or primary mapping/readback in a way that cannot be preserved by a behavior-neutral compile adaptation.

`TASK_RECONCILIATION_REQUIRED: NO`
