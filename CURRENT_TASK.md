# RemoteOrbit Current Task

## Current task — SYSTEM-MAPPED DUAL-RECEIVER V2 IMPLEMENTATION

- **Status:** ACTIVE / PRODUCT CONSTRUCTION AUTHORIZED THROUGH CANDIDATE INSTALL AND SET-A HANDOFF
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

- Authoritative parent control HEAD: `bf5579fc43f2efbe627dec03f4d0b52182a2848f`.
- Implementation branch/worktree: `codex/dual-receiver-system-mapped-routing-v2` at `/private/tmp/remoteorbit-dual-receiver-system-mapped-routing-v2`.
- Tasks 2–11 are implemented and tested; product checkpoint `fa6e08e96bcc16ab5079415973619b91810c8167` and control-sync branch HEAD `f4b7fe9338088b96f38bec04928834e6efe54ca2` are pushed and match the remote branch. Task 11 required no additional source/test files.
- Task 8 TDD evidence: the pre-change integration test observed no second hardware-gate begin and synthetic B output at first PCM; after implementation `DualReceiverVoiceTransactionTests` passed 13/13, `VoicePressCoordinatorTests` 38/38, `VoiceTriggerRuntimeTests` 48/48; `git diff --check` passed.
- A ready B DOWN now arms the same hardware gate as A; 350 ms classification enters the hardware hold and first PCM releases through the gate. The normal B path emits no synthetic trigger edge.
- Task 9 verifies timeout and B quick-release restoration, rejects new DOWN while B owns the mapping, and restores A only after output drain closes the held mapped-UP owner. Focused VoiceTriggerRuntimeTests and DualReceiverVoiceTransactionTests passed 64/64; `git diff --check` passed; product checkpoint `f1ce1c0bdeddaf516923ba80153482786183fad2` is pushed.
- Task 10 adds fail-closed HID-removal invalidation, serializes device mapping operations, waits for physical release before restoring A after momentary BLE loss, blocks setting changes throughout mapping ownership, and ignores stale A-restore completions/readbacks. Focused VoiceTriggerRuntimeTests and DualReceiverVoiceTransactionTests passed 72/72; `git diff --check` passed; product checkpoint `fa6e08e96bcc16ab5079415973619b91810c8167` is pushed.
- Task 11 confirmed existing A/B settings require no new UI or provider controls. `DualReceiverVoiceSettingsTests` passed 4/4 and `VoicePersistentSessionTests` passed 16/16. Existing/new assertions cover secondary Off, equal A/B, non-disabled SHORT, settings exclusion while B is armed/active/restoring, and Persistent Session trigger independence. No Task 11-only commit was needed.
- Next: Task 12, full focused suites, full test suite, self-tests, release/package build, scope audit, then exact candidate install and RemoteOrbit-only restart.
- No candidate build/install or task-scoped app restart has occurred. No remote gesture, BLE or audio test has occurred.
- The canonical dirty `HIDMonitor.swift` and `codex/v0211-nonseize-hid-audit` remain untouched.

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
CONTROL_HEAD:
IMPLEMENTATION_BASE:
IMPLEMENTATION_BRANCH:
IMPLEMENTATION_WORKTREE:
FINAL_HEAD:
REMOTE_HEAD:
LOCAL_REMOTE_MATCH:

LATENCY_GATE_ACCEPTED: YES
TASK_2_PRIMARY_MAPPING:
TASK_3_FIRST_SHORT_EVENT:
TASK_4_MAPPING_STATE:
TASK_5_DIRECT_A_HARDWARE_PATH:
TASK_6_A_TO_B_ARM:
TASK_7_EARLY_SECOND_FAIL_CLOSED:
TASK_8_B_HARDWARE_PATH:
TASK_9_RESTORE_A:
TASK_10_FAILURE_SAFETY:
TASK_11_SETTINGS_LEGACY:
TASK_12_FULL_VALIDATION:

FOCUSED_TESTS:
FULL_SWIFT_TEST:
SELF_TESTS:
RELEASE_BUILD:
DIFF_CHECK:
SCOPE_AUDIT:

A_TO_B_TEST_LATENCY_MS:
B_TO_A_TEST_LATENCY_MS:
END_TO_END_READINESS_TESTS:

APP_PATH:
INSTALLED_SOURCE_HEAD:
EXECUTABLE_SHA256:
APP_VERSION_BUILD:
BUNDLE_ID:
RUNNING_PID:

CANONICAL_PREEXISTING_DIRT_PRESERVED:
UNAUTHORIZED_LOCAL_BRANCH_LEFT_UNTOUCHED:
MERGED: NO
FINAL_STATE: READY_FOR_USER_SYSTEM_MAPPED_SET_A
```
