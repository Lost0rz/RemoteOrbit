# RemoteOrbit Physical Option Primary Corrective Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore the verified `v0.2.11` Physical Option Primary / Synthetic Fallback voice behavior on PR #4 while retaining reliability diagnostics and closing the late-hardware-edge race.

**Architecture:** Keep `VoicePressCoordinator` as the gesture/session owner, restore `RemoteVoiceKeyMapping` as the device-scoped F5 → Left Option production input, and put physical Option deferral/replay/fallback ownership in `HardwareOptionGate` inside `VoiceKeyFilter`. Synthetic Option remains an actuator used only when mapping is unavailable or the captured physical event cannot be copied/replayed. `VoiceSessionDiagnostics` records the selected source and never controls ownership.

**Tech Stack:** Swift 5.9, macOS 13+, Swift Package Manager, AppKit/CoreGraphics/IOKit, XCTest, shell self-tests.

**Spec:** `/Users/jack7788/.codex/attachments/e4824eb6-8300-45c8-8fdf-6c022c974166/pasted-text.txt`

## Global Constraints

- Frozen production baseline: `v0.2.11` / `48a6d54ffa1a2798ac9ac760673d6406cec6bf12`.
- Work only on branch `codex/voice-single-owner-option`; do not reset, rebase, force-push, or modify `main`, the tag, Release metadata, or merged history.
- Normal voice path is `physical remote F5 → device-scoped hidutil F5 → Left Option → CGEvent gate → VoicePressCoordinator → physical replay/release`.
- Synthetic Option is fallback only; a normal long press must not unconditionally send synthetic DOWN after PCM.
- Keep the existing hold threshold, BLE tail-drain behavior, audio decoding, gain, driver, button mappings, HUD, settings UX, general injection, Obsidian/FloatTabs/Codex actions, and release metadata unchanged unless compilation requires a related edit.
- Retain `VoiceReliabilityLog.swift`, `VoiceSessionDiagnostics.swift`, observer evidence, stale-callback diagnostics, summary output, and rotation logic.
- Do not edit `RELEASE_NOTES_v0.2.11.md`.
- The PR remains `OPEN + Draft + unmerged`; hardware acceptance is not replaced by local tests.

---

### Task 1: Freeze the audit evidence and test seams

**Files:**
- Read: `remote-orbit/Sources/RemoteOrbit/main.swift`
- Read: `remote-orbit/Sources/RemoteOrbit/VoiceOptionTrigger.swift`
- Read: `remote-orbit/Sources/RemoteOrbit/VoiceSessionDiagnostics.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/VoiceOptionTriggerTests.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/VoicePressCoordinatorTests.swift`

**Interfaces:**
- Consumes: current PR HEAD `799c91a7dc4086221d4dec64658dfcce865565ff`, `origin/main`, and `v0.2.11` checks already recorded before implementation.
- Produces: tests that express hardware ownership, fallback ownership, late-edge suppression, and no-PCM cancellation without altering product code.

- [x] **Step 1: Confirm repository state**

Run:

```bash
git status --short
git branch --show-current
git rev-parse HEAD
git rev-parse origin/main
git rev-list -n 1 v0.2.11
```

Expected: clean tree, branch `codex/voice-single-owner-option`, `HEAD=799c91a7dc4086221d4dec64658dfcce865565ff`, and both `origin/main` and `v0.2.11` equal `48a6d54ffa1a2798ac9ac760673d6406cec6bf12`.

- [x] **Step 2: Add the physical-primary regression tests**

Add XCTest cases for physical long, physical short, custom short cancellation, mapping-unavailable fallback, no PCM, and the late-hardware race. The gate test should have this shape:

```swift
func testFallbackOwnerSuppressesLateHardwareEdge() {
    let gate = HardwareOptionGate()
    let session = UUID()

    XCTAssertTrue(gate.begin(sessionID: session))
    XCTAssertEqual(gate.resolve(sessionID: session), .noOptionEdge)
    XCTAssertEqual(
        gate.selectFallback(sessionID: session, reason: "no-option-edge"),
        .syntheticDown
    )
    XCTAssertTrue(gate.shouldSuppressLateHardwareEvent(.down, sessionID: session))
    XCTAssertTrue(gate.shouldSuppressLateHardwareEvent(.up, sessionID: session))
}
```

The coordinator test must pass `usesHardwareOption: true`, capture the long-ready callback, assert no synthetic events after first PCM, and assert the hardware callback is the selected path. Existing synthetic-only expectations must explicitly pass `usesHardwareOption: false`.

- [x] **Step 3: Run only the new tests and confirm RED**

Run:

```bash
swift test --filter VoiceOptionTriggerTests.testFallbackOwnerSuppressesLateHardwareEdge
swift test --filter VoicePressCoordinatorTests.testPhysicalLongPathReleasesHardwareWithoutSyntheticEvents
```

Expected: compilation/test failure because the current PR has no `HardwareOptionGate`, no hardware callbacks, and no `usesHardwareOption` parameter. Do not modify production code before observing this failure.

### Task 2: Restore and harden the Hardware Option gate

**Files:**
- Modify: `remote-orbit/Sources/RemoteOrbit/VoiceOptionTrigger.swift`
- Modify: `remote-orbit/Sources/RemoteOrbit/VoiceSessionDiagnostics.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/VoiceOptionTriggerTests.swift`

**Interfaces:**
- Consumes: `VoiceOptionTrigger` session identity and the existing diagnostics object.
- Produces: `HardwareOptionEdge`, `HardwareOptionResolution`, `HardwareOptionOwner`, and `HardwareOptionGate` with `begin`, `capture`, `resolve`, `selectFallback`, `shouldSuppressLateHardwareEvent`, `completeHardwareReplay`, and `cancel` semantics.

- [x] **Step 1: Implement the ownership state machine**

Use states equivalent to `waitingForHardware`, `hardwareOwned`, `fallbackOwned`, `resolved`, and `cancelled`. A copied physical down selects hardware; a missing edge or failed copy selects fallback only when the caller explicitly allows fallback. Keep the active session identity while fallback owns the gesture so late mapped events can be suppressed.

- [x] **Step 2: Preserve the v0.2.11 resolutions**

Return `.hardwareReplay` for a copied physical down, `.syntheticTap` for an uncopyable captured pair, `.syntheticDown` for an uncopyable down-only edge, and `.noOptionEdge` when no mapped edge was observed. The gate must not clear itself merely because fallback was selected.

- [x] **Step 3: Add late-edge suppression behavior**

When fallback owns a session, return suppression for both late down and late up. When a hardware down was replayed but its up arrived after resolution, pass through exactly that up and close the gate; suppress any duplicate down. When the gate is cancelled, pass all subsequent events through normally.

- [x] **Step 4: Run gate tests GREEN**

Run:

```bash
swift test --filter VoiceOptionTriggerTests
```

Expected: all gate ownership, copy-failure, stale-session, and late-edge tests pass.

### Task 3: Restore physical mapping, filter capture, and coordinator callbacks

**Files:**
- Modify: `remote-orbit/Sources/RemoteOrbit/main.swift`
- Modify: `remote-orbit/Sources/RemoteOrbit/VoiceOptionTrigger.swift`
- Modify: `remote-orbit/Tests/RemoteOrbitTests/VoicePressCoordinatorTests.swift`

**Interfaces:**
- Consumes: `HardwareOptionGate` and `HardwareOptionResolution` from Task 2.
- Produces: device-scoped `RemoteVoiceKeyMapping`, `VoiceKeyFilter` Option deferral/replay, and `VoicePressCoordinator` physical-primary routing.

- [x] **Step 1: Restore `RemoteVoiceKeyMapping`**

Restore matching `VendorID=0x2717`, `ProductID=0x32B8`, the F5 usage `0x70000003E`, and Left Option destination `0x7000000E2`. Keep `setEnabled(true)` on supported HID connection, `setEnabled(false)` on disconnect and app termination, and expose `isEnabled` for source selection. A failed enable must select synthetic fallback for that session; it must not disable all voice input.

- [x] **Step 2: Restore coordinator ownership fields and callbacks**

Restore `usesHardwareOption` in accepted and deferred presses, `usesHardwareOptionPath`, and these callbacks:

```swift
var onHardwareOptionGateBegin: ((UUID) -> Void)?
var onHardwareOptionGateLongReady: ((UUID) -> Void)?
var onHardwareOptionGateShortResult: ((UUID, Bool) -> Void)?
var onHardwareOptionGateCancel: ((UUID) -> Void)?
```

For a hardware long press, first PCM invokes the gate callback and produces zero synthetic requests. For a fallback long press, first PCM sends synthetic DOWN and later a balanced UP. Default physical short releases the captured pair; custom or disabled short cancels/drops the captured pair and runs only the custom action.

- [x] **Step 3: Restore `VoiceKeyFilter` event mask and scoped capture**

Include `keyDown`, `keyUp`, and `flagsChanged`. While `HardwareOptionGate` is active, inspect only `VK.option`, copy the mapped down/up events, record their edge, return `nil` for deferred or late-suppressed events, and pass through an up received before a down. Outside the active gate, real keyboard Option behavior remains unchanged.

- [x] **Step 4: Wire AppController source selection**

On raw HID microphone down, pass `usesHardwareOption: RemoteVoiceKeyMapping.isEnabled` and `source: "raw-hid"`. On CGEvent F5 fallback, pass `usesHardwareOption: false` and `source: "cgevent-fallback"`. Wire all four gate callbacks to `VoiceKeyFilter` and remove the global `LegacyVoiceMappingSafety` block. Mapping enable failure is logged and diagnosed, then the current gesture is allowed to use synthetic fallback.

- [x] **Step 5: Run coordinator and regression tests GREEN**

Run:

```bash
swift test --filter VoicePressCoordinatorTests
```

Expected: physical-primary long/short, synthetic fallback, no-PCM, rapid repress, stale callback, tail, and disconnect tests pass with no threshold or drain timing changes.

### Task 4: Make diagnostics Option-source aware

**Files:**
- Modify: `remote-orbit/Sources/RemoteOrbit/VoiceSessionDiagnostics.swift`
- Modify: `remote-orbit/Sources/RemoteOrbit/VoiceOptionTrigger.swift`
- Modify: `remote-orbit/Sources/RemoteOrbit/VoiceSyntheticOptionObserver.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/VoiceSessionDiagnosticsTests.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/VoiceSyntheticOptionObserverTests.swift`

**Interfaces:**
- Consumes: gate callbacks and synthetic trigger requests from Tasks 2–3.
- Produces: source-aware events and summaries containing `optionOwner`, `hardwareDownSeen`, `hardwareUpSeen`, `hardwareReplayPerformed`, `syntheticDownRequests`, `syntheticUpRequests`, `lateHardwareSuppressed`, and `fallbackReason`.

- [x] **Step 1: Add structured owner and hardware evidence methods**

Record `OPTION_OWNER_SELECTED` with `owner=hardware` or `owner=synthetic_fallback`, `HARDWARE_OPTION_DOWN_CAPTURED`, `HARDWARE_OPTION_UP_CAPTURED`, `HARDWARE_OPTION_REPLAY`, `HARDWARE_OPTION_COPY_FAILED`, `SYNTHETIC_FALLBACK_ARMED`, and `LATE_HARDWARE_OPTION_SUPPRESSED`. Keep existing PCM, BLE, focus, tail, stale callback, rotation, and summary events.

- [x] **Step 2: Keep synthetic observer fallback-only**

Correlate synthetic observations only with sessions whose owner is `synthetic_fallback`. A hardware-primary session with no synthetic observation must not gain an invariant violation. Existing synthetic observer classification and listen-only behavior remain unchanged.

- [x] **Step 3: Add summary assertions**

Verify physical sessions report `optionOwner=hardware`, `hardwareReplayPerformed=true`, and zero synthetic requests; fallback sessions report `optionOwner=synthetic_fallback`, the reason, and balanced synthetic counts. Verify no-PCM reports no owner and zero Option requests.

- [x] **Step 4: Run diagnostics tests GREEN**

Run:

```bash
swift test --filter VoiceSessionDiagnosticsTests
swift test --filter VoiceSyntheticOptionObserverTests
```

Expected: source-aware summary and observer tests pass without changing log rotation behavior.

### Task 5: Correct documentation without changing release history

**Files:**
- Modify: `README.md`
- Modify: `SETUP_NOTES.md`
- Do not modify: `RELEASE_NOTES_v0.2.11.md`

**Interfaces:**
- Consumes: final source-aware event names and lifecycle from Tasks 3–4.
- Produces: documentation stating physical mapped Option is preferred, `HardwareOptionGate` owns deferral/replay, and synthetic trigger is fallback only.

- [x] **Step 1: Replace synthetic-only lifecycle statements**

Correct statements that say the application always owns a synthetic lifecycle, never enables hidutil mapping, or sends synthetic DOWN for every normal long press. Document mapping enable/disable lifecycle and fallback reasons.

- [x] **Step 2: Document hardware acceptance logs**

Document H1 normal long, H2 default short, H3 custom short, H4 repeated long, and H5 disconnect/reconnect expectations, including `optionOwner=hardware` and zero synthetic DOWN requests on H1.

- [x] **Step 3: Verify release notes unchanged**

Run:

```bash
git diff -- RELEASE_NOTES_v0.2.11.md
```

Expected: no output.

### Task 6: Full regression, audit, and corrective commits

**Files:**
- All files changed by Tasks 2–5, limited to the voice path, diagnostics, tests, and README/SETUP_NOTES.

**Interfaces:**
- Consumes: all task changes.
- Produces: verified corrective commits on the current PR branch and a hardware acceptance checklist; no merge/readiness state change.

- [x] **Step 1: Run the complete verification set**

Run from `remote-orbit/`:

```bash
swift test
./run-self-tests.sh
swift build -c release
```

Run from the repository root:

```bash
git diff --check
rg "LegacyVoiceMapping|RemoteVoiceKeyMapping|HardwareOptionGate|flagsChanged|syntheticOptionTrigger.sendDown|OPTION_OWNER" remote-orbit/Sources/RemoteOrbit remote-orbit/Tests/RemoteOrbitTests README.md SETUP_NOTES.md
git diff -- RELEASE_NOTES_v0.2.11.md
```

Expected: full Swift tests, self-tests, release build, and whitespace checks pass; required physical-primary symbols exist; no normal-long unconditional synthetic assumption remains; release notes are unchanged.

- [x] **Step 2: Inspect final diff and status**

Run:

```bash
git diff --stat v0.2.11...HEAD
git diff --name-status
git status --short
git log --oneline --decorate -8
```

Confirm only voice-path corrective, diagnostics, tests, and documentation files changed, with no reset/rebase.

- [x] **Step 3: Create auditable corrective commits**

Use separate commits where the diff boundaries remain clean:

```bash
git add remote-orbit/Tests/RemoteOrbitTests/VoiceOptionTriggerTests.swift remote-orbit/Tests/RemoteOrbitTests/VoicePressCoordinatorTests.swift
git commit -m "test: restore physical-primary voice contract"
git add remote-orbit/Sources/RemoteOrbit/main.swift remote-orbit/Sources/RemoteOrbit/VoiceOptionTrigger.swift
git commit -m "fix: restore hardware option primary path"
git add remote-orbit/Sources/RemoteOrbit/VoiceSessionDiagnostics.swift remote-orbit/Sources/RemoteOrbit/VoiceSyntheticOptionObserver.swift remote-orbit/Tests/RemoteOrbitTests/VoiceSessionDiagnosticsTests.swift remote-orbit/Tests/RemoteOrbitTests/VoiceSyntheticOptionObserverTests.swift
git commit -m "feat: make voice diagnostics option-source aware"
git add README.md SETUP_NOTES.md docs/superpowers/plans/2026-09-15-restore-physical-option-primary.md
git commit -m "docs: restore physical-primary voice lifecycle"
```

If a test and its implementation must remain in one atomic commit for compilation, combine only that dependent pair and report the actual commit list. Do not squash or rewrite existing PR commits.

- [ ] **Step 4: Re-run verification after commits**

Repeat `swift test`, `./run-self-tests.sh`, `swift build -c release`, `git diff --check`, and the required `rg` audit against the committed tree. Record `REMOTE_MAIN`, old/new/remote PR HEAD, clean/dirty status, every contract result, command output summary, hardware acceptance as `NOT RUN`, changed files, commits, and unresolved risks.

## Coverage review

- Physical mapping and lifecycle: Task 3.
- Hardware gate and original race: Tasks 2–3.
- Late hardware edge after fallback: Tasks 2–3.
- Long/short/custom/no-PCM/fallback/rapid-repress/disconnect tests: Tasks 1 and 3.
- Reliability diagnostics retention and source-aware summaries: Task 4.
- Documentation correction and release-note protection: Task 5.
- Full verification and PR state preservation: Task 6.
