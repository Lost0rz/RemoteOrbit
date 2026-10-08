# Dual-Receiver System-Mapped Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve RemoteOrbit's historically working device-scoped `hidutil` hardware-mapped voice trigger path while routing direct LONG to Receiver A and tap-then-LONG to Receiver B by temporarily switching the remote F5 mapping from A to B between the first and second physical presses.

**Architecture:** Idle dual mode keeps F5 mapped to Receiver A. A first quick release discards the captured A edge, then switches the existing `RemoteVoiceKeyMapping` and `VoiceKeyFilter` runtime target to Receiver B under the existing reconfiguration suppression guard. A second physical press is accepted only when B mapping is ready; its mapped B edge is captured by the existing `HardwareOptionGate` and released on first PCM. After B ownership closes, or after timeout/quick-release/failure, mapping is restored to A. CGEvent synthetic trigger remains fallback-only and is never the normal A/B path.

**Tech Stack:** Swift 5.9, macOS 13+, SwiftPM, IOKit HID monitoring, `/usr/bin/hidutil`, CGEvent filter/gate infrastructure already in RemoteOrbit.

**Spec:** `docs/superpowers/specs/2026-10-08-dual-receiver-system-mapped-trigger-design.md`

## Global Constraints

- Product contract: direct LONG -> A; quick first tap + second LONG -> B; isolated quick tap -> no action.
- `LONG_THRESHOLD_MS = 350`; `DOUBLE_WINDOW_MS = 300`.
- A initial key = Left Option; B initial key = Right Option.
- `HIDMonitor` remains the sole raw HID owner.
- `VoiceKeyFilter` / `HardwareOptionGate` remains the sole mapped-edge owner.
- `RemoteVoiceKeyMapping` remains the sole device-scoped mapping authority.
- Normal dual A/B routing MUST NOT call `VoiceOptionTrigger.sendDown(...key:)` or otherwise synthesize the selected receiver modifier.
- Generic `ButtonGestureRecognizer` timing is unchanged.
- BLE codec, tail timing, output-drain semantics, Persistent Session semantics, diagnostic authority, audio driver and TCC are out of scope.
- Mapping switch failures and second-press-before-B-ready are fail-closed.
- No merge before independent Web audit and user hardware acceptance.

## Review Focus

1. A second physical DOWN arriving while A->B mapping is still arming must open neither A nor B and must not be replayed later.
2. A stale A->B completion after timeout/cancel must not leave B mapped; it must converge back to A.
3. B->A restoration must occur only after B mapped-UP ownership is safely closed; never remap while B release is still owned.
4. A failed B->A restore must block all new voice gestures rather than leak B into the next gesture.
5. An asynchronous HID readback mismatch after an apparent successful `hidutil --set` must lock dual mode and converge to A before later gestures.

---

## File Structure

**Retain and modify from the accepted 019 implementation branch:**

- `remote-orbit/Sources/RemoteOrbit/main.swift` — AppController integration, existing `RemoteVoiceKeyMapping`, `VoiceKeyFilter`, `HardwareOptionGate`, `VoicePressCoordinator` hardware replay hooks.
- `remote-orbit/Sources/RemoteOrbit/DualReceiverVoiceGestureRecognizer.swift` — emit the first-short transition needed to start B arming; keep 350/300 classifier semantics.
- `remote-orbit/Sources/RemoteOrbit/DualReceiverVoiceMode.swift` — dual eligibility now requires primary A mapping readiness rather than an empty mapping.
- `remote-orbit/Sources/RemoteOrbit/AppStorage.swift` and `KeyMapping/SettingsView.swift` — retain accepted A/B preferences/UI with only copy/status adjustments if required.

**Create:**

- `remote-orbit/Sources/RemoteOrbit/DualReceiverMappedTriggerState.swift` — small state enum for A-ready / B-arming / B-ready / B-active / A-restoring / blocked/unavailable runtime mapping ownership. It does not execute `hidutil` and is not a second mapping authority.

**Tests:**

- `remote-orbit/Tests/RemoteOrbitTests/DualReceiverVoiceGestureRecognizerTests.swift`
- `remote-orbit/Tests/RemoteOrbitTests/DualReceiverVoiceModeTests.swift`
- `remote-orbit/Tests/RemoteOrbitTests/DualReceiverVoiceTransactionTests.swift`
- `remote-orbit/Tests/RemoteOrbitTests/VoiceTriggerRuntimeTests.swift`
- `remote-orbit/Tests/RemoteOrbitTests/VoicePressCoordinatorTests.swift`
- `remote-orbit/Tests/RemoteOrbitTests/RemoteVoiceKeyMappingTests.swift`
- `remote-orbit/Tests/RemoteOrbitTests/EventSuppressorTests.swift`
- `remote-orbit/Tests/RemoteOrbitTests/VoiceOptionTriggerTests.swift`

---

### Task 1: Establish v2 Baseline Without Losing Accepted 019 Work

**Files:**
- Control sync only before product mutation: `CURRENT_STATUS.md`, `CURRENT_TASK.md`, current spec and this plan.
- No product file change in this task.

**Interfaces:**
- Consumes: preserved 019 branch `codex/dual-receiver-momentary-routing-v1` at `c90edbf73ad9b0642fa344734571c0e806c0eb73`.
- Produces: clean v2 implementation branch/worktree with exact accepted 019 product implementation plus current authoritative control docs.

- [ ] **Step 1: Freshness and authority check**

Fetch/prune and verify authoritative `origin/main`, preserved branch HEAD, canonical remote and control files.

- [ ] **Step 2: Preserve unrelated local dirt**

Read-only record the pre-existing canonical `HIDMonitor.swift` modification. Do not clean/stash/reset/copy it.

- [ ] **Step 3: Create isolated v2 branch/worktree from preserved 019 branch**

Use:

```text
branch: codex/dual-receiver-system-mapped-routing-v2
worktree: /private/tmp/remoteorbit-dual-receiver-system-mapped-routing-v2
code base: c90edbf73ad9b0642fa344734571c0e806c0eb73
```

- [ ] **Step 4: Sync only current authoritative control/spec/plan files from `origin/main`**

Do not merge product history from `main`; do not replace 019 product files.

- [ ] **Step 5: Prove product baseline identity**

Verify that before new product edits the v2 product tree matches preserved product HEAD `ef29186e25c64cd4d1d7209cb2a41f95c51d4a11` except the known 019 control-only follow-up.

- [ ] **Step 6: Run accepted baseline tests**

Run:

```sh
swift test --package-path remote-orbit --filter DualReceiverVoiceGestureRecognizerTests
swift test --package-path remote-orbit --filter DualReceiverVoiceModeTests
swift test --package-path remote-orbit --filter DualReceiverVoiceTransactionTests
swift test --package-path remote-orbit --filter VoiceTriggerRuntimeTests
swift test --package-path remote-orbit --filter VoicePressCoordinatorTests
```

Expected: PASS.

- [ ] **Step 7: Commit control sync only**

No product mutation yet.

---

### Task 2: Change Dual-Mode Eligibility From Empty Mapping to Primary-A Mapping

**Files:**
- Modify: `remote-orbit/Sources/RemoteOrbit/DualReceiverVoiceMode.swift`
- Modify: `remote-orbit/Sources/RemoteOrbit/main.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/DualReceiverVoiceModeTests.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/VoiceTriggerRuntimeTests.swift`

**Interfaces:**
- Consumes: existing `applyVoiceHIDMapping(Bool, VoiceTriggerKey) -> Bool` injected seam.
- Produces: active dual mode with A mapping enabled and filter target A; no mapping-clear normal state.

- [x] **Step 1: Write RED tests**

Add tests asserting:

```text
eligible dual config + A mapping apply succeeds
-> active(A,B)
-> mapping call is enabled=true,target=A

A mapping apply fails
-> unavailable(primaryMappingUnavailable)
-> no voice prewarm/route

secondary Off
-> legacy behavior unchanged
```

- [x] **Step 2: Run RED**

```sh
swift test --package-path remote-orbit --filter DualReceiverVoiceModeTests
swift test --package-path remote-orbit --filter VoiceTriggerRuntimeTests
```

Expected: failures because 019 still clears mapping for dual mode.

- [x] **Step 3: Minimal implementation**

Replace `mappingClearSucceeded` semantics with `primaryMappingReady`. Remove dual activation's normal `setEnabled(false, A)` path. On eligible dual activation/connect, ensure `setEnabled(true, A)` succeeds and filter is configured to A before mode becomes active.

- [x] **Step 4: GREEN + legacy regression**

Run the two focused suites plus `VoicePersistentSessionTests`.

- [x] **Step 5: Commit**

Commit only dual eligibility/mapping-baseline changes.

---

### Task 3: Expose the First-Short Transition From the Pure Gesture Classifier

**Files:**
- Modify: `remote-orbit/Sources/RemoteOrbit/DualReceiverVoiceGestureRecognizer.swift`
- Modify: `remote-orbit/Tests/RemoteOrbitTests/DualReceiverVoiceGestureRecognizerTests.swift`

**Interfaces:**
- Produces: `Event.awaitingSecondPress(gestureID:firstUpAt:)` in addition to existing `.classified` and `.noAction`.

- [x] **Step 1: Write RED tests**

Assert that a first press released below 350 ms emits exactly one awaiting-second event immediately at first UP, while direct LONG emits no awaiting-second event.

- [x] **Step 2: Run RED**

```sh
swift test --package-path remote-orbit --filter DualReceiverVoiceGestureRecognizerTests
```

- [x] **Step 3: Add the event without changing timing semantics**

The event reports state transition only; classifier remains pure and does not execute mapping or transport actions.

- [x] **Step 4: GREEN**

Confirm all existing 350/300 boundary, stale timer, cancel and disconnect tests still pass.

- [x] **Step 5: Commit**

---

### Task 4: Add Explicit Runtime Mapping-Ownership State

**Files:**
- Create: `remote-orbit/Sources/RemoteOrbit/DualReceiverMappedTriggerState.swift`
- Modify: `remote-orbit/Sources/RemoteOrbit/main.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/VoiceTriggerRuntimeTests.swift`

**Interfaces:**
- Produces runtime phases:

```swift
primaryReady
armingSecondary(gestureID:generation:)
secondaryReady(gestureID:)
secondaryActive(gestureID:)
restoringPrimary(generation:)
blockedUntilRelease(gestureID:)
unavailable(reason:)
```

- [x] **Step 1: Write RED runtime-state tests**

Cover idle A-ready, A->B arming, B-ready, blocked-second-press, restore-A, stale generation ignored, and unavailable restore failure.

- [x] **Step 2: Run RED**

```sh
swift test --package-path remote-orbit --filter VoiceTriggerRuntimeTests
```

- [x] **Step 3: Implement only state ownership**

Do not move `hidutil` execution out of `RemoteVoiceKeyMapping`; this state object/controller layer only records which mapping owns the next press.

- [x] **Step 4: GREEN**

- [x] **Step 5: Commit**

---

### Task 5: Restore Direct-A to the Existing Hardware-Mapped Gate Path

**Files:**
- Modify: `remote-orbit/Sources/RemoteOrbit/main.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/DualReceiverVoiceTransactionTests.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/VoicePressCoordinatorTests.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/VoiceOptionTriggerTests.swift`

**Interfaces:**
- Consumes: A mapping already active; `VoiceKeyFilter.beginOptionDeferral`; existing first-PCM `onHardwareOptionGateLongReady` replay path.
- Produces: classified direct A hold with `usesHardwareOptionPath=true`; no synthetic A edge.

- [x] **Step 1: Write RED tests**

Assert:

```text
first raw DOWN in primaryReady
-> A hardware gate begins
350ms classification A
-> activate voice
before first PCM -> A external replay 0
first PCM -> hardware gate long-ready/replay exactly once
VoiceOptionTrigger keyed synthetic edges = 0
release + drain -> matching hardware A UP
```

- [x] **Step 2: Run RED**

```sh
swift test --package-path remote-orbit --filter DualReceiverVoiceTransactionTests
swift test --package-path remote-orbit --filter VoicePressCoordinatorTests
swift test --package-path remote-orbit --filter VoiceOptionTriggerTests
```

- [x] **Step 3: Replace 019 classified-synthetic normal path for A**

Use an explicit already-classified hardware-hold entry; do not re-enter the legacy 300 ms classifier.

- [x] **Step 4: GREEN**

Required invariant: no second long wait and no normal synthetic trigger.

- [x] **Step 5: Commit**

---

### Task 6: Arm Receiver B After First Quick Release Using Existing Reconfiguration Suppression

**Files:**
- Modify: `remote-orbit/Sources/RemoteOrbit/main.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/VoiceTriggerRuntimeTests.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/EventSuppressorTests.swift`

**Interfaces:**
- Consumes: `.awaitingSecondPress`, `VoiceKeyFilter.beginVoiceTriggerReconfiguration(from:to:)`, `applyVoiceHIDMapping(true,B)` on the existing serial mapping queue.
- Produces: `secondaryReady` only after B apply success and filter target B are both committed.

- [x] **Step 1: Write RED tests for successful A->B arm**

Expected order:

```text
first quick UP
-> discard/cancel captured A gate
-> begin reconfiguration(A,B)
-> mapping apply enabled=true,B
-> configure filter B
-> end reconfiguration
-> secondaryReady
```

Assert no A/B receiver replay and no synthetic edge during the transition.

- [x] **Step 2: Write RED failure tests**

Cover mapping apply failure, filter configure failure, stale completion after timeout/cancel, and concurrent configuration change.

- [x] **Step 3: Run RED**

```sh
swift test --package-path remote-orbit --filter VoiceTriggerRuntimeTests
swift test --package-path remote-orbit --filter EventSuppressorTests
```

- [x] **Step 4: Implement A->B arm on the existing mapping queue**

`B_MAPPING_READY` means:

```text
hidutil --set B returned success
AND filter runtime key == B
AND reconfiguration suppression safely ended
```

Do NOT wait for asynchronous diagnostic readback before admitting the second press. Record `A_TO_B_APPLY_MS` using monotonic time. Existing readback remains asynchronous evidence.

- [x] **Step 5: Handle asynchronous readback mismatch**

If later readback for the active generation reports mismatch/unparseable in a way that disproves requested B mapping, lock dual mode, suppress new gestures and converge to A. A stale readback from an older generation must not override the current state.

- [x] **Step 6: GREEN**

- [x] **Step 7: Commit**

---

### Task 7: Fail Closed When the Second DOWN Arrives Before B Is Ready

**Files:**
- Modify: `remote-orbit/Sources/RemoteOrbit/main.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/VoiceTriggerRuntimeTests.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/DualReceiverVoiceTransactionTests.swift`

**Interfaces:**
- Consumes: `armingSecondary` / `secondaryReady` mapping phase.
- Produces: second press admitted only in `secondaryReady`.

- [x] **Step 1: Write RED test with injected mapping delay**

Use existing harness mapping delay so second raw DOWN occurs before B apply completion.

Assert:

```text
A external edge = 0
B external edge = 0
synthetic edge = 0
BLE activation = 0 for that second press
attempt enters blockedUntilRelease
late B apply does not replay/buffer the already-held second press
```

- [x] **Step 2: Write RED cleanup test**

After blocked second UP, converge to A; new gesture is rejected until A restore succeeds.

- [x] **Step 3: Implement fail-closed admission**

Never buffer a second DOWN across a mapping switch because remapping an already-held F5 cannot guarantee a fresh B DOWN edge.

- [x] **Step 4: GREEN**

- [x] **Step 5: Commit**

---

### Task 8: Route a Ready Second Press Through the Existing Hardware Gate as Receiver B

**Files:**
- Modify: `remote-orbit/Sources/RemoteOrbit/main.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/DualReceiverVoiceTransactionTests.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/VoicePressCoordinatorTests.swift`

**Interfaces:**
- Consumes: `secondaryReady`, filter target B, physical second F5 mapped to B.
- Produces: B hardware gate capture, 350 ms B classification, first-PCM replay of B DOWN.

- [x] **Step 1: Write RED tests**

Assert:

```text
secondaryReady + second raw DOWN
-> begin hardware deferral under B
second hold 350ms -> classify B
first PCM -> hardware B DOWN replay exactly once
A replay = 0
synthetic = 0
```

- [x] **Step 2: Run RED**

```sh
swift test --package-path remote-orbit --filter DualReceiverVoiceTransactionTests
swift test --package-path remote-orbit --filter VoicePressCoordinatorTests
```

- [x] **Step 3: Implement classified B hardware hold**

Reuse the same already-classified hardware-hold entry as A; selected key is diagnostic/ownership metadata, not a synthetic trigger instruction.

- [x] **Step 4: GREEN**

- [x] **Step 5: Commit**

---

### Task 9: Restore A After Timeout, B Quick Release, and Completed B Transaction

**Files:**
- Modify: `remote-orbit/Sources/RemoteOrbit/main.swift`
- Modify: filter callback surface in `main.swift` only as required to signal safely closed held hardware ownership.
- Test: `remote-orbit/Tests/RemoteOrbitTests/VoiceTriggerRuntimeTests.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/DualReceiverVoiceTransactionTests.swift`

**Interfaces:**
- Consumes: B mapping phases and HardwareOptionGate safe-close lifecycle.
- Produces: verified runtime return to primary A before next gesture.

- [ ] **Step 1: RED — no second press timeout**

After <=300 ms window expires, restore B->A and cancel prewarm. New first press is admitted only after A restore succeeds.

- [ ] **Step 2: RED — second quick release**

Discard captured B down/up, expose neither receiver, then restore A.

- [ ] **Step 3: RED — completed B long transaction**

Do not start B->A remap merely at physical UP or output-drain start. Restore only after held mapped B UP ownership is safely closed.

- [ ] **Step 4: RED — restore failure**

A restore failure -> `.unavailable` / runtime lock; later gesture, prewarm and receiver edges all remain zero.

- [ ] **Step 5: Implement safe-close callback and serialized restore**

Use generation tokens so stale restore/arm completions cannot overwrite a newer state.

- [ ] **Step 6: GREEN**

- [ ] **Step 7: Commit**

---

### Task 10: Disconnect, Transport Loss, Runtime Reconfiguration, and Async Readback Safety

**Files:**
- Modify: `remote-orbit/Sources/RemoteOrbit/main.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/VoiceTriggerRuntimeTests.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/DualReceiverVoiceTransactionTests.swift`

**Interfaces:**
- Produces: deterministic convergence to A or unavailable state on exceptional paths.

- [ ] **Step 1: Add RED tests**

Cover:

```text
HID disconnect while arming B
HID disconnect while B ready
BLE loss before first PCM A/B
BLE loss after B replay
user A/B setting change while B armed/active/restoring
stale mapping completion
stale async readback mismatch
```

- [ ] **Step 2: Implement minimum cleanup**

Do not redesign disconnect/BLE subsystems; only ensure mapping/gate ownership converges safely.

- [ ] **Step 3: GREEN**

- [ ] **Step 4: Commit**

---

### Task 11: Settings and Legacy Regression

**Files:**
- Modify only if necessary: `AppStorage.swift`, `KeyMapping/SettingsView.swift`
- Test: `DualReceiverVoiceSettingsTests.swift`, `VoicePersistentSessionTests.swift`

**Interfaces:**
- Retains accepted 019 Receiver A/Receiver B configuration.

- [ ] **Step 1: Verify no new UI is required**

A and B preferences already exist. Do not add provider/backend controls.

- [ ] **Step 2: Add/adjust regression assertions**

```text
secondary Off -> legacy single-receiver mapping
A == B -> no dual mode
SHORT not Disabled -> no dual mode
settings change busy during arming/active/restoring
Persistent trigger preference remains independent
```

- [ ] **Step 3: Run GREEN**

```sh
swift test --package-path remote-orbit --filter DualReceiverVoiceSettingsTests
swift test --package-path remote-orbit --filter VoicePersistentSessionTests
```

- [ ] **Step 4: Commit only if files/tests changed**

---

### Task 12: Full Automated Validation and Exact Candidate Build

**Files:** no new design work.

- [ ] **Step 1: Focused suites**

Run:

```sh
swift test --package-path remote-orbit --filter DisabledShortClassifierTests
swift test --package-path remote-orbit --filter DualReceiverVoiceGestureRecognizerTests
swift test --package-path remote-orbit --filter DualReceiverVoiceModeTests
swift test --package-path remote-orbit --filter DualReceiverVoiceSettingsTests
swift test --package-path remote-orbit --filter DualReceiverVoiceTransactionTests
swift test --package-path remote-orbit --filter VoicePressCoordinatorTests
swift test --package-path remote-orbit --filter VoiceOptionTriggerTests
swift test --package-path remote-orbit --filter EventSuppressorTests
swift test --package-path remote-orbit --filter RemoteVoiceKeyMappingTests
swift test --package-path remote-orbit --filter VoiceTriggerRuntimeTests
swift test --package-path remote-orbit --filter VoicePersistentSessionTests
swift test --package-path remote-orbit --filter BLEBridgeTests
```

- [ ] **Step 2: Full suite/self-tests/build**

```sh
swift test --package-path remote-orbit
./remote-orbit/run-self-tests.sh
./remote-orbit/package-app.sh
git diff --check
```

- [ ] **Step 3: Scope audit**

Must report:

```text
NORMAL_DUAL_SYNTHETIC_TRIGGER = NO
VIRTUAL_HID_PROVIDER_ADDED = NO
SECOND_HID_OWNER_ADDED = NO
GENERIC_GESTURE_TIMING_CHANGED = NO
BLE_CODEC_CHANGED = NO
TAIL_DRAIN_CHANGED = NO
PERSISTENT_SESSION_SEMANTICS_CHANGED = NO
IDLE_DUAL_MAPPING_TARGET = A
B_MAPPING_ONLY_DURING_B_WINDOW_OR_TRANSACTION = YES
SECOND_PRESS_BEFORE_B_READY_FAILS_CLOSED = YES
```

- [ ] **Step 4: Commit/push exact candidate and verify clean local/remote match**

No merge.

---

### Task 13: Early Hardware Acceptance in Three Separate Sets

**Files:** runtime only after automated PASS.

- [ ] **Step 1: Install/restart exact candidate**

Replace only `/Applications/RemoteOrbit.app`, restart RemoteOrbit only, verify source HEAD/hash/version/build/PID and initial mapping A.

- [ ] **Step 2: Stop for Set A**

User performs 5 direct LONGs.

Required:

```text
A opens 5/5
B opens 0/5
normal trigger source = captured system-mapped A
synthetic normal edges = 0
```

If A fails, STOP; do not test B.

- [ ] **Step 3: Stop for Set B**

User performs 5 natural quick-first-tap + second-LONG gestures.

Required:

```text
first tap opens neither receiver
B_MAPPING_READY before accepted second DOWN
B opens 5/5 accepted attempts
A opens 0/5
synthetic normal edges = 0
A_TO_B_APPLY_MS recorded for every attempt
```

If a second DOWN beats B readiness, classify that attempt explicitly as `B_MAPPING_NOT_READY_FAIL_CLOSED`; do not count it as receiver misrouting and do not hide it. If this happens at a material rate under natural use, return to Web for timing/UX decision rather than widening unsafe behavior.

- [ ] **Step 4: Stop for Set C**

User performs 5 isolated quick taps.

Required:

```text
A opens 0/5
B opens 0/5
A mapping restored after each window
```

- [ ] **Step 5: Return for independent Web audit**

Required final state:

`WAITING_FOR_INDEPENDENT_WEB_AUDIT`

Do not merge or proceed to broader A/B/A/B soak until Web accepts Sets A/B/C.
