# CURRENT_STATUS

Last updated: 2026-10-30
State: `RO-VOICE-PIPELINE-SIMPLIFICATION-042 — READY_FOR_LOCAL_GATE_E`
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

## Current authorized gate

`Gate E — End-to-end voice boundary hardening` is now authorized for local construction.

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
