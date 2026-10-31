# RO-VOICE-PIPELINE-SIMPLIFICATION-042 — RC003 Runtime Owner-Race Addendum

Date: 2026-10-31
Task: `RO-VOICE-PIPELINE-SIMPLIFICATION-042`
Branch: `codex/voice-pipeline-simplification-042`
Runtime candidate: product source `ef606a3f712304cf43da2e9fb849a87a0bb02a1b`, installed executable SHA-256 `2799d6a4b2b13a08f4304e00b75962c2dfaf95fd6d25e65894ae7e7ad30ee935`, PID `31333`.

## Human runtime result

Result: `FAIL`.

The user still reproduced an extreme rapid-repress failure where Doubao shows its listening waveform but the new speech does not reach transcription.

The user also observed that Doubao itself appears unable to accept an immediate new utterance while it is still post-processing the previous one. That may be a separate external IME readiness boundary, but the current capture already proves RemoteOrbit failures before any such external policy should be introduced.

## Fresh evidence

### A. Production mapped-trigger ownership differs from the deterministic test model

Fresh diagnostic counts:

- `PHYSICAL_TRANSPORT_SUPERSEDED`: 18;
- `VOICE_PRESS_ADMISSION admitted / voice_down_opening`: 36;
- `VOICE_PRESS_ADMISSION deferred / direct_output_drain`: 10;
- `VOICE_PRESS_ADMISSION rejected / pending_hardware_repress_owner_missing`: 10;
- `PENDING_HARDWARE_REPRESS_BEGIN`: 0;
- `PENDING_HARDWARE_REPRESS_PROMOTE`: 0;
- `REPLAY_UP_PASS_ACK`: 0;
- `OPTION_GATE_STALE_EVENT`: 36.

For all 36 direct openings in this fresh run, the immediate hardware gate resolved `noOptionEdge`; the later old mapped Option-UP release was therefore stale/unowned. Mapped trigger traffic arrived with gate state `none` and passed through.

The important production ordering is therefore:

```text
A raw HID DOWN
-> coordinator starts A
-> filter gate is armed
-> coordinator immediately releases/resolves the gate
-> no mapped Option DOWN has arrived yet
-> gate resolves noOptionEdge
-> A mapped Option DOWN later arrives and passes directly
-> A has no heldHardwareOptionSessionID
```

The prior complete-lifecycle regression manually injected A's mapped DOWN before releasing the gate, so it created an old hardware owner that production does not create in this timing regime.

### B. Why B produces waveform without RemoteOrbit audio

During rapid B re-press:

```text
B physical AUDIO_START
-> B becomes live pre-HID candidate
-> A receives PHYSICAL_TRANSPORT_SUPERSEDED and starts terminal output drain

B raw HID DOWN
-> coordinator sees live B candidate and defers B for direct_output_drain
-> coordinator calls beginPendingHardwareOptionRepress(B)
-> filter rejects the begin because A has neither heldHardwareOptionSessionID
   nor pendingReplayedHardwareOptionUp
-> return value is ignored

B mapped Option DOWN
-> no pending filter owner exists
-> event passes to Doubao
-> Doubao waveform can appear

A drain completes
-> coordinator attempts B promotion
-> promotePendingHardwareOptionRepress(B) has no pending owner/captured DOWN
-> B rejected pending_hardware_repress_owner_missing
-> direct re-press activation loses the live physical candidate
```

This exactly matches the human symptom: the IME receives a trigger edge and can display a waveform, while RemoteOrbit never commits B as the routed audio session.

The failure occurred 10 times in the fresh capture, including around 08:28:44, 08:29:19, 08:29:51, 08:29:53, 08:29:56, 08:30:05, 08:30:10, 08:30:12, 08:30:19 and 08:30:20 (+08:00).

## C. Released HOST_MIC_OPEN drain still consumes physical starts

The fresh run also contains three terminal HOST_MIC_OPEN overlaps:

```text
old A streamID=0 / HOST_MIC_OPEN
-> A physical release observed
-> AUDIO_STOP reason=0x02
-> 350 ms drain active
-> released-host grace active

new B AUDIO_START reason=0x03 / new stream ID
-> ignored as late AUDIO_START during drain
```

Observed new stream IDs were 73, 91 and 102. One matching B HID DOWN was rejected `voice_session_busy`; two were suppressed by debounce after the physical transport start had already been discarded.

The existing host supersession helper intentionally requires `audioStopDrainWorkItem == nil`, so it only handles a reason03 arrival after the old drain has already retired. The fresh runtime proves that the same released-host ownership must be supersedable while the old drain is still active.

## Design question A

How should a deferred direct hardware B own its mapped DOWN when A's production hardware gate resolved before A's mapped DOWN arrived and therefore there is no old filter-owned hardware-UP owner?

### Rejected option — let B mapped DOWN pass and treat it as already promoted

Rejected because it recreates the user-visible failure boundary: the IME can open before RemoteOrbit has committed B's route/candidate. It also makes first-audio correctness depend on uncontrolled timing between Doubao and A output retirement.

### Selected option — explicit pending B capture authorized by coordinator ownership

The coordinator already has the authoritative reason B is deferred: A still owns direct output/terminal lifecycle and BLE proves a live B physical candidate.

Under that exact path, the filter may arm a pending B DOWN owner even when it has no old held/replay-UP owner. This is not a global loosening of filter ownership; it is a new explicit begin mode called only from the direct-output-drain re-press state.

The begin operation must return structured state equivalent to:

```text
ARMED_AWAITING_OLD_UP_ACK
ARMED_NO_OLD_UP_OWNER
REJECTED
```

The coordinator must consume that result. It must never claim that it is waiting for old-UP acknowledgement when the filter has no owner capable of producing that acknowledgement.

### Two-condition promotion barrier

Once B pending capture is armed, B mapped Option DOWN is captured/suppressed rather than passed to the IME.

Promotion may occur only after both facts are true:

```text
A terminal/output/trigger ownership complete
AND
B mapped DOWN captured by the pending owner
```

Correctness must not depend on which fact happens first.

If B DOWN is captured first, wait for A. If A completes first, retain B pending ownership and wait for mapped DOWN capture. The event-capture side must notify or otherwise make readiness observable so promotion can resume once the second condition becomes true.

After both facts are true, reuse the current pending promotion/replay path; do not synthesize a new independent trigger model.

Early B physical UP keeps the current cancellation/tombstone semantics so later mapped release components cannot leak.

## Design question B

When can a physical B supersede an old HOST_MIC_OPEN stream that is still inside AUDIO_STOP drain?

### Selected narrow predicate

Allow it only when all are true:

- AUDIO_STOP drain is active and has a real pending stop reason;
- old stream is the HOST_MIC_OPEN voice session;
- `releasedHostMicOpenGrace` belongs to that session and records `physicalReleaseObserved == true`;
- incoming start is explicit physical `reason == 0x03`;
- incoming stream ID differs from the old stream ID.

This uses already-existing released-host evidence rather than reclassifying active host sessions.

### Required retirement order

For the narrow predicate:

1. retire/cancel only A BLE ingress drain ownership with the existing transport epoch/generation protection;
2. cancel/retire the released host grace and host voice intent locally before B becomes current, so no later MIC_CLOSE uses B's mutable stream ID;
3. preserve already queued A AudioPipe output;
4. begin B decoder epoch and install B stream ID;
5. classify B as `.preHIDPhysical` and keep its PCM candidate-only;
6. notify the existing physical-transport-superseded coordinator path so A completes output/trigger retirement and B remains serialized;
7. retain READY.

Unreleased HOST_MIC_OPEN, non-0x03, same-stream and normal no-replacement drain behavior remain unchanged.

## Doubao post-processing observation

Do not add an IME cooldown/re-arm delay in this corrective.

The user may be observing a real Doubao post-processing busy period. However, an IME delay would mask rather than fix the two proven RemoteOrbit failures above. Re-evaluate external IME readiness only after a later capture proves:

- B transport/session admission succeeds;
- B candidate is promoted;
- AudioPipe actually renders B PCM to RemoteOrbit Mic;
- and Doubao still refuses the utterance during its post-processing phase.

Only that evidence would justify a separate IME-facing re-arm policy.

## Verification contract

Tests must reproduce deployed ordering rather than the old idealized gate timing:

1. A gate resolves `noOptionEdge` before A mapped DOWN; no old held hardware owner exists.
2. B direct-output-drain deferral can still arm a pending B owner.
3. B mapped DOWN is captured/suppressed, never passed early.
4. A-complete-before-B-DOWN and B-DOWN-before-A-complete both converge to exactly one B promotion.
5. pending begin failure is explicit and cannot strand a deferred B.
6. early B UP cancels without trigger leakage.
7. legacy old-UP-owned pending path remains green.
8. released HOST drain + reason03/new stream supersedes immediately.
9. stale old drain/grace/MIC_CLOSE cannot mutate or close B.
10. unreleased host, non-0x03, same-stream, normal 350 ms tail, generic debounce, READY, candidate isolation, A-terminal/B-preservation, Gate C/D and ATVV protocol behavior remain green.

## Scope / non-goals

- No arbitrary Doubao cooldown.
- No broad probe work.
- No global 350 ms drain reduction.
- No global debounce reduction/removal.
- No parallel ambiguous decoder epochs.
- No driver/TCC changes.
- No merge/tag/release/Gate F before the renewed source audit and human runtime acceptance.

`TASK_RECONCILIATION_REQUIRED: YES` — the fresh human runtime gate failed and `CURRENT_TASK.md` must authorize these two bounded source correctives before mutation.
