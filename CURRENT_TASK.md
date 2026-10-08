# RemoteOrbit Current Task

## Current task — SYSTEM-MAPPED DUAL-RECEIVER V2 IMPLEMENTATION

- **Status:** WAITING FOR USER SET A / IMPLEMENTATION, AUTOMATED VALIDATION AND CANDIDATE INSTALL COMPLETE
- **Task ID:** `RO-DUAL-RECEIVER-SYSTEM-MAPPED-IMPLEMENTATION-023`
- **Previous task:** `RO-DUAL-RECEIVER-MAPPING-LATENCY-GATE-022` — PASS
- **Final design:** `docs/superpowers/specs/2026-10-08-dual-receiver-system-mapped-trigger-design-final.md`
- **Implementation plan:** `docs/superpowers/plans/2026-10-08-dual-receiver-system-mapped-routing.md`
- **Latency addendum:** `docs/superpowers/plans/2026-10-08-dual-receiver-system-mapped-routing-latency-addendum.md`
- **Preserved implementation base:** `codex/dual-receiver-momentary-routing-v1` at `c90edbf73ad9b0642fa344734571c0e806c0eb73`
- **Preserved product HEAD:** `ef29186e25c64cd4d1d7209cb2a41f95c51d4a11`
- **Authorized v2 branch:** `codex/dual-receiver-system-mapped-routing-v2`
- **Authorized worktree:** `/private/tmp/remoteorbit-dual-receiver-system-mapped-routing-v2`
- **Merge:** FORBIDDEN

## Latency prerequisite — PASSED

Measured real process-level mapping latency:

```text
A->B: 50/50 success
median 5.428063 ms
p95    6.137273 ms
max    6.698084 ms

B->A: 50/50 success
median 5.326646 ms
p95    6.389208 ms
max    6.703750 ms
```

Prior natural first-UP -> second-DOWN minimum: `74.476 ms`.

Worst measured A->B process margin: `67.777916 ms`.

`MAPPING_LATENCY_GATE_PASS`

This authorizes construction. Production must additionally log total `FIRST_UP_TO_SECONDARY_READY_MS`; the second physical DOWN is still admitted only if `SECONDARY_READY` is already true.

## Authoritative architecture

### A / primary ready

```text
F5 mapping = A
filter target = A
```

Direct LONG uses the original hardware/system-mapped path:

```text
physical F5
-> mapped A edge captured
-> 350 ms classify A
-> activate remote audio
-> first PCM
-> release captured A DOWN
-> release/drain
-> captured A UP
```

### First quick release

```text
discard captured A pair
-> begin guarded A->B reconfiguration
-> hidutil --set F5->B
-> configure filter B
-> end suppression guard
-> SECONDARY_READY
```

### Second DOWN admission

Only `SECONDARY_READY` may admit the second physical DOWN.

If second DOWN arrives earlier:

```text
A exposed = 0
B exposed = 0
synthetic = 0
BLE activation for that attempt = 0
no buffering/replay after readiness
```

### Second LONG B

```text
mapped B edge captured
-> 350 ms classify B
-> remote audio
-> first PCM
-> release captured B DOWN
-> release/drain
-> captured B UP
-> only then restore B->A
```

Timeout or second quick release opens neither receiver and restores A.

## Mandatory invariants

```text
RAW_HID_OWNER = HIDMonitor only
MAPPED_EDGE_OWNER = VoiceKeyFilter / HardwareOptionGate only
MAPPING_AUTHORITY = RemoteVoiceKeyMapping only
NORMAL_DUAL_SYNTHETIC_TRIGGER = NO
VIRTUAL_HID_PROVIDER = NO
PERSISTENT_SESSION_RECEIVER_AUTHORITY = NO
GENERIC_BUTTON_GESTURE_TIMING_CHANGE = NO
BLE_CODEC_CHANGE = NO
TAIL_DRAIN_RETUNE = NO
```

Mapping failures are fail-closed. B->A restore failure blocks all later gestures until reconciliation.

Do not put synchronous `hidutil --get` in the double-tap critical path. Asynchronous readback remains diagnostic.

## Required production timing evidence

For every A->B / B->A runtime transition log monotonic:

```text
A_TO_B_APPLY_MS
B_TO_A_APPLY_MS
FIRST_UP_TO_SECONDARY_READY_MS
```

For second-DOWN admission also log whether readiness pre-existed the DOWN.

A stale completion/readback from an older mapping generation must not mutate current ownership.

## Construction procedure

Follow the implementation plan task-by-task with TDD, subject to this task and latency addendum.

## Current execution checkpoint

- Authoritative parent control HEAD: bf5579fc43f2efbe627dec03f4d0b52182a2848f.
- Implementation branch/worktree: codex/dual-receiver-system-mapped-routing-v2 at /private/tmp/remoteorbit-dual-receiver-system-mapped-routing-v2.
- Tasks 2–11 completed; validated product/candidate source HEAD: 50a20174632dc105fb670a9b83e3f6feaa8e9f9b.
- Task 12 passed: focused suites 201/201 across 12 suites; full Swift suite 384/384; self-tests 3/3; universal release package/signature; git diff --check; scope audit.
- Normal B path uses the existing hardware Option gate. Early second DOWN fails closed without buffering/replay; A restoration waits until B mapped-UP ownership is closed; mapping failures lock the runtime.
- Scope audit: no second raw HID owner/mapping authority, no normal dual synthetic trigger or virtual HID, no generic gesture timing, BLE codec, tail/drain, or Persistent Session authority/semantics change. Idle target is A; B is limited to its ready window/transaction.
- Installed candidate: /Applications/RemoteOrbit.app, source HEAD 50a20174632dc105fb670a9b83e3f6feaa8e9f9b, version/build 0.2.13 (42), Bundle ID com.lost0rz.RemoteOrbit, executable SHA-256 7bf64aaea9e988f4857d49509ac897e952bd6b67dd405585a486d6a1f1c4a219. Signature verified.
- RemoteOrbit was restarted as PID 93962; Core Audio driver PID 615 was left untouched.
- No remote gestures, BLE/audio test, Set B/C, or merge occurred. The canonical dirty HIDMonitor.swift and codex/v0211-nonseize-hid-audit remain untouched.
- Stop at READY_FOR_USER_SYSTEM_MAPPED_SET_A for user hardware acceptance.
### Gate 0 — authority and v2 baseline

1. `git fetch origin --prune`.
2. Read `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md`, final design, implementation plan, latency addendum, README and SETUP_NOTES.
3. Verify authoritative main and preserved base.
4. Create/reconcile only `codex/dual-receiver-system-mapped-routing-v2` from preserved branch `c90edbf...`.
5. Use only `/private/tmp/remoteorbit-dual-receiver-system-mapped-routing-v2`.
6. Sync only authoritative control/spec/plan/addendum files from current `origin/main`; do not merge main product history into v2.
7. Prove product baseline remains the accepted 019 product tree before new edits.
8. Run the accepted focused baseline suites.

### Existing local state protection

The reported local-only branch `codex/v0211-nonseize-hid-audit` is not authority for this task. Inspect only if needed for attribution; do not use, merge, delete or rewrite it.

The pre-existing dirty canonical `remote-orbit/Sources/RemoteOrbit/KeyMapping/HIDMonitor.swift` must remain untouched. No clean/stash/reset/restore/copy.

### Product implementation

Execute implementation-plan Tasks 2 through 12. Required outcomes include:

- dual mode keeps A mapping active rather than clearing mapping;
- first-short classifier event arms B;
- explicit mapping ownership state;
- direct A returns to existing hardware-gate first-PCM replay;
- A->B guarded mapping switch;
- second DOWN before B-ready fails closed;
- ready B uses existing hardware-gate path, never normal synthetic trigger;
- timeout/quick B/B completion restore A safely;
- disconnect/loss/stale completion/readback failure safety;
- Settings/legacy behavior retained;
- full focused/full tests, self-tests, release build and `git diff --check` pass.

## Scope audit before install

Must explicitly return NO for:

```text
SECOND_RAW_HID_OWNER_ADDED
SECOND_MAPPING_AUTHORITY_ADDED
NORMAL_DUAL_SYNTHETIC_TRIGGER_USED
VIRTUAL_HID_PROVIDER_ADDED
GENERIC_BUTTON_THRESHOLD_CHANGED
BLE_CODEC_CHANGED
TAIL_DRAIN_RETUNED
PERSISTENT_SESSION_AUTHORITY_CHANGED
CANONICAL_DIRTY_FILE_TOUCHED
```

## Candidate install boundary

Only after all automated validation passes, the executor may build/package/install the exact v2 candidate and restart only RemoteOrbit using the existing project procedure.

Do not change the receiver shortcuts, driver, CoreAudio, TCC or system remappers.

Record exact installed source HEAD, branch HEAD, executable SHA-256, version/build, Bundle ID and PID.

Then STOP at:

`READY_FOR_USER_SYSTEM_MAPPED_SET_A`

Do not perform remote hardware gestures. Do not continue to Set B/C. Do not merge.

## Required handoff

```text
TASK_ID: RO-DUAL-RECEIVER-SYSTEM-MAPPED-IMPLEMENTATION-023
CONTROL_HEAD: bf5579fc43f2efbe627dec03f4d0b52182a2848f
IMPLEMENTATION_BASE: c90edbf73ad9b0642fa344734571c0e806c0eb73; accepted product baseline ef29186e25c64cd4d1d7209cb2a41f95c51d4a11
IMPLEMENTATION_BRANCH: codex/dual-receiver-system-mapped-routing-v2
IMPLEMENTATION_WORKTREE: /private/tmp/remoteorbit-dual-receiver-system-mapped-routing-v2
FINAL_HEAD: this closeout control-sync commit; validated candidate source HEAD 50a20174632dc105fb670a9b83e3f6feaa8e9f9b
REMOTE_HEAD: matches FINAL_HEAD; verified after push
LOCAL_REMOTE_MATCH: YES

LATENCY_GATE_ACCEPTED: YES; Task 022 prerequisite accepted, not rerun
TASK_2_PRIMARY_MAPPING: YES; idle remains mapped to A
TASK_3_FIRST_SHORT_EVENT: YES; recognized first short release arms B transition
TASK_4_MAPPING_STATE: YES; explicit generation-bound mapping ownership state
TASK_5_DIRECT_A_HARDWARE_PATH: YES; existing mapped A hardware gate
TASK_6_A_TO_B_ARM: YES; guarded mapping switch and readiness transition
TASK_7_EARLY_SECOND_FAIL_CLOSED: YES; no exposure, synthetic edge, activation, buffer, or replay
TASK_8_B_HARDWARE_PATH: YES; existing mapped B hardware gate
TASK_9_RESTORE_A: YES; after B mapped-UP ownership closes; timeout and quick release covered
TASK_10_FAILURE_SAFETY: YES; removal/loss/stale completion/readback failures fail closed
TASK_11_SETTINGS_LEGACY: YES; existing settings and legacy behavior preserved
TASK_12_FULL_VALIDATION: PASS

FOCUSED_TESTS: PASS; 12 suites, 201/201
FULL_SWIFT_TEST: PASS; 384/384
SELF_TESTS: PASS; 3/3
RELEASE_BUILD: PASS; arm64+x86_64 package, signature verified
DIFF_CHECK: PASS
SCOPE_AUDIT: PASS

SECOND_RAW_HID_OWNER_ADDED: NO
SECOND_HID_OWNER_ADDED: NO
SECOND_MAPPING_AUTHORITY_ADDED: NO
NORMAL_DUAL_SYNTHETIC_TRIGGER_USED: NO
VIRTUAL_HID_PROVIDER_ADDED: NO
GENERIC_BUTTON_THRESHOLD_CHANGED: NO
GENERIC_GESTURE_TIMING_CHANGED: NO
BLE_CODEC_CHANGED: NO
TAIL_DRAIN_RETUNED: NO
TAIL_DRAIN_CHANGED: NO
PERSISTENT_SESSION_AUTHORITY_CHANGED: NO
PERSISTENT_SESSION_SEMANTICS_CHANGED: NO
IDLE_DUAL_MAPPING_TARGET: A
B_MAPPING_ONLY_DURING_B_WINDOW_OR_TRANSACTION: YES
SECOND_PRESS_BEFORE_B_READY_FAILS_CLOSED: YES

A_TO_B_TEST_LATENCY_MS: NOT REPEATED; Task 022 accepted prerequisite
B_TO_A_TEST_LATENCY_MS: NOT REPEATED; Task 022 accepted prerequisite
END_TO_END_READINESS_TESTS: automated transaction/state tests; no live latency benchmark

APP_PATH: /Applications/RemoteOrbit.app
INSTALLED_SOURCE_HEAD: 50a20174632dc105fb670a9b83e3f6feaa8e9f9b
EXECUTABLE_SHA256: 7bf64aaea9e988f4857d49509ac897e952bd6b67dd405585a486d6a1f1c4a219
APP_VERSION_BUILD: 0.2.13 (42)
BUNDLE_ID: com.lost0rz.RemoteOrbit
RUNNING_PID: 93962

CANONICAL_PREEXISTING_DIRT_PRESERVED: YES
UNAUTHORIZED_LOCAL_BRANCH_LEFT_UNTOUCHED: YES
MERGED: NO
FINAL_STATE: READY_FOR_USER_SYSTEM_MAPPED_SET_A
```
