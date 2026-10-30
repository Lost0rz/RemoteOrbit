# Voice Pipeline Gate D Small Measured Jitter Reserve

## Intent

Add one bounded startup playout reserve around the accepted Gate C PCM
consumer so short BLE arrival bursts/gaps do not become active front-edge
underruns. The reserve is a startup policy only: PCM enters the existing
96,000-frame ring immediately, the consumer waits once for a selected fixed
threshold, and a remote tail bypasses that threshold so short utterances can
drain.

## Goals

- Make `WAITING_FOR_RESERVE → STARTED` explicit and per remote stream.
- Evaluate exactly `0/45/75/100 ms` at the existing 48 kHz output rate.
- Keep the CoreAudio callback allocation-free, lock-free with respect to the
  producer, and limited to scalar/atomic reserve checks plus bounded ring/I/O.
- Make configured reserve, actual start depth, wait duration, start reason,
  and selected candidate available through the existing diagnostics authority.
- Prove with deterministic simulation that a finite reserve helps short jitter
  but does not repair a sustained supply deficit.

## Non-goals and anti-goals

- No ring-capacity change, second PCM buffer, adaptive jitter estimation,
  rebuffering, time stretching, packet-loss concealment, BLE/ATVV change, or
  Gate E trigger/tail change.
- No packaging, installation, runtime, TCC, driver, Air, merge, tag, or
  release action.
- Reserve silence is not rendered PCM, not an underrun, and does not advance
  first-real-PCM markers.

## Approaches considered

1. **One reserve state around the Gate C consumer — selected.** Keep the
   existing ring as the only PCM authority and add fixed scalar/atomic state
   beside the consumer. This preserves FIFO, overflow, tail, and realtime
   ownership while making the policy auditable.
2. **Put reserve semantics inside the PCM ring.** Rejected because transport
   capacity and playout policy would become one authority, making tail bypass,
   session reset, and diagnostics less explicit.
3. **Use a second prebuffer or adaptive/rebuffering controller.** Rejected by
   the Gate D card: it adds another PCM authority or changes startup policy
   after playout and would exceed the authorized scope.

## Design

`AudioPipePlayoutReserve` owns the candidate-to-frame conversion, selected
default, atomic state, and bounded start evidence. A new remote activation
resets it to `WAITING_FOR_RESERVE`; the first render that observes threshold
depth transitions it once to `STARTED`. A zero threshold starts immediately.
When the route is inactive, the same state transitions through a tail-bypass
reason and the existing ring read proceeds unchanged. No later empty queue or
underrun can re-arm the reserve.

The render path checks the reserve before calling the ring consumer. Waiting
renders direct silence without consuming the ring and uses a new
`AudioPipeRenderState.reserveWait` accounting state. The existing active
underrun/starvation/front-edge evidence is therefore emitted only after
`STARTED`. Actual remote consumption remains the sole source for output-boundary
and F5/F8 first-rendered markers.

The existing `AudioPipeDiagnosticsSnapshot` carries the bounded reserve
configuration and start evidence. Candidate comparison is a deterministic pure
simulation with 10 ms/480-frame callbacks and a burst/gap pattern whose long-run
supply is sufficient; a separate initial-full-burst/under-supply scenario
demonstrates the permanent-deficit limit. The smallest positive candidate that
eliminates the synthetic active underflow without tail bypass is selected; the
recorded comparison remains the authority if the candidates are not distinct.

## Acceptance

The Gate D card's 14 reserve tests, required regressions, full Swift tests,
both release builds, protocol self-tests, and `git diff --check` must pass.
The final control transition updates `CURRENT_STATUS.md` and `CURRENT_TASK.md`
together and stops at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`.
