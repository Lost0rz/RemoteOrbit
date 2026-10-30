# Voice Pipeline Gate B Design

**Task:** `RO-VOICE-PIPELINE-SIMPLIFICATION-042`

**Status:** Approved execution design from the authorized Gate B card (`MODE: EXECUTE`)

## Intent

Separate long-lived ATVV connection readiness from the Gate A per-press voice stream,
and remove CoreBluetooth notification ingestion from the AppKit/main scheduling domain.
The change must keep the existing ATVV protocol and decode path, Gate A release ordering,
041 observability, and AudioPipe data-plane contract attributable and unchanged.

## Verified constraints

- The live control branch is `codex/voice-pipeline-simplification-042` at Gate B control
  transition `4b742848457448308efb0f60e480fa400ca12eab`.
- Gate A's audited semantic head is `50b1d9efabe15f04d5479b39af227d0e6f43a4e3`.
- `BLEBridge` currently creates `CBCentralManager` with `.main`, stores transport and
  stream state in one class, and schedules normal post-release teardown that cancels the
  peripheral connection.
- `AudioPipe.feed(samples:)` is an existing thread-safe producer boundary and is not a
  Gate B data-plane redesign target.
- CoreBluetooth delegate callbacks must be owned by one dedicated serial queue; main/UI
  callbacks may be asynchronous observations/control notifications only.

## Goals

- Model transport as `DISCONNECTED -> CONNECTING -> READY` and voice stream as the
  existing `IDLE -> OPENING -> STREAMING -> DRAINING -> IDLE` lifecycle.
- Preserve a healthy prepared peripheral, discovered characteristics, notifications,
  and accepted capabilities after a normal per-session `MIC_CLOSE`.
- Allow the next session to send `MIC_OPEN` from READY without repeating connection,
  discovery, subscription, or capability negotiation.
- Run CoreBluetooth delegate handling, notification parsing/decoding, ATVV state
  mutation, timers, and recovery ownership on one serial `bleQueue`.
- Marshal `onStreamingChanged`, `onAudioFrame`, `onConnectionChanged`, level, and
  admission callbacks explicitly to main without making main scheduling a prerequisite
  for notification receipt, decode, or `AudioPipe.feed`.
- Preserve the 350 ms AUDIO_STOP drain barrier, Gate A tail order, stale AUDIO_START
  rejection, bounded genuine-failure recovery, and existing diagnostics.

## Non-goals and anti-goals

- No ATVV command/framing/codec/ADPCM/sample-rate/AUDIO_SYNC semantic change.
- No AudioPipe queue, render callback, lock, gain, resampler, limiter, jitter, or
  playout-reserve change.
- No Gate A profile/menu/trigger redesign and no new user-visible start/tail delay.
- No driver, packaging, installation, TCC, Air runtime, merge, tag, release, or Gate C/D/E
  work.
- Do not retain stale characteristics or capabilities after a genuine disconnect, reset,
  setup failure, notification failure, or explicit shutdown.

## Approaches

### A. Queue-own the existing `BLEBridge` — selected

Create one labeled serial `DispatchQueue` with an appropriate QoS and pass it to
`CBCentralManager`. Keep the existing bridge and protocol handler as the single state
owner, but make public session/test entry points enqueue onto that queue. Replace main
timers that mutate BLE state with queue-owned work items or a queue-owned dispatch timer.
Keep normal stream close separate from `stop()`: send `MIC_CLOSE`, retire the stream after
the existing drain, and leave the READY transport intact. Only explicit shutdown and
genuine transport failures clear the connection state. Main callbacks are small explicit
hops after transport/audio work.

This is the smallest change that satisfies the required ownership boundary, preserves
existing protocol code, and is straightforward to reverse if later evidence requires a
larger transport/session split.

### B. Split transport and voice session into new objects — rejected

This would make the conceptual split visible in types, but would duplicate or migrate a
large amount of existing recovery, diagnostic, and drain ownership in the same gate. It
adds more lifecycle seams than the required evidence can isolate.

### C. Keep CoreBluetooth on main and move only decode — rejected

This leaves delegate callbacks, notification ownership, and transport-state mutation on
the UI queue and therefore fails the Gate B queue and main-isolation contract.

## Ownership and interfaces

- `BLEVoiceTransportState` gains explicit connection lifecycle facts and helpers so READY
  is independent from `voiceInputRequested`/`micOpenRequested`.
- `BLEBridge.bleQueue` is the only production writer domain for `central`, `peripheral`,
  ATVV characteristics/capabilities, protocol stream state, drain barriers, timers, and
  recovery work. The queue is created with `DispatchQueue(label:..., qos: .userInitiated)`
  and passed to `CBCentralManager`.
- `PostReleaseCaptureGraceController` receives an injectable scheduling queue; production
  grace expiry runs on `bleQueue`, while existing tests may retain the main default.
- Decoded PCM is fed directly to the existing `AudioPipe.feed` boundary on `bleQueue`.
  `onAudioFrame` is a main hop after that feed, so UI/voice activation cannot gate decode.
- Normal close clears per-session voice intent and protocol stream state but does not clear
  transport characteristics/capabilities or cancel the healthy peripheral.
- `clearTransportState` remains the fatal/reset/shutdown path and clears READY before
  bounded reconnect logic is scheduled.

## Verification implications

Focused tests will prove the state transition and reuse policy, the dedicated queue
identity, main callback isolation, per-session MIC_OPEN/MIC_CLOSE intent, normal close
preserving READY, genuine reset clearing READY, drain-barrier admission, and stale
AUDIO_START rejection. Existing BLEBridge, ATVV, VoicePipelineSimplification,
VoiceBoundaryOrdering, VoiceTriggerRuntime, AudioPipe, and 041 diagnostic/export tests
remain required unchanged in semantic expectation.

Source/diff inspection will separately verify that no AudioPipe architecture, jitter,
codec/protocol, driver, packaging, installation, runtime, or Gate C/D/E implementation
enters this gate.

## Consequences and reversibility

- The bridge remains a single implementation owner, so queue ownership is explicit but
  not yet a separate transport/session type boundary.
- Normal connection persistence reduces repeated setup work and changes only the normal
  close lifecycle; fatal reset behavior remains available through the existing clear path.
- The queue and READY split can be reverted by restoring main delegate scheduling and the
  old normal-close cancellation path without changing the ATVV protocol or AudioPipe.

**TASK_RECONCILIATION_REQUIRED:** NO

**REASON:** The selected design stays within the authorized Gate B objective and preserves
all forbidden Gate A/C/D/E boundaries.

**DURABLE_DOCUMENT:** This file.
