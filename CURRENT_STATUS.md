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
- Gate D accepted semantic head: `9cdbf6f5190d9ed453d7f15cf2e8192973cc62ad`.

## Gate A — CLOSED / INDEPENDENT AUDIT PASS

The production voice key is one direct start/stop transport control. No primary SHORT/LONG/DOUBLE/Persistent/Receiver-A-B voice mode remains. One captured `VoiceInputProfile`/trigger owns each complete session. Trigger UP remains downstream of transport/audio/output drain.

## Gate B — CLOSED / INDEPENDENT AUDIT PASS

ATVV transport readiness is separate from per-session voice streaming. CoreBluetooth/ATVV state is owned by dedicated serial queue `com.remoteorbit.ble`. Healthy transport remains strict READY across normal sessions; stale callbacks/reset cannot satisfy a new transport.

## Gate C — CLOSED / INDEPENDENT AUDIT PASS

Remote playout uses the preallocated 96,000-frame `FixedCapacityPCMFrameRing`. The CoreAudio callback reads directly into `AudioBufferList`, does not take the producer `stateLock`, and keeps diagnostics on bounded atomic/off-path structures. Tail PCM remains renderable after route deactivation; output drain requires actual ring empty.

## Gate D — CLOSED / INDEPENDENT AUDIT PASS

Independent Web `CODE_DIFF` audit accepted `9cdbf6f5190d9ed453d7f15cf2e8192973cc62ad` for the Gate D boundary.

Accepted properties:

- one-shot startup playout reserve with explicit `WAITING_FOR_RESERVE → STARTED` state;
- selected default `45 ms = 2,160 frames` at 48 kHz; `0/45/75/100 ms` remain the bounded candidate set;
- reserve wait consumes no PCM and is not counted as active underrun/starvation/front-edge evidence;
- first-render markers advance only on actual remote PCM consumption;
- once started, reserve never re-arms during the stream;
- inactive queued tail bypasses reserve once; inactive empty state does not start/bypass reserve;
- short utterances released below threshold remain drainable to actual ring empty;
- producer-side new-session activation withdraws realtime active before ring/reserve reset and republishes active only after initialization;
- reserve `STARTED` metadata is published coherently before externally visible STARTED state;
- `AudioPipePlayoutReserveLifecycleGate` serializes realtime decision and producer reset so stale decisions cannot publish after a new-session reset; realtime claim failure returns immediately without wait/spin/lock;
- default 45 ms, Gate C ring capacity, overflow policy, BLE/ATVV, Gate A/B/C semantics, driver/runtime/install/TCC/Air were unchanged by the corrective.

Executor evidence recorded focused corrective suites `27/27`, full Swift `557/557`, arm64/x86_64 Release builds, protocol self-tests `3/3`, and `git diff --check` passing. This source acceptance does not claim installed/hardware/Air natural-use acceptance.

## Gate E — LOCAL SOURCE HARDENING COMPLETE / WAITING FOR INDEPENDENT WEB AUDIT

The Gate A–D source audit found one real failure-retirement boundary defect and
one missing completion notification in the existing path:

- direct sessions could retain trigger ownership and the remote route after
  BLE/ATVV transport loss when HID had not yet delivered physical UP;
- a MIC_OPEN attempt that received no AUDIO_START could close through the
  existing post-release grace while leaving the direct voice coordinator in
  DRAINING because no stream-stop callback was emitted.

The minimal Gate E correction keeps the existing ownership and drain chain:

- a transport failure is now a terminal retirement boundary for the direct
  session; it withdraws the remote route, waits on the existing output-drain
  callback, and releases the captured trigger at most once even without a
  physical UP edge;
- transport reset notifies the existing connection-loss callback when a voice
  intent was active even if strict READY was never reached;
- a post-release MIC_CLOSE with no active stream emits the existing
  `onStreamingChanged(false)` lifecycle notification, while an active stream
  still waits for the existing AUDIO_STOP/tail retirement path;
- stale output-drain completions remain session-identity guarded and cannot
  release the next direct session.

No classifier, first-PCM/reserve gate, BLE/ATVV protocol change, new queue,
timing change, rebuffering policy, or second diagnostic authority was added.
The accepted Gate A, B, C, and D semantic boundaries remain unchanged.

### Gate E source-audit and verification receipt

- Focused Gate E/direct transport and required regression suites: `144/144` passed.
- Full Swift test suite: `563/563` passed.
- arm64 Release build: passed.
- x86_64 Release build: passed.
- Protocol self-tests: `3/3` passed.
- `git diff --check`: passed.

The source audit and tests cover immediate direct DOWN/profile ownership,
strict-READY MIC_OPEN separation, physical-UP/drain ordering, tail bypass and
actual ring-empty completion, no-AUDIO_START cleanup, OPENING/STREAMING
transport loss, failed-session reset, rapid next-session admission, stale
drain callbacks, Gate D reserve truthfulness, Gate A/B/C, ATVV, 041 diagnostic,
and exporter regressions. This is source/test evidence only; no installed,
hardware, Air, natural-use, packaging, or runtime acceptance is claimed.

The Gate E diff review found no accepted Gate A–D semantic change:

- Gate A: unchanged;
- Gate B: unchanged strict READY/healthy reuse and protocol behavior;
- Gate C: unchanged ring capacity, overflow, realtime, and drain ownership;
- Gate D: unchanged 45 ms default, candidate set, lifecycle gate, and reserve
  diagnostics.

The only changed product paths are failure retirement and its existing
transport lifecycle notification. No merge, tag, release, package/install,
driver, TCC, or Air operation was performed.

## Current authorized gate

`Gate E — End-to-end voice boundary hardening` was authorized for local
construction; that construction and its required verification are now complete.

Gate E is the final source-level boundary gate for 042. It may harden and test the start/end ordering from physical voice edges through trigger ownership, ATVV stream lifecycle, Gate D reserve, Gate C ring drain, and final trigger release. It must not redesign accepted Gate A-D architecture or introduce new buffering/transport policy.

The required product boundary remains:

```text
VOICE DOWN
→ same-session profile/trigger ownership established
→ receiver trigger DOWN is not gated on first PCM/reserve
→ ATVV MIC_OPEN requested through strict READY transport
→ AUDIO_START / decode / PCM submission
→ Gate D startup reserve
→ CoreAudio playout

VOICE UP
→ DRAINING
→ existing BLE post-release/audio-stop retirement completes
→ remote route becomes inactive
→ reserve tail-bypass if still waiting
→ Gate C ring drains to actual empty
→ same captured trigger UP
→ IDLE
```

No merge/tag/release/install/TCC/Air mutation is authorized in Gate E. After local implementation and verification, push the same branch and stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`.

## Stop / next

Gate E implementation and required verification are complete on the canonical
writer. Commit and push only this bounded Gate E correction, verify exact local
and remote equality, then remain stopped at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`
for a fresh independent Web/code audit of the Gate E head.

Do not begin another gate. Do not merge, tag, release, package/install, mutate
TCC, or change Air runtime.
