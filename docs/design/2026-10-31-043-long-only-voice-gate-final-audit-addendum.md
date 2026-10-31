# Task 043 — LONG-only Voice Gate Final Audit Addendum

Date: 2026-10-31
Scope: final pre-construction design hardening for the LONG-only admission corrective.

This addendum is more specific than the prior LONG-only design/audit where they differ. It does not authorize expansion into readiness, BLEBridge, AudioPipe, ATVV, driver, or generic non-microphone HID behavior.

## 1. SHORT uses bounded discard ownership, not immediate gate cancellation

A raw HID microphone UP before 300 ms classifies the gesture as SHORT/no-op. However the hidutil-translated Option components may arrive after raw HID UP. Therefore SHORT must not simply close the trigger gate and forget ownership.

Required behavior:

- cancel the private candidate timer and candidate promotion authority;
- transfer the gesture into the existing bounded short-discard/suppression ownership semantics;
- consume any late mapped Option DOWN/UP/flagsChanged components belonging to that physical gesture;
- retire the discard owner only after its existing bounded release/quiet-window conditions are satisfied;
- emit no synthetic tap and no Persistent action;
- a newer gesture must not inherit or be contaminated by the old discard owner.

Reuse the existing option-gate discard/tombstone machinery. Do not call the Persistent short-tap emission path merely to obtain suppression.

## 2. LONG confirmation and mapped-trigger arrival are independent facts

Task 042 runtime evidence proved that raw HID DOWN can precede the hidutil-translated Option DOWN by enough time that resolving the gate too early produces `noOptionEdge` and later trigger leakage.

Therefore a LONG candidate tracks independently:

- `longConfirmed`;
- physical `stillHeld`;
- previous-session/admission readiness;
- mapped trigger capture readiness when hardware mapping is in use.

At 300 ms, LONG confirmation may commit the existing direct voice lifecycle when `stillHeld && admissionReady`, but the hardware trigger gate must not be resolved as `noOptionEdge` merely because mapped DOWN has not arrived yet.

If LONG is confirmed before mapped DOWN arrives:

- preserve the gesture-scoped hardware capture owner;
- enter the current direct `.opening`/voice activation path without restoring first-PCM gating;
- release/replay the mapped trigger exactly once when that gesture's mapped DOWN is actually captured;
- if physical UP/cancellation invalidates the gesture before mapped DOWN arrives, later mapped components must be discarded and must not open the IME.

Synthetic fallback is used only when hardware mapping is actually unavailable according to the existing runtime authority, not simply because mapped DOWN is late.

## 3. Trigger capture ownership is established as early as the raw microphone DOWN path safely permits

The HID monitor intentionally processes reports synchronously on the main RunLoop to establish event suppression before macOS emits translated CGEvents. Preserve that ordering advantage.

For a normal idle microphone DOWN, establish the gesture-scoped mapped-trigger owner before slow/nonessential work such as focus preparation or formal session instrumentation.

For a rapid re-press while the previous gesture still owns terminal hardware Option-UP/output retirement, do not overwrite the old owner with a normal gate. Reuse the existing pending-repress hardware ownership mechanism and consume its structured begin result. A failed pending begin must not be ignored.

## 4. Candidate phase must not start focus preparation or formal voice-session observability

The 0-300 ms private candidate is not a user-visible voice session.

Before promotion do not start:

- FloatTabs/Codex focus transaction or focus-safety timeout;
- `VoiceTimingLogger.begin()` or equivalent formal voice-session timeline;
- receiver readiness;
- voice HUD;
- `activateVoiceInput()`;
- synthetic trigger delivery.

The candidate may snapshot the target application/profile/trigger identity at DOWN so the same identity remains authoritative if the frontmost application or settings change during the hold.

The HID layer may create the existing physical-attempt diagnostic identity on raw microphone DOWN. SHORT cancellation must explicitly end/cancel that physical attempt so no stale attempt/watchdog identity survives into the next gesture.

## 5. Rapid re-press requires all promotion predicates simultaneously

For Session B overlapping Session A terminal ownership, B can promote only while all are simultaneously true:

```text
B.longConfirmed
AND B.stillHeld
AND A/admission ownership ready
```

The implementation must support either event order:

- A becomes ready first -> wait for 300 ms;
- 300 ms occurs first -> wait for A;
- B reaches 300 ms but is released before A becomes ready -> B is cancelled and must never promote later.

Existing pending-repress trigger capture, A output drain, replay-UP acknowledgement, physical transport candidate preservation and accepted Doubao post-processing limitation remain unchanged.

## 6. Pre-HID PHYSICAL_HTT remains authoritative transport evidence

A physical ATVV stream may begin before HID DOWN. Preserve the existing Task 042 pre-HID candidate adoption, fixed-capacity AudioPipe candidate/prebuffer, transport supersession and READY reuse exactly as implemented.

Do not:

- send a duplicate MIC_OPEN for an already-live physical candidate;
- reset the decoder merely because LONG admission is delayed;
- clear the existing candidate/prebuffer at LONG promotion;
- treat pre-HID physical streaming itself as a public voice state;
- change BLEBridge or AudioPipe to implement the 300 ms gate.

## 7. All production microphone trigger entry sources obey the same LONG-only contract

The primary `.hidMonitor` microphone path and any production `voiceKeyFilterFallback` path must not diverge into different user semantics. A fallback path must not retain immediate-direct activation while the primary path is LONG-only.

The trigger-capture mechanics may differ by source, but SHORT remains no-op and LONG remains the only promotion into the existing direct voice lifecycle.

## 8. Resource invariants

This corrective adds no permanent background mechanism.

Allowed new scheduling state:

- at most one cancellable one-shot LONG candidate timer for the current physical gesture.

Forbidden:

- recurring classification timer;
- new dispatch queue for LONG admission;
- new CoreAudio listener/poller;
- readiness activity during candidate/SHORT;
- unbounded candidate, timer, callback, mapped-event, or work-item collections;
- per-tick/high-frequency candidate logging.

After SHORT cleanup, candidate timer count and candidate count must be zero. The bounded mapped-trigger discard owner may remain only for the existing quiet-window lifecycle required to consume late translated Option components.

## Additional deterministic verification

In addition to the existing Task 043 tests, prove:

1. SHORT raw UP before mapped DOWN: late mapped DOWN/UP/flags components are consumed by bounded discard ownership; IME trigger delivery remains zero.
2. SHORT after mapped DOWN but before mapped UP: late mapped UP cannot escape or strand modifier state.
3. LONG threshold before mapped DOWN: direct voice promotion does not close the gate as `noOptionEdge`; later mapped DOWN is delivered exactly once for the same valid gesture.
4. LONG threshold then physical UP before mapped DOWN: later mapped components cannot open the IME.
5. Rapid B reaches threshold, then releases before A terminal ownership clears: A completion cannot auto-promote B.
6. SHORT immediately followed by a valid LONG: old discard/tombstone events cannot consume or mutate the new gesture.
7. SHORT cleanup leaves `VoiceAttemptDiagnostics.currentID == nil` and no armed voice-start watchdog/formal voice timeline for that discarded attempt.
8. Candidate phase performs zero focus-transaction begin/safety-timeout work; focus preparation starts only at actual LONG promotion.
9. `.hidMonitor` and production fallback trigger routes satisfy the same SHORT=no-op / LONG-only contract.
10. Hardware-gate/pending-repress begin failure is explicit and cannot allow mapped DOWN to pass while RemoteOrbit has no matching session owner.

## Preferred mutation boundary

Product source mutation remains primarily `remote-orbit/Sources/RemoteOrbit/main.swift` plus focused tests. If implementation requires production mutation in `VoiceReceiverReadiness.swift`, `BLEBridge.swift`, `AudioPipe.swift`, ATVV, driver, or generic non-microphone HID source, STOP before widening scope.

## Runtime acceptance after source audit

After independent Web source audit passes, use a fresh exact-source candidate and perform two runtime phases:

1. SHORT-only phase: repeated quick taps must produce zero IME openings/readiness activations and no resource growth.
2. LONG phase: normal holds plus bounded rapid re-press; verify voice behavior and memory/CPU stability.

The previously installed candidate remains invalid for final product acceptance.
