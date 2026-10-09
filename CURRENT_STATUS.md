# CURRENT_STATUS

Last updated: 2026-10-09
State: TASK 028 WEB AUDIT PASS / USER RECEIVER-B HARDWARE GATE AUTHORIZED / MERGE FORBIDDEN
Repository: `Lost0rz/RemoteOrbit`

## Authority
- Audited control parent: `6e988ae98792391bce069ced978131472bbb96b3`.
- Corrective branch: `codex/dual-receiver-b-up-replay-ack-fix`.
- Product implementation and installed source: `f938b919e288a481f5eacaf9aad9c254dcf0cffe`.
- Final corrective branch HEAD: `85bb2e12cad41198e5a27d9e610cbdb30b01d357`; independent ref check matched this HEAD.
- `f938b919... -> 85bb2e12...` changes only `CURRENT_STATUS.md` and `CURRENT_TASK.md`; no later product/test mutation.
- Installed candidate evidence: `/Applications/RemoteOrbit.app`, version `0.2.13` build `42`, Bundle ID `com.lost0rz.RemoteOrbit`, executable SHA-256 `104d4bf0cad8f7316ceea8c8e21568737d3ba3eea0f3c44207107a1159eb850e`, RemoteOrbit PID `39949`; Core Audio and driver were not restarted by the executor.
- Merge remains forbidden.

## Accepted prior evidence
- Set A passed 5/5 on the system-mapped Left Option hardware path.
- Corrective 024 fixed the dual-mode microphone legacy 180 ms debounce conflict.
- Task 025/027 proved the observed stuck-B failure was caused by the reposted copied Right Option UP being suppressed by B->A reconfiguration before it could pass downstream.
- Task 026 proved a direct physical Right Option hold/release has the correct Receiver-B momentary semantics.

## Independent Web audit of Task 028
PASS for the first user hardware gate.

Source-backed findings:
- The product checkpoint is scoped to `main.swift`, `VoiceKeyFilterTests.swift`, `DualReceiverVoiceTransactionTests.swift`, plus control files; no HIDMonitor, BLE/audio, mapping-authority, tail timing, generic gesture, flags, or event-tap relocation changes were introduced.
- `VoiceKeyFilter` now registers pending replay-UP ownership before reposting copied hardware-UP events.
- Replay identity is matched using the current gesture-owned pending record plus keyCode, CGEvent type, and original Quartz timestamp. Wrong key/type/timestamp and duplicate events cannot consume the pending component.
- Pending replay-UP is included in `hasActiveHardwareTriggerOwnership`, so normal B->A reconfiguration cannot start while the expected replay is outstanding.
- The event-tap callback checks the expected replay acknowledgement before reconfiguration suppression; a matching replay is returned on the pass path unchanged.
- Only after every expected replay-UP component has passed does the acknowledgement callback enqueue `handleDualReceiverHardwareOutputDrainClosed`, after which primary mapping restoration is allowed.
- Stop, supersede, and HID-removal paths invalidate pending replay ownership.
- The no-copied-UP emergency fallback remains viable: `releaseHeldHardwareOption` emits the existing emergency balancing UP, no pending replay owner is created, and the existing output-drain callback can continue to the restore path.
- Normal dual Receiver-B release still uses the copied hardware event; there is no normal synthetic B-UP, no flag rewrite, and no `.cghidEventTap` relocation.

Automated verification evidence from the local executor is accepted as local evidence, not independently rerun by Web: VoiceKeyFilter 16/16, DualReceiverVoiceTransaction 20/20, VoiceTriggerRuntime 53/53, VoicePressCoordinator 38/38, full Swift 394/394, self-tests 3/3, release/package/signature/diff/scope PASS.

TDD note: the initial RED on the implementation base was a compile-time failure because the new pending-owner/ack test seams did not yet exist, rather than a behavioral assertion reaching the old race. That is weaker than the ideal RED contract, but it is not a hardware-gate blocker here because Task 027 already captured the old race in a real runtime trace, and the GREEN tests plus independent source audit directly cover the corrective ordering invariant.

## Current authorization
User-only first Receiver-B hardware gate is authorized now.

Perform exactly one natural gesture:

```text
quick first tap -> immediate second LONG -> speak -> physical release
```

Expected:
- first quick tap opens neither receiver;
- second LONG opens Receiver B only;
- Receiver A does not open;
- physical release closes Receiver B immediately/normally;
- no duplicate text and no stuck modifier/session state.

If any item fails: STOP, do not retry to overwrite the sample, do not Set C, do not merge.

If the one-shot hardware gate passes: perform read-only evidence capture before expanding to 5/5 stability testing. Expected internal evidence includes `REPLAY_UP_PENDING`, `REPLAY_UP_POSTED`, `REPLAY_UP_PASS_ACK`, no matching replay-UP `reconfiguration_suppress`, then B->A restore and final `primaryReady`/idle.
