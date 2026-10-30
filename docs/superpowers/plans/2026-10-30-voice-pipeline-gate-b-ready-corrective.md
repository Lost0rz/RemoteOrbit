# Gate B Strict ATVV READY Corrective Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or the already selected inline execution method) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent ATVV READY and MIC_OPEN until characteristic discovery, both notify confirmations, and capabilities are all positively established.

**Architecture:** Keep the existing `BLEBridge` and dedicated `com.remoteorbit.ble` writer. Add readiness facts to `BLEVoiceTransportState`; every fact-recording path calls one idempotent evaluator, while failures and resets clear the facts.

**Tech Stack:** Swift, CoreBluetooth, XCTest, SwiftPM.

**Spec:** `docs/superpowers/specs/2026-10-30-voice-pipeline-gate-b-ready-corrective-design.md`

## Global Constraints

- Preserve the dedicated BLE queue and connection persistence model.
- Preserve ATVV bytes/order/codec/ADPCM/sample rate/AUDIO_SYNC, AudioPipe, CoreAudio, jitter, Gate A semantics, driver, packaging/install/TCC/Air, and Gate C/D/E boundaries.
- Do not modify `AudioPipe.swift`.
- Update `CURRENT_STATUS.md` and `CURRENT_TASK.md` together only in the final corrective commit.

## Review Focus

- Capabilities-first and notify-first order must converge exactly once to READY.
- A single notify confirmation must never make the transport READY.
- Notify error or disabled state must clear reusable readiness through the existing failure path.
- Reset/new connection must clear all old subscription facts and obsolete callbacks must not satisfy a new setup.
- A queued voice intent must not emit MIC_OPEN before strict READY, while normal READY reuse must preserve confirmed facts.

### Task 1: Readiness contract tests

**Files:**
- Modify: `remote-orbit/Tests/RemoteOrbitTests/BLEBridgeTests.swift`

- [ ] **Step 1: Add failing state tests** for the five required facts, capabilities-first, notify-first, partial notify, notify failure/reset clearing, READY reuse, and strict MIC_OPEN eligibility.
- [ ] **Step 2: Run the focused BLEBridge tests and verify RED** because the current state has no subscription facts/evaluator and capabilities directly call READY.

### Task 2: Minimal strict evaluator

**Files:**
- Modify: `remote-orbit/Sources/RemoteOrbit/BLEBridge.swift`
- Test: `remote-orbit/Tests/RemoteOrbitTests/BLEBridgeTests.swift`

- [ ] **Step 1: Add queue-owned readiness facts and an idempotent `evaluateATVVReadiness()`**; only the evaluator may transition transport READY.
- [ ] **Step 2:** Record characteristic discovery, notification confirmations, and accepted capabilities through the evaluator; require strict READY in `requestMicOpenIfReady()`.
- [ ] **Step 3:** Clear readiness facts in new connection/reset paths, preserve them on normal voice close, and keep current-peripheral/characteristic identity guards for obsolete callbacks.
- [ ] **Step 4:** Run focused BLE and grace/tail suites and verify GREEN.

### Task 3: Gate B verification and handoff

**Files:**
- Modify: `CURRENT_STATUS.md`
- Modify: `CURRENT_TASK.md`
- Modify: authorized corrective implementation/test files only

- [ ] **Step 1: Run required focused suites, full Swift tests, arm64/x86_64 release builds, protocol self-tests, and `git diff --check`.
- [ ] **Step 2: Inspect the diff for unchanged AudioPipe, protocol, jitter, Gate A, and Gate C/D/E boundaries.
- [ ] **Step 3: Revalidate exact branch/HEAD/remote, update both controls together, commit as a direct child of the audited head, push only the authorized branch, verify remote exactness, and stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`.

## Plan self-review

- All card behaviors map to Task 1 tests or Task 2 state/bridge changes.
- The evaluator is the only production READY transition; no second transport object or AudioPipe change is introduced.
- Verification includes both orderings, partial/failure/reset behavior, reuse, and all required repository gates.
