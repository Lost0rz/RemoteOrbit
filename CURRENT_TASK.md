# RemoteOrbit Current Task

## Current task — RECEIVER-B REPLAY-UP ACKNOWLEDGED RESTORE CORRECTIVE

- **Status:** IMPLEMENTATION COMPLETE / VALIDATION PASSED / CANDIDATE INSTALLED / WAITING_FOR_INDEPENDENT_WEB_AUDIT / MERGE FORBIDDEN
- **Task ID:** `RO-DUAL-RECEIVER-B-UP-REPLAY-ACK-CORRECTIVE-028`
- **Previous task:** `RO-DUAL-RECEIVER-RIGHT-OPTION-EVENT-SHAPE-AUDIT-027` — CLOSED / ROOT CAUSE PROVEN
- **Implementation base:** `458e28d91b5ff748613bb88f5b89212d660279c7`
- **Installed source before corrective:** `406f1242e7c3bc17b1fa0da43b069a0b2c6874c8`
- **Authorized branch:** `codex/dual-receiver-b-up-replay-ack-fix`
- **Authorized worktree:** `/private/tmp/remoteorbit-dual-receiver-b-up-replay-ack-fix`
- **Merge:** FORBIDDEN

## Proven defect
Task 027 evidence plus source establishes this exact failure:

```text
captured B UP
-> copied B UP posted at .cghidEventTap
-> controller starts B->A restore before reposted event is observed passing the filter
-> beginVoiceTriggerReconfiguration suppresses Right Option
-> reposted B UP returns with its original Quartz timestamp
-> event tap records action=reconfiguration_suppress and returns nil
-> external Receiver B never receives release
```

The replayed DOWN also gains extra raw flag bit `0x20000000` yet successfully opens Receiver B. Do not treat that flag difference as the current root cause and do not rewrite flags in Task 028.

## Required design contract
The correction must be deterministic and event-driven.

1. Keep using the copied system-mapped hardware UP event. Do not synthesize a replacement normal-path Right Option UP.
2. Do not add `Key.syntheticMarker` to normal hardware replay.
3. Do not change `.cghidEventTap` posting location in this task.
4. Introduce the minimum gesture-scoped ownership needed to distinguish an expected reposted hardware-UP component from unrelated events. Use stable fields already present on the copied event, preferably gesture ownership + keyCode + event type + original Quartz timestamp. Do not depend on mutable wall-clock timing.
5. While the expected copied B-UP is posted but has not yet re-entered the filter pass path, B release ownership remains open for reconfiguration purposes. B->A restore must not start.
6. When the expected reposted B-UP re-enters the filter, it must be allowed to pass downstream unmodified. Only after that pass decision is committed may the controller enqueue B->A restore.
7. Stale, unrelated, duplicated, wrong-key, wrong-type, or wrong-timestamp events must not acknowledge the pending replay.
8. The acknowledgement/restore transition must be exactly-once and generation/session scoped.
9. Device removal/stop/supersede must clear or invalidate pending replay ownership safely; no stranded permanent lock.
10. Direct A behavior, B DOWN replay, first-PCM sequencing, output drain, mapping latency logic, settings, generic gestures, BLE codec/audio, tail drain, and persistent-session behavior remain unchanged.

## TDD gate — mandatory RED first
Before production edits, add the smallest focused failing test(s) proving the current race. The RED evidence must show that the current implementation can begin B->A reconfiguration before the copied B-UP has been observed on a downstream/pass path, allowing the expected replay to hit `reconfiguration_suppress`.

The test must fail for the intended reason on the exact implementation base. Do not write production code before capturing RED.

Minimum required focused behavior after GREEN:

```text
REPLAY_UP_PENDING_BLOCKS_PRIMARY_RESTORE = PASS
EXPECTED_REPLAY_UP_REENTERS_AND_PASSES = PASS
PRIMARY_RESTORE_BEGINS_ONLY_AFTER_REPLAY_UP_PASS = PASS
EXPECTED_REPLAY_UP_ACK_EXACTLY_ONCE = PASS
STALE_OR_UNRELATED_EVENT_CANNOT_ACK = PASS
RECONFIGURATION_CANNOT_SUPPRESS_EXPECTED_REPLAY_UP = PASS
NORMAL_DUAL_SYNTHETIC_TRIGGER_USED = NO
REPLAY_EVENT_FLAGS_REWRITTEN_BY_PRODUCT = NO
A_PATH_UNCHANGED = PASS
```

Prefer extending existing `VoiceKeyFilterTests`, `DualReceiverVoiceTransactionTests`, and/or `VoiceTriggerRuntimeTests`; do not create a broad new subsystem.

## Implementation constraints
- No arbitrary `asyncAfter`/sleep to make ordering appear stable.
- A main-queue hop may be used only as an ordering handoff after the expected replayed event has been positively acknowledged at the filter pass seam.
- Keep `HIDMonitor` as the sole raw HID owner.
- Keep `RemoteVoiceKeyMapping` as the sole device mapping authority.
- Keep `VoiceKeyFilter` / `HardwareOptionGate` as the mapped-edge authority.
- Do not add a second event tap or observer authority.
- Do not normalize `0x20000000` or any other replay flags in this task.
- Do not use source PID/state/keyboard-type instrumentation unless the corrective fails the hardware gate.

## Validation before install
Run at minimum:

```text
focused RED test(s) before product change
focused GREEN tests after product change
all VoiceKeyFilterTests
all DualReceiverVoiceTransactionTests
all VoiceTriggerRuntimeTests
all VoicePressCoordinatorTests
full swift test suite
self-tests
release build/package
signature verification
git diff --check
scope audit
```

Return exact test counts and failures if any.

## Candidate install authorization
If and only if every required automated gate passes and the branch/worktree is clean and pushed:
- build/install the corrective candidate to `/Applications/RemoteOrbit.app`;
- restart RemoteOrbit only;
- do not restart or modify the Core Audio driver;
- record source HEAD, executable SHA-256, app version/build, Bundle ID and running PID.

Do not perform any remote gesture as the executor.

## User hardware gate after Web audit
After local implementation evidence is returned, Web will independently audit the branch before authorizing the user hardware gate.

Expected first hardware gate:
- Receiver B only;
- quick first tap + second LONG;
- verify B opens during hold and closes on physical release;
- no Set C;
- no merge.

## Task 028 implementation result
- Product commit: `f938b919e288a481f5eacaf9aad9c254dcf0cffe` on `codex/dual-receiver-b-up-replay-ack-fix`.
- RED was captured before production edits. Focused tests failed to compile because the exact pending replay ownership/pass-ack and held-UP test seams required by the new assertions were absent on the implementation base.
- GREEN focused suites: VoiceKeyFilter 16/16; DualReceiverVoiceTransaction 20/20; VoiceTriggerRuntime 53/53; VoicePressCoordinator 38/38.
- Full Swift suite: 394/394. Self-tests: 3/3. Release build/package, signature verification, diff check, and scope audit: PASS.
- Candidate installed at `/Applications/RemoteOrbit.app`: source `f938b919e288a481f5eacaf9aad9c254dcf0cffe`, executable SHA-256 `104d4bf0cad8f7316ceea8c8e21568737d3ba3eea0f3c44207107a1159eb850e`, version `0.2.13` build `42`, Bundle ID `com.lost0rz.RemoteOrbit`, running PID `39949`.
- Core Audio PID `590` and RemoteOrbitAudio driver PID `615` stayed unchanged. No remote gestures or physical Option test; no merge.
- Stop at `READY_FOR_INDEPENDENT_WEB_AUDIT`. The next hardware action remains user-only after independent audit authorization.

## Strict prohibitions
```text
NO merge
NO Set C
NO executor remote gestures
NO fixed timing workaround
NO flag rewriting
NO event-tap relocation
NO synthetic normal B UP
NO BLE/audio/tail retune
NO generic gesture changes
NO driver/CoreAudio/TCC changes
NO broad diagnostics expansion
```

## Stop
Stop at `READY_FOR_INDEPENDENT_WEB_AUDIT` after a clean pushed implementation and candidate install. If RED cannot reproduce the race, if exact replay acknowledgement cannot be made deterministic, or if any unrelated regression appears, STOP without hardware testing or merge.
