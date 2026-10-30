# RO-VOICE-PIPELINE-SIMPLIFICATION-042 runtime incident

Date: 2026-10-30
Status: boundary identified; corrective authorized by CURRENT_TASK.md

## Human symptom

Installed candidate 0.2.14 (43) invokes the configured Doubao input-method trigger, but Doubao shows no audio waveform / no usable remote microphone audio.

## Evidence

Candidate source remains `2d09b6d77f9f75aa46bb4a13838cd22d5589f524` with only control-only descendants.

The preserved runtime evidence shows two distinct phases:

1. The first routed attempt is admitted, sends host `MIC_OPEN`, receives `AUDIO_START`, then retires normally.
2. Once the Gate B long-lived ATVV transport remains READY, later physical voice presses commonly produce `AUDIO_START reason=0x03 session_origin=PHYSICAL_HTT` before the matching HID key-down is admitted.

For those later presses:

- BLE reports `AUDIO_START` first with `session_origin=PHYSICAL_HTT`.
- `BLEBridge` marks its internal stream active and calls `notifyStreaming(true)`.
- the main callback forwards that as `voicePress.setRemoteStreaming(true)`.
- `VoicePressCoordinator.hasReleaseOrTailOwnershipForReconfiguration` includes `remoteStreaming`.
- the matching HID press is therefore rejected as `admission=rejected reason=voice_session_busy`.
- no direct session owns the route, so `AudioPipe.remoteActive` remains false.
- BLE notifications and ADPCM decode can still succeed; the WAV recorder proves decoded PCM is present.
- `AudioPipe.feed` sees an inactive remote route and only retains bounded candidate pre-roll; CoreAudio stays in idle rendering and Doubao receives no remote PCM.

Representative preserved samples include streams with decoded audio such as:

- stream 35: 84 frames / 20,160 samples / 1,260 ms decoded audio;
- stream 36: 74 frames / 17,760 samples / 1,110 ms decoded audio;
- stream 44: 115 frames / 27,600 samples / 1,725 ms decoded audio.

The corresponding `AUDIOPIPE_SUMMARY` records `render_callback_count=0`, `render_filled_frames=0`, reserve still `waiting_for_reserve`, while idle callbacks continue. This proves CoreAudio itself is alive but the remote route is not owned/activated.

During the preserved window, the first admitted press is followed by repeated `voice_session_busy` rejections while physical-HTT streams continue to arrive and decode.

## Root cause

Confirmed source/runtime ordering defect:

`PHYSICAL_HTT AUDIO_START before HID key-down`

is incorrectly treated as prior-session/release ownership instead of pre-HID transport/pre-roll for the same physical press.

Gate B's long-lived READY transport exposes this ordering: Gate A previously closed the ATVV transport after a voice session, whereas Gate B intentionally retains READY. With notifications already subscribed, the remote can now deliver the physical-HTT control/audio stream before the HID path reaches direct-session admission.

## Corrective boundary

Preserve long-lived READY transport and pre-HID PCM capture, but separate transport-level pre-HID streaming from session-owned streaming.

Required behavior:

- pre-HID `PHYSICAL_HTT` may begin decoding and bounded pre-roll;
- it must not by itself make the matching HID press fail `voice_session_busy`;
- once the matching HID press is admitted, the existing physical stream must be adopted/bound to that session and the remote route activated;
- do not send a duplicate host `MIC_OPEN` when an already-active physical stream is adopted;
- after adoption, ordinary streaming/retirement/tail semantics remain Gate A-E compatible;
- stale or unrelated streams must still remain admission blockers where required.

No broader redesign is authorized by this incident record.
