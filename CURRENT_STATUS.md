# CURRENT_STATUS

Last updated: 2026-10-30
State: `RO-VOICE-PIPELINE-SIMPLIFICATION-042 — SECOND_RUNTIME_INCIDENT_BOUNDARY_IDENTIFIED / READY_FOR_LOCAL_CORRECTIVE`
Repository: `Lost0rz/RemoteOrbit`

## Current authority

- Active branch: `codex/voice-pipeline-simplification-042`.
- Accepted corrective source before the second runtime incident: `7dfd2e0c9ab71d3fa437be9b4c5cfac1282d9b1c` — independent CODE_DIFF audit PASS.
- Installed corrective candidate: `0.2.14 (43)`.
- Frozen 041 observability baseline: `ac3132986197bfee4440bb8f388e3d2e5f478f03`.
- Incident record: `docs/incidents/2026-10-30-042-adopted-physical-grace-intent-race.md`.
- `AGENTS.md` remains durable repository authority.
- `CURRENT_TASK.md` is the sole active execution authorization.

## Confirmed second incident boundary

The prior corrective passed six consecutive RC003 sessions. In later rapid open/close use, fresh evidence showed that a healthy adopted physical session could finish AUDIO_STOP and return the coordinator to idle while the BLE post-release grace still retained `voiceInputRequested=true`.

The next physical AUDIO_START therefore observed `micOpenRequested=false && voiceInputRequested=true`, became `session_origin=UNKNOWN`, was published as session-owned streaming, and caused the matching HID DOWN to be rejected `voice_session_busy`. BLE still decoded credible non-zero PCM while AudioPipe remained unrouted with zero render callbacks.

This is an admission/lifecycle race, not a downstream PCM/virtual-mic silence defect.

## Corrective boundary

Do not broadly reclassify UNKNOWN.

For an adopted physical stream only, after physical release and healthy AUDIO_STOP tail/drain completion, retire the stale BLE voice intent and obsolete grace immediately while retaining Gate B READY. Host-MIC_OPEN grace/MIC_CLOSE behavior must remain unchanged.

Preserve strict READY, long-lived READY, ATVV protocol/codec, Gate C ring, Gate D 45 ms reserve, trigger/tail/output-drain ordering, driver and TCC policy.

No additional probe is required.

## Stop / next

Execute only the bounded corrective in `CURRENT_TASK.md`; push the existing 042 branch and stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`. Do not package/install, merge, tag, release, or create Gate F.
