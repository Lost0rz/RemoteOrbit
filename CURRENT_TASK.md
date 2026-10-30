# RemoteOrbit Current Task

## RO-VOICE-PIPELINE-SIMPLIFICATION-042 — Fresh Runtime Incident Evidence Capture

Status: `HUMAN_CORRECTIVE_RUNTIME_RETEST_FAILED / FRESH_INCIDENT_EVIDENCE_REQUIRED`

Repository: `Lost0rz/RemoteOrbit`
Active branch: `codex/voice-pipeline-simplification-042`
Accepted corrective source: `7dfd2e0c9ab71d3fa437be9b4c5cfac1282d9b1c`
Installed candidate: `0.2.14 (43)`
Frozen 041 observability baseline: `ac3132986197bfee4440bb8f388e3d2e5f478f03`

## Observation

The corrective candidate first passed six consecutive human RC003 voice sessions. During later frequent open/close testing, a new failure appeared:

- Doubao still opens;
- waveform is visible;
- speech audio is no longer captured / recognized.

This is not the previous no-waveform Physical-HTT admission failure. Root cause is UNKNOWN.

## Objective

Preserve and inspect the fresh failed runtime window using existing read-only evidence. Determine the first failed or contradictory boundary among:

1. session/trigger admission;
2. `MIC_OPEN` / `AUDIO_START`;
3. BLE audio frame ingress;
4. ADPCM decode and whether decoded PCM is non-zero/credible;
5. AudioPipe feed/submission and queue depth;
6. Gate D reserve start/tail-bypass;
7. CoreAudio render callbacks and whether rendered remote frames/samples are non-zero;
8. virtual microphone / consumer-side readiness where already observable.

The immediate decision is whether the failure is transport/content, AudioPipe/render, or downstream virtual-mic consumption.

## Authorized work

Evidence capture/diagnosis only:

- preserve the currently running failed candidate state;
- use the existing installed `diagnostics status`, `diagnostics verify`, and `diagnostics export` path;
- copy the current `~/Library/Logs/RemoteOrbit/RemoteOrbit.log` if present;
- inspect existing journal/runtime evidence for the fresh failure window;
- compare the six successful corrective sessions against the first failed post-smoke session if timestamps/events allow;
- classify the minimum evidence-supported fault boundary;
- if existing evidence is insufficient, identify exactly one missing fact and one minimum probe, then STOP before adding it.

## Explicitly not authorized

Do NOT:

- modify product source/tests/package scripts;
- restart RemoteOrbit merely to clear the symptom;
- disconnect/reconnect RC003/ATVV merely to clear the symptom;
- reinstall/repackage;
- reset TCC;
- replace/reload the CoreAudio driver;
- change Gate B long-lived READY/strict READY;
- change Gate C ring;
- change Gate D 45 ms reserve;
- change ATVV protocol/codec;
- merge/tag/release/publish;
- create Gate F;
- add probes before proving one missing fact requires them.

## Immediate evidence capture

Run against the currently installed failed runtime:

```bash
mkdir -p ~/Desktop/RemoteOrbit-Incident-042-AudioSilent

"/Applications/RemoteOrbit.app/Contents/MacOS/RemoteOrbit" diagnostics status
"/Applications/RemoteOrbit.app/Contents/MacOS/RemoteOrbit" diagnostics verify
"/Applications/RemoteOrbit.app/Contents/MacOS/RemoteOrbit" diagnostics export \
  --output ~/Desktop/RemoteOrbit-Incident-042-AudioSilent \
  --host-role controller

cp ~/Library/Logs/RemoteOrbit/RemoteOrbit.log \
  ~/Desktop/RemoteOrbit-Incident-042-AudioSilent/ 2>/dev/null || true
```

Do not restart before capture.

## Return contract

Return only observed evidence:

- candidate PID/path/version if still observable;
- export artifact path/name;
- diagnostic verify result;
- failure-window timestamps if available;
- last successful session before failure;
- first failed session;
- `MIC_OPEN` / `AUDIO_START` presence;
- BLE frame/sample counts;
- decode reject/error counts;
- decoded PCM content evidence if existing diagnostics expose it;
- AudioPipe submitted/queued/rendered frame counts;
- reserve state/start reason;
- underrun/starvation counts;
- transport reset/loss events;
- virtual-mic/IOProc readiness evidence already present;
- factual first-missing/contradictory boundary, or `UNKNOWN` if evidence cannot discriminate;
- one minimum missing fact/probe only if needed.

Stop after evidence capture/diagnosis. No product correction is authorized yet.
