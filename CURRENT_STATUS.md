# CURRENT_STATUS

Last updated: 2026-10-30
State: `RO-VOICE-PIPELINE-SIMPLIFICATION-042 — READY_FOR_LOCAL_GATE_C`
Repository: `Lost0rz/RemoteOrbit`

## Current authority

- Active branch: `codex/voice-pipeline-simplification-042`.
- `AGENTS.md` remains the durable repository rule authority.
- `CURRENT_TASK.md` is the sole active execution authorization.
- Frozen 041 evidence baseline: `ac3132986197bfee4440bb8f388e3d2e5f478f03`.
- Gate A accepted semantic head: `50b1d9efabe15f04d5479b39af227d0e6f43a4e3`.
- Gate B accepted semantic head: `ae0bf10874d34ce556b4b73a506b22f6a9a1a412`.

## Gate A — CLOSED / INDEPENDENT AUDIT PASS

The production microphone key is single-purpose transport control:

`DOWN → OPENING → STREAMING → DRAINING → IDLE`

There is no production SHORT/LONG/DOUBLE/Persistent/Receiver-A-B voice mode. One `VoiceInputProfile` is captured per session. Physical UP preserves the remote route through the BLE/audio-stop tail boundary; queued output drains before the same trigger is released.

## Gate B — CLOSED / INDEPENDENT AUDIT PASS

Independent Web `CODE_DIFF` audit accepted Gate B at `ae0bf10874d34ce556b4b73a506b22f6a9a1a412`.

Accepted source properties:

- CoreBluetooth delegate/notification ingestion and BLE/ATVV state mutation are serialized on dedicated `com.remoteorbit.ble`.
- UI/control callbacks that require main ownership are explicitly marshalled to main; BLE decode and `AudioPipe.feed` do not wait for main.
- Transport lifetime is separated from per-press stream lifetime; a healthy transport remains READY across normal voice sessions.
- READY is strict: all three required ATVV characteristics discovered + audio/control notify subscriptions positively confirmed + capabilities accepted.
- One idempotent readiness evaluator owns the READY transition; MIC_OPEN is additionally guarded by strict reusable READY.
- Normal close preserves READY facts; genuine reset/failure clears stale readiness/characteristic state.
- Existing post-release grace, 350 ms AUDIO_STOP drain, stale-AUDIO_START admission barrier, Gate A tail ownership, ATVV protocol semantics, and 041 diagnostics remain intact.
- Gate B did not change the AudioPipe/CoreAudio data-plane architecture or jitter policy.

Recorded executor verification at the accepted Gate B head: BLE strict-readiness tests 28/28; full Swift tests 521/521; arm64 and x86_64 release builds pass; protocol self-tests 3/3; `git diff --check` pass.

Human natural-use, installed runtime/TCC, and Air acceptance remain pending and are not implied by the source audit.

## Current authorized gate

`Gate C — Realtime-safe audio data plane` is now authorized for local construction.

Gate C is limited to replacing the current dynamic/locking PCM queue/render path with a fixed-capacity single-producer/single-consumer data plane and a preallocated realtime render path while preserving audio semantics and diagnostics.

Gate C must not change BLE connection/queue/readiness behavior, ATVV protocol/codec, gain/resampling policy, jitter reserve policy, Gate A control semantics, start/tail user policy, driver, packaging/install/TCC/Air runtime, merge/tag/release, or historical branches.

## Stop / next

Local construction must fetch this branch, read `AGENTS.md`, this file, and `CURRENT_TASK.md`, reuse one canonical writer, execute Gate C only, push the same branch, and stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`.

Do not begin Gate D/E automatically.
