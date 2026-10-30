# RemoteOrbit Current Task

## RO-VOICE-PIPELINE-SIMPLIFICATION-042 — Gate C Realtime-safe Audio Data Plane

Status: `READY_FOR_LOCAL_GATE_C`

Repository: `Lost0rz/RemoteOrbit`

Active branch: `codex/voice-pipeline-simplification-042`

Frozen evidence baseline: `ac3132986197bfee4440bb8f388e3d2e5f478f03`

Gate A accepted semantic head: `50b1d9efabe15f04d5479b39af227d0e6f43a4e3`

Gate B accepted semantic head: `ae0bf10874d34ce556b4b73a506b22f6a9a1a412`

## Objective

Continue the already-decided single-path voice architecture by making the PCM playback data plane realtime-safe and bounded without changing BLE/ATVV semantics or introducing jitter tuning.

The user-facing product contract remains:

```text
VOICE DOWN
→ trigger + remote voice opening
→ BLE/ATVV decode
→ PCM playback

VOICE UP
→ BLE/audio-stop tail completes
→ queued output drains
→ same trigger UP
```

Gate C changes only the decoded-PCM → CoreAudio data plane.

## Prior accepted gates

### Gate A — CLOSED / PASS

Single direct voice-session path; no production SHORT/LONG/DOUBLE/Persistent/Receiver-A-B mode; captured VoiceInputProfile owns the whole session; tail trigger release remains downstream of BLE/audio and output drain.

### Gate B — CLOSED / PASS

Accepted head: `ae0bf10874d34ce556b4b73a506b22f6a9a1a412`.

- dedicated serial BLE queue `com.remoteorbit.ble`;
- strict ATVV READY and healthy READY reuse across sessions;
- main callback isolation;
- genuine failure clears stale transport state;
- post-release grace / 350 ms AUDIO_STOP drain / admission barrier preserved;
- no AudioPipe architecture or jitter change.

## Gate C — Realtime-safe audio data plane — AUTHORIZED

### Goal

Replace the current dynamic, lock-sharing PCM queue/render path with a bounded fixed-capacity producer/consumer path so the CoreAudio realtime callback does not allocate, compact Swift Arrays, perform formatting/I/O, or acquire the current ordinary producer lock.

### Required target model

Producer side:

```text
BLE queue
→ ATVV decode
→ existing gain/limiter/resample semantics
→ fixed-capacity PCM ring write
```

Consumer side:

```text
CoreAudio IOProc
→ fixed-capacity PCM ring read
→ copy directly to output buffers
→ zero-fill true underflow
→ return
```

Single producer is the existing BLE/audio submission path. Single consumer is the CoreAudio render callback.

### Authorized work

1. Introduce one fixed-capacity SPSC PCM ring or equivalently bounded single-writer/single-reader structure for remote PCM playout.
2. Preallocate storage needed by the realtime render path before callbacks begin.
3. Remove dynamic `pendingOutput` growth/compaction from the active realtime path.
4. Remove the ordinary shared producer/consumer `NSLock` from the realtime callback path. If a minimal atomic/index mechanism is required, keep it bounded and realtime-appropriate.
5. Preserve current submitted/rendered/queue-depth/underrun/tail/overflow diagnostic meaning. Adapt counters only where necessary to remain truthful with the new representation.
6. Preserve existing AudioPipe public behavior used by Gate A/B, including remote candidate/routing, output-drain completion, diagnostics snapshots, local-mic behavior, gain/limiter/resample semantics, and virtual-device output contract.
7. Keep output drain event-driven by actual queued PCM becoming empty, not by introducing a new arbitrary fixed delay.
8. Keep explicit bounded overflow behavior. If the fixed ring becomes full, record the drop truthfully; do not silently overwrite unread PCM unless the current task implementation explicitly proves that policy is required and tests it.
9. Preserve one canonical writer and existing 041 observability authority.

### Realtime requirements

The production CoreAudio render callback must not perform:

- heap allocation for per-callback sample arrays;
- Swift Array append/removeFirst/compaction/growth;
- ordinary blocking `NSLock` acquisition shared with the producer;
- disk/file I/O;
- JSON/string formatting/log printing;
- main-thread dispatch/waits.

The callback may perform fixed-size/index arithmetic, bounded memory copies, zero-fill, and realtime-safe counter updates needed for existing diagnostics.

### Semantics that must remain unchanged

- ATVV v0.4/v1.0 command/framing/capability/codec semantics;
- ADPCM decode and sample-rate selection;
- CoreBluetooth dedicated queue and strict READY model from Gate B;
- keepalive/reconnect/discovery/subscription behavior;
- Gate A direct voice/session/profile/trigger ownership;
- physical-UP post-release grace and 350 ms AUDIO_STOP drain;
- current gain/limiter behavior;
- current 16 kHz/8 kHz → output-rate resampling behavior unless a purely mechanical buffer-interface adaptation is required;
- virtual audio driver behavior and format;
- current user-visible start/tail policy.

### Forbidden in Gate C

Do NOT:

- add or tune a jitter reserve / playout startup threshold;
- add a multi-frame intentional latency buffer beyond the ring capacity needed for bounded transport between producer/consumer;
- change BLE/ATVV protocol or connection lifecycle;
- change codec, gain, limiter, sample-rate policy, or speech processing;
- change menu/profile/voice-key semantics;
- redesign Gate A/B state machines;
- add new always-on diagnostic authorities/rings unrelated to the PCM transport structure;
- package/install/replace the app, reload CoreAudio, mutate TCC, or alter Air runtime;
- merge, tag, release, close preserved PRs, or mutate 039/040/041;
- begin Gate D or Gate E automatically.

If a desired change materially alters playout latency/jitter policy, STOP and leave it for Gate D.

## Gate C verification requirements

At minimum prove:

1. exact live branch/head and clean canonical writer before mutation;
2. one fixed-capacity PCM producer/consumer structure owns the active remote playout queue;
3. producer and consumer have one clear ownership model with no ordinary blocking lock in the CoreAudio realtime callback;
4. render callback performs no per-callback heap allocation or dynamic collection mutation;
5. ordered PCM written by the producer is rendered in order without duplication/reordering;
6. true underflow zero-fills only the missing output portion and increments truthful underrun evidence;
7. ring-full/overflow policy is bounded, deterministic, tested, and reflected in existing overflow evidence;
8. queue-depth diagnostics are derived truthfully from the new ring state;
9. output-drain completion fires only after the submitted queue has actually drained and preserves Gate A trigger-up ordering;
10. tail PCM submitted before transport stop remains renderable after remote route deactivation until the queue is empty;
11. rapid session transitions do not leak stale PCM from one session into another;
12. local-mic/non-remote behavior remains unchanged where covered;
13. Gate B BLE queue/READY tests pass unchanged in semantic expectation;
14. ATVV protocol tests pass unchanged in semantic expectation;
15. 041 continuity/diagnostic/export tests remain truthful;
16. focused AudioPipe tests include wraparound, partial read/write, exact-full/empty, underflow, overflow, drain, reset/session boundary, and counter behavior;
17. full Swift tests pass;
18. arm64 release build passes;
19. x86_64 release build passes;
20. protocol self-tests pass;
21. `git diff --check` passes;
22. final diff proves no Gate D jitter tuning and no Gate E start/tail policy change leaked into Gate C.

## Evidence to return

The executor receipt must report:

- old vs new AudioPipe queue model;
- ring capacity and why it is structural capacity rather than intentional jitter reserve;
- producer/consumer ownership;
- realtime callback operations after the change;
- overflow/underflow policy;
- output-drain semantics;
- diagnostics/counter mapping;
- exact changed paths;
- focused and full verification results;
- explicit confirmation that BLE/ATVV, jitter policy, Gate A/B semantics, driver/runtime were not changed.

## Completion / stop state

After Gate C implementation and verification:

- update `CURRENT_STATUS.md` and `CURRENT_TASK.md` together;
- commit all authorized Gate C changes;
- push only `codex/voice-pipeline-simplification-042` and verify exact remote identity;
- stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`;
- do not begin Gate D/E automatically;
- do not merge, tag, release, install, mutate TCC, or change the Air runtime.
