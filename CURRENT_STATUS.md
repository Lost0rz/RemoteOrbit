# CURRENT_STATUS

Last updated: 2026-10-30
State: `RO-VOICE-PIPELINE-SIMPLIFICATION-042 — WAITING_FOR_INDEPENDENT_WEB_AUDIT`
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

## Gate C — LOCAL IMPLEMENTATION COMPLETE

Gate C replaced only the decoded-PCM → CoreAudio data plane with one
preallocated `FixedCapacityPCMFrameRing` and an off-path diagnostic mailbox.
The ring capacity is 96,000 frames at the existing 48 kHz output rate: a
structural bound matching the previous two-second maximum queue, not a
startup reserve, jitter threshold, or intentional playout delay. The ring
starts empty and rejects newest input when full without overwriting unread
PCM.

The producer remains the existing serialized AudioPipe submission path after
the existing gain/limiter/resampling. The CoreAudio callback reads directly
into the supplied `AudioBufferList`, zero-fills only a true suffix underflow,
and publishes bounded scalar evidence. It does not acquire `stateLock`,
allocate a sample array, mutate a dynamic PCM queue, format/log/I/O, or
dispatch/wait. Output drain is signaled only by inactive route plus actual
ring emptiness; normal tail PCM is retained, while activation/reset clears
stale PCM before a new session.

Existing counters and 041 continuity/export evidence are merged off-path;
`compaction_count` remains present and is frozen at zero because compaction no
longer exists. No BLE/ATVV/codec/gain/limiter/resampling, Gate A/B, jitter,
driver, packaging, install, TCC, Air runtime, merge, tag, or release behavior
was changed.

### Gate C verification receipt

- Focused Gate C/regression suites: `196/196` passed.
- Full Swift test suite: `534/534` passed.
- Protocol self-tests: `3/3` passed.
- arm64 Release build: passed.
- x86_64 Release build: passed.
- `git diff --check`: passed.
- Canonical writer: `/private/tmp/remoteorbit-voice-pipeline-simplification-042`.
- Audited parent: `8fe9c5f9e0fcc29b769892fa6e4fa0daa1462c01`; this control transition is its direct child.

### Changed paths

- `remote-orbit/Sources/RemoteOrbit/AudioPipe.swift`
- `remote-orbit/Sources/RemoteOrbit/AudioPipeRealtime.swift`
- `remote-orbit/Tests/RemoteOrbitTests/AudioPipeTests.swift`
- `remote-orbit/Tests/RemoteOrbitTests/AudioPipeRealtimeTests.swift`
- `docs/superpowers/specs/2026-10-30-voice-pipeline-gate-c-design.md`
- `docs/superpowers/plans/2026-10-30-voice-pipeline-gate-c.md`

## Stop / next

The Gate C implementation is delivered on this branch and is now stopped at
`WAITING_FOR_INDEPENDENT_WEB_AUDIT`. Independent Web/code audit is still
required; local tests and builds do not claim natural-use, installed-runtime,
TCC, hardware, or Air acceptance.

Do not begin Gate D/E automatically. Do not merge, tag, release, install,
mutate TCC, or change the Air runtime.
