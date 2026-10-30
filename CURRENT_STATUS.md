# CURRENT_STATUS

Last updated: 2026-10-30
State: `RO-VOICE-PIPELINE-SIMPLIFICATION-042 — READY_FOR_LOCAL_GATE_D`
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

## Current authorized gate

`Gate D — Small measured jitter reserve` is now authorized for local construction.

Gate D may add only a small, explicit, measurable startup playout reserve on top of the accepted Gate C ring so short BLE arrival jitter can be absorbed without redesigning BLE/ATVV, AudioPipe transport capacity, Gate A/B ownership, or tail semantics.

The reserve must be a true playout-start threshold, not a larger ring, not adaptive rebuffering, and not a claim to repair permanent BLE delivery deficit. The implementation must make the added latency explicit and measurable.

Initial candidate values for evidence-driven evaluation are `0 ms`, `45 ms`, `75 ms`, and `100 ms`; source authority may choose one bounded default only after tests/recorded evidence justify it. No value above 100 ms is authorized in Gate D.

## Stop / next

Local construction must fetch this branch, read `AGENTS.md`, this file, and `CURRENT_TASK.md`, reuse one canonical writer, execute Gate D only, push the same branch, and stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`.

Do not begin Gate E automatically. Do not merge, tag, release, package/install, mutate TCC, or change Air runtime.
