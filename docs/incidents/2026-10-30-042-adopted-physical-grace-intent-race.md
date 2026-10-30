# RO-VOICE-PIPELINE-SIMPLIFICATION-042 — Adopted Physical Grace Intent Race

Date: 2026-10-30
Task: `RO-VOICE-PIPELINE-SIMPLIFICATION-042`
Installed candidate: `0.2.14 (43)`
Accepted corrective source: `7dfd2e0c9ab71d3fa437be9b4c5cfac1282d9b1c`

## Human observation

The Physical-HTT admission corrective first passed six consecutive RC003 voice sessions. During later high-frequency open/close use, Doubao still opened and displayed waveform activity but speech stopped reaching recognition.

## Fresh runtime evidence

The final known-good session was `B1E3BCE5-5BE7-4146-B145-90B090CA1760`, stream `60`:

- `AUDIO_START reason=0x03`, `session_origin=PHYSICAL_HTT`;
- matching HID session admitted;
- route active;
- `AUDIOPIPE_SUMMARY`: 126 render callbacks, 46,080 filled frames;
- BLE decoded 15,360 non-zero/credible samples;
- physical release started the 1,000 ms post-release grace;
- AUDIO_STOP drain completed and coordinator returned idle.

The next stream `61` arrived before that old grace had retired its BLE voice intent:

- `AUDIO_START reason=0x03`, `session_origin=UNKNOWN`;
- `ATVV streaming=true` was published while coordinator was idle/routed=false;
- matching HID session `85E7` was rejected `voice_session_busy`;
- BLE still decoded 27,600 samples with no decode rejects;
- `AUDIOPIPE_SUMMARY`: render_callback_count=0, render_filled_frames=0, routed path inactive.

Subsequent failing streams repeated the same admission/routing failure.

## Source explanation

`ATVVKeepAliveTelemetry.sessionOrigin()` returns:

- `HOST_MIC_OPEN` when `micOpenRequested == true`;
- `UNKNOWN` when `micOpenRequested == false && voiceInputRequested == true`;
- `PHYSICAL_HTT` when both are false.

The first Physical-HTT corrective maps `UNKNOWN` to session-owned streaming. After an adopted physical stream, `stopVoiceInputOnBLEQueue()` starts post-release grace because `voiceInputRequested` is still true even though no host MIC_OPEN was sent. If the healthy AUDIO_STOP drain finishes before that grace expires, the coordinator may already be idle while the BLE transport still carries stale `voiceInputRequested=true`.

A rapid next physical AUDIO_START therefore becomes `UNKNOWN` and is incorrectly published as session-owned before its HID DOWN, recreating `voice_session_busy`.

The grace expiration stale-session guard only reports/cancels the stale callback and returns; it is not the correct place to clear an intent that may by then belong to a different session.

## Evidence-supported corrective boundary

Do not broadly reclassify every UNKNOWN stream.

For an adopted physical stream only, after all of the following are true:

1. original stream origin is `PHYSICAL_HTT`;
2. no host `MIC_OPEN` was issued for that stream;
3. physical release has occurred and post-release grace is waiting;
4. healthy AUDIO_STOP tail/drain has completed;

retire the old BLE voice intent immediately, cancel the obsolete grace, and retain Gate B READY.

This must not change host-MIC_OPEN grace/MIC_CLOSE behavior, long-lived READY, strict READY, Gate C ring, Gate D 45 ms reserve, ATVV framing/codec, driver/TCC, or trigger/tail/output-drain semantics.

## Required regression evidence

- adopted physical release + AUDIO_STOP drain retires `voiceInputRequested` before the former grace deadline;
- READY remains reusable;
- rapid next physical AUDIO_START during the former grace window classifies/adopts normally and matching HID is admitted;
- host-MIC_OPEN session still preserves existing post-release grace and MIC_CLOSE;
- AUDIO_STOP before physical release does not prematurely retire intent;
- stale grace callback cannot mutate the next session;
- repeated rapid sessions remain admissible and render audio.
