# CURRENT_STATUS

Last updated: 2026-10-08
State: CORRECTIVE CANDIDATE INSTALLED / WAITING FOR USER SET B RETRY
Repository: `Lost0rz/RemoteOrbit`

## Authority
- Current control HEAD: `3fd2271e7dbb80c8407f7a963b3615a8116c8382`.
- Failed candidate branch: `codex/dual-receiver-system-mapped-routing-v2` at `e1e6fe0bf76e245c4237978600b117b5b8e2a83e`.
- Installed failed candidate source: `50a20174632dc105fb670a9b83e3f6feaa8e9f9b`.
- Corrective task: `RO-DUAL-RECEIVER-MIC-DEBOUNCE-CORRECTIVE-024`.
- Corrective branch: `codex/dual-receiver-mic-debounce-corrective`; product commit `406f1242e7c3bc17b1fa0da43b069a0b2c6874c8` is pushed.
- Corrective worktree: `/private/tmp/remoteorbit-dual-receiver-mic-debounce-corrective`.
- Merge remains forbidden.

## Corrective candidate
- `HIDButtonDownPolicy` bypasses `ButtonEdgeDebouncer` only for the microphone while `DualReceiverVoiceMode` is active.
- Legacy microphone, single-shot, repeatable, and advanced generic-button policy remains unchanged; the global debounce interval remains 180 ms.
- Validation: focused HID policy tests 3/3; dual-receiver transaction tests 19/19; full Swift tests 387/387; self-tests 3/3; release build and `git diff --check` passed.
- Installed app: `/Applications/RemoteOrbit.app`, source `406f1242e7c3bc17b1fa0da43b069a0b2c6874c8`, version `0.2.13 (42)`, executable SHA-256 `cf5192dcf1a4fea5be9fc46f2923c72e01baa7eee7691cafbe77ab16dfda4b00`, running PID `5331`.
- No remote gestures were performed. Next action: user performs the Set B corrective retry; do not execute Set B or Set C as the agent.

## Accepted Set A
Set A remains accepted: 5/5 Direct LONG used system-mapped Left Option through HardwareOptionGate; first PCM preceded replay; B trigger and normal synthetic edge counts were zero; all samples completed release/drain and returned to primaryReady.

## Set B incident — proven internal root cause
Failed Set-B sample evidence:

```text
first quick UP -> SECONDARY_READY = 22.737 ms
second physical DOWN gap = 109.810 ms
ButtonEdgeDebouncer.defaultInterval = 180 ms
second raw F5 DOWN = HID_MIC_EDGE_SUPPRESSED(reason=debounce)
mapped Right Option DOWN = pass, gate_state=none
B hardware gate begin = absent
B classification = absent
physical UP edge = also debounce-suppressed
B->A restore later succeeded after second-press-window-expired
```

At the failed candidate source, the microphone still used the legacy HID edge debounce in dual mode:

```text
advanced = button != .microphone && profile.usesAdvancedGestures
shouldDebounce = !shouldRepeat && !advanced
```

Therefore a legitimate second microphone press inside the 300 ms dual-receiver window was discarded by the legacy 180 ms single-shot debounce. This is the proven cause of RemoteOrbit failing to create the B hardware-gate/transaction path in the incident.

The user-visible fact that external B remained open is consistent with an unowned system-mapped Right Option edge passing while RemoteOrbit had no B gate, but the exact external receiver interpretation remains unproven and is not a separate fix target yet.

## Proven test gap
`DualReceiverVoiceTransactionTests` injects `harness.edge(...)` directly into `AppController.handleDualReceiverMicrophoneEdge(...)`. It bypasses `HIDMonitor` and `ButtonEdgeDebouncer`, so the existing transaction suite cannot detect this input-layer conflict.

## Corrective boundary
Completed one minimal corrective:

1. In active dual-receiver mode, microphone raw edges must not use the legacy `ButtonEdgeDebouncer` policy that can suppress the intentional second press.
2. Legacy microphone mode and all non-microphone buttons retain their existing debounce behavior.
3. Do not change `ButtonEdgeDebouncer.defaultInterval` globally.
4. Do not change generic `ButtonGestureRecognizer` thresholds or behavior.
5. Do not change dual-receiver 350 ms LONG / 300 ms double window.
6. Do not change mapping architecture, HardwareOptionGate, BLE, tail/drain, Persistent Session, driver, TCC, or synthetic-trigger policy.
7. Added a RED regression at the HID input-policy/debouncer boundary using the observed 109.810 ms second-press gap, plus legacy-regression coverage.
8. Existing controller-level dual transaction tests pass but are not sufficient alone to cover this boundary.

The exact corrective candidate is installed and RemoteOrbit is running. Stop before user gestures at `READY_FOR_USER_SET_B_CORRECTIVE_RETRY`.
