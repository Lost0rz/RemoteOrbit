# CURRENT_STATUS

Last updated: 2026-10-30
State: `RO-VOICE-PIPELINE-SIMPLIFICATION-042 — ADOPTED_PHYSICAL_GRACE_CORRECTIVE_IMPLEMENTED / WAITING_FOR_INDEPENDENT_WEB_AUDIT`
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

## Local corrective evidence

The bounded corrective is implemented in `BLEBridge` with session-specific
adopted-physical retirement state. It records the adopted session ID, physical
release, and healthy AUDIO_STOP drain completion. Only when the matching grace
is still waiting, no host `MIC_OPEN` was issued, and both lifecycle edges are
observed does it cancel that grace and clear the old `voiceInputRequested`
intent. It retains ATVV READY and does not issue `MIC_CLOSE`. A stale grace
generation remains unable to expire or mutate a newer session.

Observed validation on the local corrective source:

- focused BLE/voice boundary/trigger/post-release/AudioPipe/ATVV/diagnostic
  selection: 291/291 passed;
- full Swift test suite: 581/581 passed;
- arm64 Release source build: completed, `lipo -archs` reported `arm64`;
- x86_64 Release source build: completed, `lipo -archs` reported `x86_64`;
- protocol self-tests: 3/3 passed;
- `git diff --check`: passed;
- changed paths are limited to `BLEBridge.swift` and its two focused test
  files; packaging, installation, driver, TCC, and runtime state were not
  changed.

The implementation and tests are in the control transition commit directly
following audited control HEAD `74611c813887c9ccb489554cb452b390fb5bbff1`.
No package or install was performed.

## Stop / next

Push and verify the existing 042 branch, then wait for the independent Web
audit. Do not package/install, merge, tag, release, or create Gate F.
