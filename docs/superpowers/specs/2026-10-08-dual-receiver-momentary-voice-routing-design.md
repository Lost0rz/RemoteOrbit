# Dual-Receiver Momentary Voice Routing — Design Spec

Date: 2026-10-08
Status: FROZEN FOR USER REVIEW
Task: `RO-DUAL-RECEIVER-MOMENTARY-ROUTING-018`

## 1. Product contract

Dual-receiver mode uses one physical microphone button and two hold-capable gestures:

```text
Direct LONG                  -> Receiver A
Quick first tap + second LONG -> Receiver B
Quick single tap only         -> no action
```

Initial receiver triggers:

```text
Receiver A -> Left Option
Receiver B -> Right Option
```

Both receivers are independent momentary voice transactions. No external Persistent Session is retained between utterances.

Accepted first implementation timing:

```text
LONG_THRESHOLD_MS = 350
DOUBLE_WINDOW_MS   = 300
```

Hardware timing task 017 established clear natural separation for these gestures. These values are implementation defaults, not permanent immutable constants.

## 2. Architectural decision

Choose a microphone-specific dual-receiver classifier adjacent to `VoicePressCoordinator`, while preserving the existing BLE/audio lifetime owner.

Do **not** route the microphone through the generic `ButtonGestureRecognizer` action-injection path. The generic recognizer remains useful as design precedent, but generic action dispatch must not own BLE, first-PCM authorization, trigger DOWN/UP, or output drain.

The dual-receiver transaction path is:

```text
raw microphone HID edge
-> voice-specific gesture classifier
-> choose Receiver A or B
-> activate ATVV voice input
-> first decoded PCM
-> emit selected receiver trigger DOWN
-> stream while physical button remains held
-> physical release
-> existing tail / output drain
-> emit the same selected receiver trigger UP
-> transaction complete
```

The selected key is captured by the transaction. A later settings change cannot change the key used for that transaction's UP.

## 3. Pre-classification trigger ownership

### 3.1 Dual mode must not keep F5 mapped to a receiver key

The current device-scoped `hidutil` mapping converts the remote microphone F5 usage to one configured modifier before receiver selection is known. That model is incompatible with double-hold because B's first short tap must expose neither A nor B.

Therefore, while dual-receiver mode is active:

```text
RemoteVoiceKeyMapping = disabled / empty mapping
```

No pre-classification F5 -> Left Option or F5 -> Right Option mapping is allowed.

### 3.2 Native F5 is parked by existing EventSuppressor ownership

`HIDMonitor` already owns an early `EventSuppressor` at a head-insert `cghidEventTap`. On each accepted raw HID edge it calls `eventSuppressor.updateHeld(...)` before delivering the semantic edge upward. The microphone native event is F5/keyCode 96.

In dual mode this existing suppression mechanism becomes the raw-F5 parking layer. Add explicit microphone F5 regression tests; do not invent a second suppressor.

Fail closed: if `HIDMonitor`/`EventSuppressor` is unavailable, dual mode must not silently fall back to a raw OS F5 path or guess a receiver. Legacy single-receiver mode may retain its existing fallback behavior.

## 4. Gesture classifier

Introduce a small pure/testable voice-specific classifier, e.g. `DualReceiverVoiceGestureRecognizer`.

Conceptual states:

```text
idle
firstPressPending
awaitingSecondPress
secondPressPending
activeDirectHold(A)
activeDoubleHold(B)
```

Rules:

1. First DOWN starts transport-only prewarm and the 350 ms long timer.
2. If first press stays down for 350 ms, classify A and activate the voice transaction.
3. If first press releases before 350 ms, emit no receiver trigger and wait up to 300 ms for a second DOWN.
4. Preserve transport prewarm during this 300 ms wait to avoid stop/start latency for B.
5. If no second DOWN arrives in 300 ms, resolve to no action and cancel the transport-only preparation.
6. If second DOWN arrives in the window, start the second 350 ms long timer.
7. If second press stays down for 350 ms, classify B and activate the voice transaction.
8. If second press releases before 350 ms, resolve to no action and cancel preparation.
9. Disconnect, invalidation, or explicit stop cancels pending timers and preparation without emitting A/B trigger edges.

Use HID monotonic timestamps as the physical timing authority; do not infer gesture duration from delayed UI callbacks.

## 5. BLE/audio lifecycle

Preserve the existing proven transport split:

- `prepareVoiceTransport()` = transport-only; must not request `micOpen`.
- `activateVoiceInput()` = only after A/B hold classification; may request `micOpen`.
- first decoded PCM remains the trigger-DOWN authorization boundary.
- physical release retains existing post-release/tail/output-drain behavior.

No new audio codec, gain, driver, BLE protocol, ATVV timing, or tail-drain redesign is authorized by this feature.

## 6. Per-transaction trigger emission

Extend `VoiceOptionTrigger` minimally so a transaction can explicitly specify its selected `VoiceTriggerKey` on DOWN.

Preferred API shape:

```swift
sendDown(sessionID:key:purpose:)
```

Keep the existing `sendDown(sessionID:purpose:)` overload for legacy callers and delegate it to the configured legacy momentary key.

`VoiceOptionTrigger` already stores `activeTriggerKey`; UP must continue to use that captured key. This is the single owner for synthetic A/B trigger balance in dual mode.

Dual mode uses classified synthetic modifier edges after first PCM. It does not dynamically rewrite `hidutil` while a physical press is in progress.

## 7. Settings and activation

Preserve the existing direct-long trigger as Receiver A.

Add a secondary/double-hold receiver trigger setting, conceptually:

```text
Double-hold trigger: Off | Left Option | Right Option | Left Control | Right Control | Left Command | Right Command
```

Recommended storage: a new optional secondary momentary trigger preference. Do not repurpose the existing Persistent Session trigger preference.

Dual mode is active only when:

```text
microphone SHORT action == Disabled
AND
secondary/double-hold trigger is enabled
AND
A trigger != B trigger
```

When the secondary trigger is Off, existing single-receiver behavior remains unchanged.

Settings changes to A/B keys or dual-mode enablement are rejected while any voice gesture, deferred second tap, active trigger, release/tail drain, or runtime reconfiguration owns the voice path.

UI should explain:

```text
Direct hold -> A
Quick tap then hold second -> B
Quick single tap -> no action
```

## 8. Legacy compatibility

The independent Disabled-SHORT classifier corrective remains required. The candidate branch `codex/disabled-short-classifier-regression-fix` is two commits ahead of its old base but 36 commits behind current `main` because control-plane documentation continued on `main`.

Do not merge/cherry-pick that branch wholesale.

Construction must branch from latest authoritative `origin/main`, then transplant only the exact final candidate versions of:

```text
remote-orbit/Sources/RemoteOrbit/main.swift
remote-orbit/Tests/RemoteOrbitTests/DisabledShortClassifierTests.swift
```

from candidate HEAD `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`, and verify that this transplant represents only the accepted classifier corrective before feature work begins.

Legacy mode remains the compatibility surface when the secondary trigger is disabled. Persistent functionality may remain available as a separate legacy/single-receiver behavior, but it is not authority for dual-receiver transactions.

## 9. Rejected approaches

### Dynamic hidutil remap after gesture classification

Rejected for v1. Changing the system mapping after the physical F5 is already held does not provide a clean or reliable receiver DOWN boundary and adds process/remap latency.

### Keep F5 mapped to A and suppress A only when B is recognized

Rejected. B's first short tap must expose zero A edges. This approach recreates the pre-classification leakage class that caused prior ambiguity.

### Persistent A + temporary handoff to B

Rejected as the dual-receiver ownership model. RemoteOrbit cannot authoritatively observe external IME Session state, so this keeps unnecessary cross-receiver state drift and ASR-composition risk.

### Seize device / virtual HID / DriverKit

Deferred. This is materially heavier. Revisit only if classified synthetic modifier triggers fail real-receiver hardware acceptance.

## 10. Failure handling

- Pending first tap timeout -> no action, cancel prewarm.
- Second quick tap -> no action, cancel prewarm.
- No first PCM -> no receiver trigger DOWN.
- BLE/ATVV loss before trigger DOWN -> cancel transaction without receiver trigger.
- BLE/ATVV loss after trigger DOWN -> use existing drain/cleanup path and guarantee exactly one matching UP.
- HID disconnect while pending -> cancel timers/prewarm, no trigger.
- HID disconnect while active -> preserve existing device-removal cleanup semantics and guarantee trigger balance.
- Rapid repress during tail ownership must not transfer A/B ownership across transactions; retain/defer according to existing voice-route ownership rules.

## 11. Diagnostics

Reuse existing `VoiceDiagnosticLogger`; do not create a parallel diagnostic authority.

Add only bounded semantic events necessary for acceptance, for example:

```text
DUAL_GESTURE_BEGIN
DUAL_GESTURE_CLASSIFIED receiver=A|B
DUAL_GESTURE_NO_ACTION
VOICE_TRANSACTION_BEGIN receiver trigger_key
VOICE_TRANSACTION_COMPLETE receiver trigger_key
```

Existing HID, AUDIO_START/AUDIO_FIRST/AUDIO_STOP, synthetic trigger, route and drain events remain authoritative for their boundaries.

## 12. Test contract

TDD is mandatory. At minimum cover:

### Pure gesture classification

- direct 350 ms+ hold -> A exactly once;
- first quick tap + second 350 ms+ hold inside 300 ms -> B exactly once;
- quick single tap + 300 ms timeout -> no action;
- two quick taps -> no action;
- first/second release just below threshold -> no receiver;
- second DOWN just inside/outside double window;
- stale timer cannot classify a newer gesture;
- disconnect/cancel clears pending state.

### Raw F5 parking

- remote microphone F5 down is suppressed when HID owns the microphone button;
- matching F5 up is suppressed only when its down was suppressed;
- unrelated physical keyboard events remain unaffected.

### Trigger ownership

- explicit Right Option DOWN stores Right Option as active transaction key;
- UP balances Right Option even if global A setting changes later;
- A transaction emits no B edge;
- B transaction emits no A edge;
- first tap of B emits neither receiver key.

### Integration

- first PCM gates selected trigger DOWN;
- no PCM -> zero receiver edges;
- release/output drain -> exactly one matching UP;
- rapid repress cannot inherit previous receiver;
- transport loss cannot strand either modifier;
- secondary Off -> legacy behavior unchanged;
- classifier corrective (`bypassesShortClassification = false`) remains protected.

Run focused tests first, then full `swift test`, self-tests, release build and `git diff --check`.

## 13. Hardware construction gates

Do not wait until all polish is complete to validate the new trigger mechanism.

After the minimal core path and minimal settings/configuration needed to select A=Left Option and B=Right Option exist, build a candidate and stop for an early hardware acceptance:

```text
5 x direct LONG:
  only A opens; B never opens

5 x double-hold:
  first tap opens neither
  second held press opens only B

5 x quick single tap:
  neither opens

release:
  selected receiver closes cleanly
  next gesture can start normally
```

Logs must show no A/B trigger before gesture classification and first PCM.

If either real receiver does not reliably accept the classified synthetic modifier path, STOP. Do not restore pre-classification `hidutil` mapping as a workaround. Return to architecture and evaluate a stronger post-classification injection mechanism (virtual HID / controlled exclusive ownership) separately.

After this early gate passes, finish Settings polish, regression coverage, full suite, release build, independent Web diff audit, then a larger hardware acceptance before merge.

## 14. Non-goals

This task does not redesign:

- BLE codec or gain;
- the ~60 s remote firmware limit;
- post-release audio tail tuning;
- Persistent Session transaction rotation;
- external IME state observation;
- diagnostic architecture;
- audio driver / TCC / packaging;
- generic non-microphone button gestures.
