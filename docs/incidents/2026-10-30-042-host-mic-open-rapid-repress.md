# RO-VOICE-PIPELINE-SIMPLIFICATION-042 — HOST_MIC_OPEN Rapid Re-press Evidence

Date: 2026-10-30
Task: `RO-VOICE-PIPELINE-SIMPLIFICATION-042`
Installed candidate: `0.2.14 (43)`
Accepted corrective source: `b1736f2feedd7ed13e4520ecdfaa0c6bf6e9b332`
Final export: `RemoteOrbit-diagnostics-20261030-135113.tar.gz`

## Archive integrity

`SHA256SUMS` verified every exported file successfully. Diagnostic journal reported zero dropped diagnostic events and zero write failures.

## Stable steady-state evidence

From 13:45:57 UTC through 13:47:53 UTC, 34 consecutive physical sessions are admitted and complete without `voice_session_busy`.

The final 20 completed sessions, 13:46:42–13:47:53 UTC, are exactly:

- 20/20 `admission=admitted`;
- 20/20 `session_origin=PHYSICAL_HTT`;
- 20/20 `adopted active PHYSICAL_HTT stream into voice session`;
- 20/20 BLE decode summaries with non-zero decoded samples, `decode_rejects=0`, `zero_sample_decodes=0`;
- 20/20 AudioPipe summaries with non-zero render callback count and non-zero rendered/filled frames;
- 20/20 `POST_RELEASE_GRACE_CANCELLED ... reason=adopted_physical_audio_stop` followed by `adopted PHYSICAL_HTT voice intent retired after AUDIO_STOP drain; ATVV READY retained`;
- zero `admission=rejected` / `voice_session_busy` in that 20-session window;
- zero transport reset/loss/disconnect, MIC_OPEN error, or AUDIO_STOP timeout in that window.

This validates the second adopted-PHYSICAL corrective in steady-state reuse.

## Hidden rapid-repress failures before steady state

### Sequence A — `09B0`

Host session `C8AAD51D-E665-44A5-AC4D-2C9D201A6154` starts at 13:45:49 UTC while BLE is connecting/handshaking and uses HOST_MIC_OPEN. It renders normally, receives AUDIO_STOP, drains, closes its pipeline, and turns route off. Its 1-second post-release grace still retains the host voice request.

Immediately afterward, the remote emits a new physical `AUDIO_START reason=0x03` (stream 76) while the old host state is still present. The log classifies this stream as `session_origin=HOST_MIC_OPEN`, publishes session-owned streaming while gesture is idle/routed=false, and matching HID press `09B0` is rejected `voice_session_busy`.

Stream 76 still decodes real PCM (`decoded_samples=25440`, `decode_rejects=0`) but `AUDIOPIPE_SUMMARY` reports `render_callback_count=0`, `render_filled_frames=0` because it never obtains the new session route.

### Sequence B — `BAFD`

Session `8A416474-28E0-4090-BE07-D28206153EA5` is admitted at 13:45:53 UTC through the host path. The user physically releases at 13:45:54 and post-release grace starts. Before that host lifecycle has retired, a new physical `AUDIO_START reason=0x03` (stream 78) arrives at 13:45:55 and is again classified `session_origin=HOST_MIC_OPEN`. Matching HID press `BAFD` is rejected `voice_session_busy`.

The old grace later expires and sends MIC_CLOSE; stream 78 then stops/drains. This is distinct from the already-fixed adopted-PHYSICAL stale-intent race because the stale owner is a HOST_MIC_OPEN session.

## Evidence-supported boundary

The remaining problem is not BLE decode, AudioPipe steady-state rendering, the 45 ms reserve, driver/TCC, or adopted-PHYSICAL retirement.

It is the ownership transition when an explicit physical `AUDIO_START reason=0x03` arrives while an older HOST_MIC_OPEN session has already been physically released but its post-release grace/host request is still active.

Do not broadly reclassify UNKNOWN and do not remove host grace without preserving no-AUDIO-START and MIC_CLOSE semantics.

The next step is state-ownership design reconciliation, specifically how to supersede/retire the old host request without sending a MIC_CLOSE that could target the newly arriving physical stream.
