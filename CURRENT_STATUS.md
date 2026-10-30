# CURRENT_STATUS

Last updated: 2026-10-30
State: `RO-VOICE-PIPELINE-SIMPLIFICATION-042 — WAITING_FOR_INDEPENDENT_WEB_AUDIT`
Repository: `Lost0rz/RemoteOrbit`

## Current authority

- Active branch: `codex/voice-pipeline-simplification-042`.
- `AGENTS.md` remains durable repository authority.
- `CURRENT_TASK.md` is the sole active execution authorization.
- Frozen 041 observability baseline: `ac3132986197bfee4440bb8f388e3d2e5f478f03`.

## Accepted lineage

- Gate A accepted semantic head: `50b1d9efabe15f04d5479b39af227d0e6f43a4e3`.
- Gate B accepted semantic head: `ae0bf10874d34ce556b4b73a506b22f6a9a1a412`.
- Gate C accepted semantic head: `9abdebc21a1e03c79ab0ac960bf2d9902c24b1d5`.

## Gate A — CLOSED / INDEPENDENT AUDIT PASS

The production voice key is a single direct start/stop transport control. No primary SHORT/LONG/DOUBLE/Persistent/Receiver-A-B voice mode remains. One `VoiceInputProfile` owns the complete session, and trigger UP remains downstream of transport/audio/output drain.

## Gate B — CLOSED / INDEPENDENT AUDIT PASS

ATVV transport readiness is separated from per-session voice streaming. CoreBluetooth/ATVV state is owned by the dedicated serial `com.remoteorbit.ble` queue. Healthy transport remains READY across normal voice sessions. READY requires all required characteristics, both required notify confirmations, and accepted capabilities; stale callbacks/reset cannot satisfy a new transport.

## Gate C — CLOSED / INDEPENDENT AUDIT PASS

Independent Web `CODE_DIFF` audit accepted `9abdebc21a1e03c79ab0ac960bf2d9902c24b1d5` for the Gate C boundary.

Accepted properties:

- active PCM playout uses preallocated `FixedCapacityPCMFrameRing` with 96,000-frame structural capacity at 48 kHz;
- the ring starts empty and has no startup reserve/playout threshold;
- producer writes are serialized by the existing AudioPipe producer-side ownership; CoreAudio is the single consumer;
- the render callback reads directly to caller-owned `AudioBufferList` storage and no longer takes `stateLock`, grows/compacts a Swift PCM array, formats/logs, performs file I/O, or main-thread dispatch/wait;
- bounded atomic render diagnostics and a fixed observation mailbox preserve 041 evidence off the realtime path;
- FIFO, exact full/empty, wraparound, underflow zero-fill, overflow newest-drop, tail preservation, session reset, and SPSC stress have focused coverage;
- normal remote deactivation preserves queued tail; a new session/explicit reset clears stale PCM;
- output-drain completion still requires inactive remote route plus actual ring emptiness;
- BLE/ATVV, Gate A/B semantics, gain/limiter/resampling, jitter policy, driver/runtime/install/TCC/Air were unchanged by Gate C.

Executor evidence at the accepted head recorded focused Gate C/regression tests `196/196`, full Swift `534/534`, arm64/x86_64 Release builds, protocol self-tests `3/3`, and `git diff --check` passing. This source acceptance does not claim installed/hardware/Air natural-use acceptance.

## Gate D — CORRECTIVE IMPLEMENTATION COMPLETE / WAITING FOR INDEPENDENT WEB AUDIT

Gate D added one explicit per-stream startup playout reserve around the
accepted Gate C consumer. PCM enters the existing 96,000-frame ring
immediately; active render remains in `WAITING_FOR_RESERVE` until the selected
threshold, then transitions once to `STARTED`. Tail/drain bypasses the reserve
before threshold and preserves the existing actual-ring-empty completion.

Candidate frame thresholds at the existing 48 kHz output rate are fixed and
centralized: `0 ms = 0`, `45 ms = 2,160`, `75 ms = 3,600`, `100 ms = 4,800`.
The selected bounded default is `45 ms`. It is the smallest positive candidate
that removed the deterministic short-jitter active underflow without tail
bypass; `75 ms` and `100 ms` provided no further underflow reduction and added
startup latency. The comparison was deterministic synthetic evidence only and
does not claim hardware or natural-use acceptance.

### Gate D candidate comparison evidence

The short-jitter simulation used 10 ms / 480-frame CoreAudio callbacks, an
initial 480-frame arrival, a 30 ms gap, a 3,600-frame burst, and then a
sufficient 600-frame/tick supply. `dropped_or_stranded_pcm` was zero for every
candidate.

| candidate | startup latency | actual start depth | active underrun callbacks | active underrun frames | tail bypass |
| --- | ---: | ---: | ---: | ---: | ---: |
| 0 ms | 0 ms | 480 | 3 | 1,440 | 0 |
| 45 ms | 40 ms | 4,080 | 0 | 0 | 0 |
| 75 ms | 40 ms | 4,080 | 0 | 0 | 0 |
| 100 ms | 60 ms | 5,280 | 0 | 0 | 0 |

The separate sustained-deficit control began with 4,800 frames and then
supplied 240 frames/tick against 480-frame consumption. All candidates still
recorded 6 active underflow callbacks and 1,440 active underflow frames, with
no dropped or stranded PCM. `SELECTION_AMBIGUOUS=NO`.

### Gate D implementation properties

- Reserve wait outputs direct silence, consumes zero remote PCM, and emits no
  active underrun, queue-starvation, or front-edge-underrun evidence.
- Actual remote consumption remains the only source for output-boundary and
  F5/F8 first-rendered markers; meter rendered-frame counts exclude reserve
  silence.
- A later queue dip does not re-arm reserve. New remote activation is the
  reset boundary.
- Existing diagnostics expose configured milliseconds/frames, candidate and
  selected default, state, start depth, wait duration, and threshold/tail
  start reason through the existing snapshot/runtime-health/summary authority.
- Gate C ring capacity and newest-drop overflow policy are unchanged; no
  adaptive jitter, rebuffering, BLE/ATVV, Gate E, driver, runtime, install,
  TCC, Air, merge, tag, or release behavior changed.

### Gate D independent-audit blocker and corrective result

The independent Web audit identified a publication-order race in the original
Gate D implementation: realtime `remoteActive=true` was published before the
new session's ring and playout reserve reset completed. The same audit found
that reserve `STARTED` was published before its start metadata was complete.

The corrective implementation now withdraws the CoreAudio-visible active bit,
clears the prior drain waiter, resets the Gate C ring, resets the Gate D
reserve, resets session-owned bookkeeping, and only then publishes active.
The executable `AudioPipeRemoteActivationTransition` contract and focused test
pin this order. An inactive empty ring now remains
`WAITING_FOR_RESERVE`; inactive queued tail PCM still gets one tail bypass.
Reserve start uses scalar states `waiting → publishing metadata → started`;
timestamp, depth, and reason are written before `STARTED` becomes observable,
and snapshots retry across a concurrent state change. The CoreAudio path still
uses no ordinary lock, allocation, queue, wait, or dynamic collection.

This is source/test evidence only. No installed, hardware, Air, or natural-use
acceptance is claimed.

### Gate D verification receipt

- Focused corrective AudioPipe/reserve suites: `22/22` passed.
- Full Swift test suite: `552/552` passed.
- arm64 Release build: passed.
- x86_64 Release build: passed.
- Protocol self-tests: `3/3` passed.
- `git diff --check`: passed.

Changed paths are the Gate D reserve seam, the executable activation-order
contract, AudioPipe/render accounting, focused tests, the protocol self-test
source list, and the Gate D design/plan documents. No product packaging,
installation, driver, TCC, Air, merge, tag, or release operation was performed.

## Stop / next

Gate D corrective implementation and required verification are complete on the
canonical writer. The branch must be committed/pushed with exact local/remote
equality, then remains stopped at `WAITING_FOR_INDEPENDENT_WEB_AUDIT` for a
fresh independent Web/code audit of the corrective head.

Do not begin Gate E automatically. Do not merge, tag, release, package/install, mutate TCC, or change Air runtime.
