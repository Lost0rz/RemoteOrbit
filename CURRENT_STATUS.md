# CURRENT_STATUS

Last updated: 2026-10-08
State: SET B INCIDENT ROOT CAUSE PROVEN / MIC DEBOUNCE CORRECTIVE AUTHORIZED
Repository: `Lost0rz/RemoteOrbit`

## Authority
- Audited incident control HEAD: `43bb1c15e1bb07ca2827a340ae7db43603fcfd86`.
- Failed candidate branch: `codex/dual-receiver-system-mapped-routing-v2` at `e1e6fe0bf76e245c4237978600b117b5b8e2a83e`.
- Installed failed candidate source: `50a20174632dc105fb670a9b83e3f6feaa8e9f9b`.
- Corrective task: `RO-DUAL-RECEIVER-MIC-DEBOUNCE-CORRECTIVE-024`.
- Planned corrective branch: `codex/dual-receiver-mic-debounce-corrective` from `e1e6fe0bf76e245c4237978600b117b5b8e2a83e`.
- Planned worktree: `/private/tmp/remoteorbit-dual-receiver-mic-debounce-corrective`.
- Merge remains forbidden.

## Accepted Set A
Set A remains accepted: 5/5 Direct LONG used system-mapped Left Option through HardwareOptionGate; first PCM preceded replay; B trigger and normal synthetic edge counts were zero; all samples completed release/drain and returned to primaryReady.

## Set B incident — proven internal root cause
First Set-B attempt evidence:

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

Source audit proves the microphone still uses the legacy HID edge debounce in dual mode:

```text
advanced = button != .microphone && profile.usesAdvancedGestures
shouldDebounce = !shouldRepeat && !advanced
```

Therefore a legitimate second microphone press inside the 300 ms dual-receiver window can be discarded by the legacy 180 ms single-shot debounce. This is the proven cause of RemoteOrbit failing to create the B hardware-gate/transaction path in the incident.

The user-visible fact that external B remained open is consistent with an unowned system-mapped Right Option edge passing while RemoteOrbit had no B gate, but the exact external receiver interpretation remains unproven and is not a separate fix target yet.

## Proven test gap
`DualReceiverVoiceTransactionTests` injects `harness.edge(...)` directly into `AppController.handleDualReceiverMicrophoneEdge(...)`. It bypasses `HIDMonitor` and `ButtonEdgeDebouncer`, so the existing transaction suite cannot detect this input-layer conflict.

## Corrective boundary
Authorize one minimal corrective only:

1. In active dual-receiver mode, microphone raw edges must not use the legacy `ButtonEdgeDebouncer` policy that can suppress the intentional second press.
2. Legacy microphone mode and all non-microphone buttons retain their existing debounce behavior.
3. Do not change `ButtonEdgeDebouncer.defaultInterval` globally.
4. Do not change generic `ButtonGestureRecognizer` thresholds or behavior.
5. Do not change dual-receiver 350 ms LONG / 300 ms double window.
6. Do not change mapping architecture, HardwareOptionGate, BLE, tail/drain, Persistent Session, driver, TCC, or synthetic-trigger policy.
7. Add a RED regression at the HID input-policy/debouncer boundary using the observed 109.810 ms second-press gap, plus legacy-regression coverage.
8. Existing controller-level dual transaction tests remain but are not sufficient alone.

After focused/full validation, build/install the exact corrective candidate and stop before user gestures at `READY_FOR_USER_SET_B_CORRECTIVE_RETRY`.
