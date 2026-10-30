# RO-VOICE-PIPELINE-SIMPLIFICATION-042 — Rapid Re-press Evidence and Design

Date: 2026-10-30
Task: `RO-VOICE-PIPELINE-SIMPLIFICATION-042`
Branch: `codex/voice-pipeline-simplification-042`

## Context

Task 042 previously fixed two rapid-repress ownership defects:

- released HOST_MIC_OPEN grace could misclassify a new physical `AUDIO_START reason=0x03` and later send a stale MIC_CLOSE;
- promoted hardware re-press could mutate/replay the new DOWN before final admission, or fail to own its own mapped-UP/output-drain lifecycle.

Those source corrections passed independent Web audit. A fresh `0.2.14 (43)` candidate was then packaged and installed for final RC003 hardware acceptance.

## RC003 human runtime result

Result: `FAIL`.

User-visible symptoms under extreme rapid release/re-press:

1. the IME waveform can remain active briefly after the physical button is already released;
2. a new hold can show waveform/input activation while speech produces no transcription;
3. failures concentrate in very fast re-press sequences.

The captured runtime evidence is sufficient for a bounded corrective; no new broad probe phase is required.

Observed evidence summary:

- 13 `late AUDIO_START ignored during drain` events;
- 7 rapid re-press admission rejections with `voice_session_busy`;
- 8 microphone DOWN edges suppressed by the existing debounce window;
- at least streams 31 and 48 contained physical audio with `session_id=NA` and zero render callbacks / filled frames;
- no permanent stuck session was observed; final runtime recovered to idle/READY.

## Verified architectural constraints

### ATVV start is the only reliable new-stream boundary

ATVV v1.0 `AUDIO_START` carries the new stream ID, while subsequent audio payloads do not carry stream identity. Once a new `AUDIO_START` is observed, the host cannot reliably continue assigning later audio to the prior stream.

Therefore a distinct new physical `AUDIO_START` is the authoritative transport-epoch boundary.

### The 350 ms tail window is still needed

The runtime capture contains late audio close to the existing tail window. The purpose of the 350 ms drain is valid: without a replacement stream, old late packets may still need to be decoded/queued.

The defect is not the duration itself. The defect is treating that timer as an uninterruptible transport/admission lock after a distinct new physical stream has already been announced.

### Old queued output and new transport ownership are different lifetimes

Already queued A PCM can continue rendering after A stops accepting BLE ingress. A new B transport epoch does not require discarding A's queued output tail.

The design must therefore separate:

- BLE ingress/decoder ownership;
- AudioPipe queued output drain;
- pre-HID candidate buffering;
- direct-session trigger ownership.

## Failure model

Current behavior couples these lifetimes:

```text
A AUDIO_STOP
  -> audioStopDrainWorkItem active for 350 ms
  -> A remains transport/decoder owner
  -> new session admission is blocked

B AUDIO_START(reason=0x03, new stream ID)
  -> ignored because old drain exists
  -> later B audio can be decoded/accounted under A

B HID DOWN
  -> may be rejected voice_session_busy
  -> or suppressed by generic <180 ms debounce
```

This directly explains the observed waveform-without-transcription shape: physical audio exists, but there is no correctly admitted/routed B voice session.

## Options considered

### Option 1 — shorten the 350 ms drain

Rejected.

It reduces overlap probability but restores tail-loss risk and does not fix the ownership model.

### Option 2 — accept B `AUDIO_START` but leave AudioPipe unchanged

Rejected.

If A's route is still active, generic `AudioPipe.feed()` can send B PCM into A's output. Transport ownership would be fixed while audio ownership remained wrong.

### Option 3 — buffer B `AUDIO_START` until A drain expires

Rejected.

Audio payloads after `AUDIO_START` have no stream identity. Delaying the epoch switch loses or misattributes B's first audio.

### Option 4 — run A and B decoders in parallel

Rejected.

Without per-packet stream identity there is no reliable way to route ambiguous payloads between two simultaneous decoder epochs.

### Option 5 — selected: transport-epoch supersession + candidate isolation + serialized promotion

Selected.

A distinct physical B `AUDIO_START` can supersede old A BLE ingress ownership while preserving A's already queued output. B becomes a pre-HID candidate immediately, its PCM is isolated from A, and B's HID/trigger/session activation remains serialized behind A's terminal trigger/output ownership.

## Selected design

### 1. Physical transport-epoch supersession

Apply only when:

- old stream A is physical-HTT and already in terminal `AUDIO_STOP` drain;
- incoming event is explicit `AUDIO_START reason == 0x03`;
- incoming stream ID differs from A's stream ID;
- A is in terminal/released lifecycle, not a legitimately overlapping active owner.

Then:

- invalidate/cancel A's BLE ingress drain ownership using epoch/generation identity;
- preserve A's already queued AudioPipe output;
- begin/reset decoder state for B;
- install B stream ID;
- classify B as `.preHIDPhysical`;
- retain READY;
- prevent stale A drain completion from clearing, stopping or retiring B.

This is a physical transport-drain supersession rule, not a global drain-time start rule and not a replacement for the existing HOST_MIC_OPEN grace supersession logic.

### 2. Candidate-only PCM path

AudioPipe needs an ownership-aware candidate ingest path.

Required semantics:

```text
A active output tail       -> continues rendering already queued A PCM
B preHID candidate samples -> candidate/prebuffer only
B candidate samples        -> never render through A active route
```

When B candidate is installed, old A teardown must not blindly call a destructive candidate reset that clears B's prebuffer.

Candidate state should be scoped to the live replacement epoch so a stale old-session callback cannot clear it.

### 3. Earlier direct re-press deferral

Current direct pending logic is too late if it requires `directOutputDrainRequested` before retaining B.

The new admissible pending boundary is:

- A direct session exists;
- A physical UP has been observed;
- B live pre-HID physical candidate exists;
- there is no second pending owner.

B is retained but not activated.

The accepted serialization remains:

```text
A physical UP
-> A transport terminal boundary
-> A queued output drain
-> A mapped UP / replay pass acknowledgement
-> B promotion / replay DOWN
-> B direct session
```

Early B UP cancels B using the existing bounded tombstone/no-trigger-leak model.

### 4. BLE-owned candidate truth

Expose a thread-safe source of truth equivalent to:

```text
isStreaming && streamOwnership == .preHIDPhysical
```

Use it at critical admission/debounce decisions so correctness does not depend on a main-queue callback having already copied that state into `VoicePressCoordinator`.

### 5. Evidence-gated debounce bypass

Keep the existing generic 180 ms debounce and generic button policy.

For the microphone voice key only:

- if a rapid DOWN falls inside the normal debounce interval;
- and BLE already has a live new physical candidate;

then that transport evidence proves this is a new physical press, so the voice DOWN/UP pair may bypass debounce.

Without candidate evidence, existing bounce protection remains unchanged.

## Preserved behavior

- Normal no-repress `AUDIO_STOP` may still accept old late packets for the existing 350 ms window.
- Same-stream or non-0x03 starts do not invoke physical drain supersession.
- Existing HOST_MIC_OPEN grace supersession and stale-MIC_CLOSE protection remain unchanged.
- Existing A-UP-before-B-DOWN hardware serialization remains unchanged.
- Existing promoted-B mapped-UP/output-drain/replay-ACK lifecycle remains unchanged.
- Long-lived READY and strict READY remain unchanged.
- Gate C ring and Gate D 45 ms reserve remain unchanged.
- ATVV codec/framing remains unchanged.
- Driver/TCC remain unchanged.
- No global UNKNOWN remap.
- No Gate F.

## Verification contract

Deterministic tests must prove:

1. new physical reason03/different-stream start supersedes old physical drain;
2. stale old drain callback cannot retire B;
3. B candidate PCM cannot render through A;
4. A teardown cannot clear B candidate/prebuffer;
5. B HID during A transport drain is deferred rather than busy, even before old output drain has begun;
6. A-UP-before-B-DOWN and promoted-B UP/output-drain/replay-ACK remain ordered;
7. live candidate bypasses microphone debounce inside 180 ms;
8. no live candidate preserves debounce;
9. non-0x03 and same-stream cases preserve existing behavior;
10. normal 350 ms tail behavior, HOST_MIC_OPEN regressions, READY, Gate C/D and steady-state adopted-PHYSICAL behavior remain green.

## Consequences

The selected design increases ownership explicitness in BLEBridge and AudioPipe, but avoids changing the ATVV protocol model or adding parallel decoders. It also removes correctness dependence on fixed timing gaps between BLE and HID callbacks.

## Reversibility

The corrective is bounded to Task 042 and can be reverted independently if runtime evidence disproves the transport-epoch model. The prior audited Task 042 source remains available in history.

## Reversal trigger

Reconsider this design only if deterministic implementation evidence shows one of the following:

- a distinct reason03/new-stream `AUDIO_START` can still belong to the old transport epoch;
- packet-level evidence provides another reliable stream identity after `AUDIO_START`;
- candidate-only AudioPipe isolation cannot be implemented without changing driver/protocol ownership.

`TASK_RECONCILIATION_REQUIRED: YES` — RC003 failed the prior runtime gate, so `CURRENT_TASK.md` must authorize this new bounded corrective before product-source mutation.
