# CURRENT_STATUS

Last updated: 2026-10-08
State: DUAL-RECEIVER IMPLEMENTATION AUTHORIZED THROUGH EARLY HARDWARE GATE
Repository: `Lost0rz/RemoteOrbit`

This file is the authority for mutable current project state. Historical detail remains preserved in Git history.

## Independent Web plan audit

- Audited planning base: `ab43ce0e8ac7cb3c3fcd1ccfd078e65f75e8d903`.
- Audited plan branch: `codex/dual-receiver-momentary-routing-v1-plan`.
- Audited plan HEAD: `6415c6baccae75b220391568d77b546c5cbbefe8`.
- Audited plan path: `docs/superpowers/plans/2026-10-08-dual-receiver-momentary-routing.md`.
- Plan branch is docs/control only relative to its base; no product or test source changed.
- Independent audit result: PASS WITH TWO MANDATORY IMPLEMENTATION CLARIFICATIONS recorded below.

## Frozen product contract

```text
Direct LONG                   -> Receiver A
Quick first tap + second LONG -> Receiver B
Quick single tap              -> no action

Receiver A -> Left Option initially
Receiver B -> Right Option initially
LONG_THRESHOLD_MS = 350
DOUBLE_WINDOW_MS   = 300
```

Both receivers are independent momentary transactions. Dual mode does not use external Persistent Session state as receiver authority.

## Frozen architecture

```text
raw microphone F5
-> dual mode keeps receiver hidutil mapping empty
-> existing HIDMonitor + EventSuppressor parks native F5
-> voice-specific 350/300 classifier
-> exactly one receiver selected
-> activate ATVV
-> first decoded PCM
-> synthetic DOWN for the selected key only
-> physical release + existing output drain
-> matching UP for the captured selected key
```

Receiver A remains the existing momentary trigger. Receiver B uses a new optional secondary/double-hold trigger. Secondary Off preserves legacy single-receiver behavior. Dual mode requires microphone SHORT Disabled and distinct A/B keys.

## Mandatory Web audit clarifications

### 1. One classifier only in dual mode

After `DualReceiverVoiceGestureRecognizer` classifies A or B at the 350 ms boundary, the dual path must enter `VoicePressCoordinator` through an explicit already-classified hold/transaction entry point.

It must NOT call the legacy `VoicePressCoordinator.keyDown(...)` path in a way that waits another 300 ms SHORT/LONG threshold. There is exactly one semantic long-press classifier in dual mode. Tests must prove receiver/voice activation is not delayed by an additional legacy threshold.

Legacy single-receiver mode keeps its existing classifier unchanged.

### 2. Mapping-clear failure is fail-closed

Dual mode must not become active merely because in-memory mapping state says disabled. The runtime transition that clears the device-scoped F5 -> receiver mapping must observe a successful `RemoteVoiceKeyMapping.setEnabled(false, ...)` result through the injected/testable mapping seam.

If clearing the receiver mapping fails, dual mode is unavailable for that gesture/runtime transition:

```text
no BLE voice activation
no A trigger
no B trigger
no raw-F5 fallback
```

Do not restore pre-classification receiver mapping as a workaround.

## Classifier corrective baseline rule

The old classifier candidate remains `172427957fd18a2b5827edd1cb1c4bddb6a5b7db` and must not be merged/cherry-picked wholesale.

Implementation starts from the authoritative main containing this transition and adopts only the accepted final corrective behavior/test from:

```text
remote-orbit/Sources/RemoteOrbit/main.swift
remote-orbit/Tests/RemoteOrbitTests/DisabledShortClassifierTests.swift
```

The candidate control files are stale and must never be transplanted.

## Implementation authority

Authorized implementation branch:

`codex/dual-receiver-momentary-routing-v1`

Authorized isolated worktree:

`/private/tmp/remoteorbit-dual-receiver-momentary-routing-v1`

The implementation may execute plan Tasks 1 through 9 with TDD, focused regressions, commits, and push. It may then run the required automated pre-hardware validation, create a release test candidate, replace/restart only the RemoteOrbit app runtime for the explicitly authorized early hardware gate, verify exact runtime identity, and STOP for user-operated hardware acceptance.

No merge is authorized.

## Existing canonical checkout local state

The local handoff reports that an existing canonical checkout contains a pre-existing uncommitted `HIDMonitor.swift` modification. This is local-only state and has not been verified by Web.

The implementation executor must inspect that state read-only, must not clean/stash/reset/copy/overwrite it, and must not use the dirty canonical checkout for implementation. A fresh isolated worktree from authoritative `origin/main` is the only implementation workspace. The pre-existing dirty canonical file does not block isolated construction if the new worktree is clean and authority matches.

## Early hardware stop boundary

After Tasks 1-9 and automated validation, the executor may build/install/restart the exact implementation candidate, record source HEAD, executable SHA-256, app version/build, Bundle ID and running PID, then stop at:

`READY_FOR_USER_EARLY_HARDWARE_ACCEPTANCE`

The user performs the physical A/B/single-tap acceptance. Receiver shortcut changes are not delegated to the executor.

If hardware later reports unreliable classified synthetic Left/Right Option acceptance, construction stops with:

`SYNTHETIC_RECEIVER_TRIGGER_NOT_ACCEPTED`

and returns to architecture.
