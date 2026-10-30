# RemoteOrbit Current Task

## RO-VOICE-PIPELINE-SIMPLIFICATION-042 — Single-Path Voice Pipeline

Status: `READY_FOR_LOCAL_GATE_B`

Repository: `Lost0rz/RemoteOrbit`

Active branch: `codex/voice-pipeline-simplification-042`

Baseline / frozen evidence parent: `ac3132986197bfee4440bb8f388e3d2e5f478f03`

Gate A audited semantic head: `50b1d9efabe15f04d5479b39af227d0e6f43a4e3`

## Objective

Replace the previous multi-mode voice-key control surface with one deterministic remote-voice path, then simplify the underlying transport/audio architecture gate-by-gate while preserving ATVV protocol correctness and the 041 observability baseline.

Product contract:

```text
VOICE DOWN
→ begin the captured voice-input trigger + remote voice opening immediately

VOICE UP
→ stop remote capture through the existing clean transport/audio drain
→ release the same captured trigger only after already-received output is drained
```

The voice key is transport control, not mode control.

## User / project decisions

1. The voice key has one high-frequency responsibility: remote voice start/stop.
2. No voice-key SHORT/LONG/DOUBLE/Persistent/Receiver-A-B mode on the primary path.
3. Voice-input/IME selection is a low-frequency menu-bar `VoiceInputProfile` action.
4. A session captures one profile/trigger identity and cannot switch it mid-session.
5. Primary optimization target is complete, stable Xiaomi RC003 audio delivery to the selected voice input, especially start, active continuity, and clean tail behavior.
6. Structural transport/audio changes must be separated into evidence-bounded gates so improvements/regressions remain attributable.

## Retained evidence / compatibility authority

- Keep existing ATVV v0.4/v1.0 protocol behavior unless new evidence proves a protocol defect.
- Keep 041 `voice_attempt_id`, BLE/decode/PCM/render ordering evidence, underrun episodes, runtime health, DiagnosticAuthority, bounded trace, DiagnosticExporter, and privacy limits.
- Keep historical 041 evidence as a before/after baseline; do not reinterpret old observations as proof of a new root cause.
- Do not add another always-on diagnostic ring or duplicate diagnostic authority.
- Human natural-use/UI acceptance remains owner-owned and cannot be replaced by machine interaction.

## Gate A — CLOSED / INDEPENDENT AUDIT PASS

Accepted semantic head: `50b1d9efabe15f04d5479b39af227d0e6f43a4e3`.

Independent Web `CODE_DIFF` audit accepted the Gate A boundary after the tail-order corrective:

- production DOWN does not wait for the 300 ms classifier;
- the production microphone path uses one direct session lifecycle;
- one `VoiceInputProfile`/trigger identity is captured per session;
- Persistent and receiver A/B voice paths are not production microphone authorities;
- physical UP enters `DRAINING`, arms release ownership, and requests the existing BLE stop flow while the AudioPipe remote route remains active;
- existing BLE post-release grace + AUDIO_STOP drain completes before remote route deactivation/output drain;
- captured trigger UP occurs only after output drain;
- no-audio-start, transport-loss, rapid-next-session, and hardware-trigger release paths have focused coverage;
- the tail corrective did not modify `BLEBridge.swift`, `AudioPipe.swift`, ATVV protocol, driver, packaging, installation, or Air runtime.

Recorded executor verification at that semantic head: full Swift tests 510/510, focused voice/BLE/ATVV/AudioPipe/diagnostic suites pass, arm64 and x86_64 release builds pass, protocol self-tests 3/3, and `git diff --check` pass.

This Gate A source acceptance does not claim installed/Air natural-use acceptance or final release readiness.

## Gate B — Long-lived ATVV transport + dedicated BLE ingestion queue — AUTHORIZED

### Goal

Separate ATVV connection readiness from voice-stream lifetime and remove CoreBluetooth ingestion from the UI/control scheduling domain, without changing ATVV protocol semantics or the AudioPipe data plane.

### Required target model

Transport lifetime:

```text
DISCONNECTED
→ CONNECTING
→ READY
```

Voice-stream lifetime remains owned by the Gate A direct session:

```text
IDLE
→ OPENING
→ STREAMING
→ DRAINING
→ IDLE
```

Normal successful voice release must close the ATVV voice stream but keep the prepared connection/discovery/subscription/capability state `READY` for the next press where the device/CoreBluetooth state permits.

A real disconnect, Bluetooth power/state change, notification/service failure, explicit app shutdown, or other existing fatal transport condition may leave `READY` and use bounded reconnect/recovery logic.

### Authorized work

1. Refactor `BLEVoiceTransportState`/`BLEBridge` so connection/discovery/subscription/capability readiness is app/transport lifecycle state rather than normal per-press teardown state.
2. Preserve `MIC_OPEN` / `MIC_CLOSE` as per-voice-session operations.
3. Preserve the existing physical-UP post-release grace and AUDIO_STOP drain semantics while detaching them from normal peripheral disconnect.
4. Keep the connection ready after normal session completion instead of scheduling `cancelPeripheralConnection` merely because one voice press ended.
5. Ensure the next direct voice press can request `MIC_OPEN` against an already-ready transport without repeating connect/service/characteristic/capability setup.
6. Move `CBCentralManager` delegate and associated peripheral notification ingestion from `.main` to one dedicated serial BLE queue with an appropriate QoS.
7. Keep BLE/ATVV transport state mutation serialized on that queue. Do not introduce concurrent writers to `BLEBridge` state.
8. Marshal only bounded state/UI callbacks to the main queue when main-thread ownership is required. Audio notification parse/decode must not depend on main-queue scheduling.
9. Preserve the existing decode path and `AudioPipe.feed` contract for Gate B; do not redesign the PCM/render data plane yet.
10. Adapt diagnostics/tests only as required to truthfully distinguish transport readiness from per-session streaming state.
11. Preserve safe reconnect after genuine disconnect/failure, sleep/wake/Bluetooth transitions insofar as the existing implementation already handles them; do not weaken current recovery in order to keep a connection alive.
12. Preserve one canonical writer and push only the authorized 042 branch.

### Gate B state/ownership requirements

- `READY` means required ATVV characteristics are discovered/subscribed and capabilities accepted.
- `voiceInputRequested`/`micOpenRequested` are session intents, not connection-lifetime authorities.
- Normal `VOICE UP` must not set transport `isStarted=false` or clear discovered characteristics solely because a voice session ended.
- Normal post-release completion must leave the transport reusable if the peripheral remains connected/healthy.
- Fatal/reset paths must still clear stale characteristic/capability state before reconnect.
- `onStreamingChanged(false)` must continue to represent the completed current stream/tail boundary used by Gate A; moving queues must not make trigger release occur before the BLE/audio drain boundary.
- `onVoiceSessionAdmissionAvailable` or its truthful successor must remain ordered after the previous AUDIO_STOP drain barrier retires.
- Main-thread UI callbacks must never become a prerequisite for receiving/decoding the next BLE audio notification.

### Gate B forbidden changes

Do NOT in Gate B:

- change ATVV command bytes, command ordering required by the protocol, codec selection, ADPCM decoder semantics, sample rate, AUDIO_SYNC behavior, gain, or resampling;
- change AudioPipe queue representation, queue capacity, `NSLock`/render architecture, CoreAudio callback implementation, underrun correction, or local-mic/audio routing semantics except the minimum call-site queue hop required for thread correctness;
- add/tune a jitter buffer or multi-frame playout reserve;
- redesign Gate A `VoiceInputProfile`, menu UX, direct voice-key semantics, or trigger ownership;
- change the user-visible start/tail policy beyond preserving the existing Gate A ordering;
- add a new diagnostic authority/ring or expand privacy-sensitive logging;
- change virtual audio driver behavior;
- package/install/replace `/Applications/RemoteOrbit.app`, reload CoreAudio, mutate TCC, or alter Air runtime;
- merge, tag, release, close preserved PRs, or mutate historical 039/040/041 branches;
- begin Gate C/D/E automatically.

If a safe dedicated BLE queue requires a small explicit main-queue hop at an AppKit/HUD/configuration boundary, that is inside Gate B. If it appears to require AudioPipe architecture changes, STOP and report the dependency instead of silently entering Gate C.

## Gate B verification requirements

At minimum prove:

1. exact starting live branch/head and clean canonical writer;
2. normal first session reaches READY and streams successfully through the unchanged ATVV/decode/AudioPipe contract;
3. normal session release completes post-release grace + AUDIO_STOP drain + Gate A output drain without disconnecting the healthy peripheral;
4. after normal session completion, transport remains/re-enters READY with characteristics/capabilities reusable;
5. a second session from READY requests MIC_OPEN without repeating connect/service discovery/characteristic discovery/capability negotiation;
6. genuine disconnect/failure clears stale transport state and can use the existing bounded reconnect path;
7. no stale `AUDIO_START` from the previous stream is accepted across the drain barrier;
8. CoreBluetooth delegate/notification ingestion runs on the dedicated serial BLE queue rather than `.main`;
9. UI/control callbacks that require main-thread ownership are marshalled explicitly and do not block audio ingestion;
10. BLE transport state has one serialized writer domain and no newly introduced cross-queue data race is evident in code/tests;
11. Gate A tail ordering remains intact: remote route stays eligible through transport/audio-stop completion, output drain follows, captured trigger UP remains last;
12. rapid sequential sessions behave deterministically across READY/stream drain boundaries;
13. existing ATVV protocol tests pass unchanged in semantic expectation;
14. existing AudioPipe focused tests pass without AudioPipe architecture changes;
15. existing 041 diagnostic/exporter/continuity tests remain truthful;
16. full Swift tests, arm64 release build, x86_64 release build, protocol self-tests, and `git diff --check` pass in the established repository flow;
17. final diff proves no Gate C/D/E implementation leaked into Gate B.

## Gates C–E — PLANNED / NOT AUTHORIZED

### Gate C — Realtime-safe audio data plane

Design intent only: fixed-capacity SPSC PCM ring, preallocated CoreAudio render path, no ordinary blocking lock/dynamic Array growth or compaction on the realtime callback, retained bounded counters/traces.

### Gate D — Small measured jitter reserve

Design intent only: after Gate C, evaluate the smallest reserve that absorbs observed 30–80 ms arrival jitter without material dictation latency; permanent delivery deficit remains a separate problem.

### Gate E — Start/tail boundary convergence

Design intent only: receiver/trigger ready no later than audio start, event-driven tail convergence with bounded safety timeouts, no avoidable RemoteOrbit truncation.

No Gate C/D/E mutation is authorized by the current task phase.

## Gate B completion / stop state

After Gate B implementation and verification:

- update `CURRENT_STATUS.md` and `CURRENT_TASK.md` together;
- commit all authorized Gate B changes;
- push only `codex/voice-pipeline-simplification-042` and verify remote identity;
- stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`;
- do not begin Gate C automatically;
- do not merge, tag, release, install, mutate TCC, or change the Air runtime.
