# RemoteOrbit Current Task

## RO-VOICE-PIPELINE-SIMPLIFICATION-042 — Runtime Audio-No-Waveform Incident Diagnosis

Status: `HUMAN_RUNTIME_ACCEPTANCE_FAILED / INCIDENT_EVIDENCE_REQUIRED`

Repository: `Lost0rz/RemoteOrbit`
Active branch: `codex/voice-pipeline-simplification-042`

Frozen evidence baseline: `ac3132986197bfee4440bb8f388e3d2e5f478f03`
Accepted source candidate: `2d09b6d77f9f75aa46bb4a13838cd22d5589f524`
Installed candidate: `0.2.14 (43)`, Bundle ID `com.lost0rz.RemoteOrbit`

## Objective

Determine the first failed runtime boundary for the human-observed candidate regression:

- voice key invokes Doubao successfully;
- Doubao shows no audio waveform / no usable remote-microphone audio.

Root cause is UNKNOWN. This task currently authorizes evidence capture and diagnosis only, not a product fix.

## Current incident hypothesis boundary

The trigger/IME path is proven alive by the human observation. The first missing fact is where the remote-audio chain stops:

```text
VOICE DOWN / trigger ownership
→ strict READY / MIC_OPEN request
→ AUDIO_START
→ BLE audio notifications
→ ATVV decode
→ PCM submit / AudioPipe feed
→ Gate D reserve start or tail bypass
→ CoreAudio render / RemoteOrbit Mic
```

The next decision depends on identifying the first absent or contradictory stage in the failed runtime session.

## Authorized work

1. Preserve the currently installed candidate and failed runtime evidence.
2. Use the existing read-only DiagnosticAuthority CLI only.
3. Verify diagnostic storage is readable.
4. Export the existing bounded diagnostic evidence bundle from the failed runtime window; a full current bounded export is acceptable if the exact failure timestamps are not yet known.
5. Query/snapshot existing events only as needed to establish whether the failed session contains:
   - trigger/session opening evidence;
   - `MIC_OPEN` request/transmit evidence;
   - `AUDIO_START`;
   - BLE audio ingress / frame continuity evidence;
   - decoded/submitted PCM evidence;
   - reserve start/tail-bypass evidence;
   - rendered/underrun/output-drain evidence;
   - transport reset/loss evidence.
6. Return the evidence bundle and a factual first-missing-boundary classification if supported.
7. If existing evidence cannot discriminate the boundary, name exactly one missing fact and the minimum probe that would resolve it; stop before adding the probe.

## Explicitly not authorized

Do NOT:

- modify product source or tests;
- change Gate A-E semantics;
- change the 45 ms reserve;
- change BLE/ATVV, AudioPipe, ring, driver, mappings, or profile behavior;
- rebuild, repackage, reinstall, or replace the candidate before preserving current evidence;
- restart the candidate merely to clear the symptom unless evidence capture is impossible otherwise;
- reset TCC;
- reinstall/reload the CoreAudio driver;
- merge, tag, release, publish, or create Gate F;
- add probes/instrumentation before proving the existing diagnostics are insufficient;
- claim a root cause from the symptom alone.

## Immediate evidence commands

Use the installed binary's read-only diagnostic CLI:

```bash
/Applications/RemoteOrbit.app/Contents/MacOS/RemoteOrbit diagnostics status
/Applications/RemoteOrbit.app/Contents/MacOS/RemoteOrbit diagnostics verify
mkdir -p ~/Desktop/RemoteOrbit-Incident-042
/Applications/RemoteOrbit.app/Contents/MacOS/RemoteOrbit diagnostics export --output ~/Desktop/RemoteOrbit-Incident-042 --host-role controller
```

The CLI has no restart/reset/repair/install/clear side effects.

## Evidence decision table

Classify only what the evidence supports:

- `MIC_OPEN` absent → Gate B/session-intent/READY handoff boundary.
- `MIC_OPEN` present but `AUDIO_START` absent → ATVV remote/control-stream startup boundary.
- `AUDIO_START` present but no BLE audio ingress → notification/transport delivery boundary.
- BLE audio ingress present but no decode/PCM submit → decode/submission boundary.
- PCM submit present but no reserve/render → AudioPipe/reserve/render boundary.
- render present but Doubao still has no waveform → virtual-device/consumer routing boundary.

These are classification buckets, not root-cause claims.

## Completion / stop state

Stop after evidence capture and classification at one of:

- `INCIDENT_BOUNDARY_IDENTIFIED / WAITING_FOR_CORRECTIVE_AUTHORIZATION`, or
- `INCIDENT_EVIDENCE_INSUFFICIENT / MINIMUM_PROBE_REQUIRED`.

Do not implement a corrective in the same execution unless Project Governance explicitly re-authorizes source mutation after evidence review.
