# CURRENT_STATUS

Last updated: 2026-10-30
State: `RO-VOICE-PIPELINE-SIMPLIFICATION-042 — CORRECTIVE_SOURCE_AUDIT_PASS / READY_FOR_CORRECTIVE_CANDIDATE_PREPARATION`
Repository: `Lost0rz/RemoteOrbit`

## Current authority

- Active branch: `codex/voice-pipeline-simplification-042`.
- `AGENTS.md` remains durable repository authority.
- `CURRENT_TASK.md` is the sole active execution authorization.
- Frozen 041 observability baseline: `ac3132986197bfee4440bb8f388e3d2e5f478f03`.

## Accepted semantic lineage

- Gate A: `50b1d9efabe15f04d5479b39af227d0e6f43a4e3` — CLOSED / INDEPENDENT AUDIT PASS.
- Gate B: `ae0bf10874d34ce556b4b73a506b22f6a9a1a412` — CLOSED / INDEPENDENT AUDIT PASS.
- Gate C: `9abdebc21a1e03c79ab0ac960bf2d9902c24b1d5` — CLOSED / INDEPENDENT AUDIT PASS.
- Gate D: `9cdbf6f5190d9ed453d7f15cf2e8192973cc62ad` — CLOSED / INDEPENDENT AUDIT PASS.
- Gate E candidate before runtime failure: `2d09b6d77f9f75aa46bb4a13838cd22d5589f524` — SOURCE AUDIT PASS; runtime acceptance later FAILED.
- Physical-HTT admission corrective: `7dfd2e0c9ab71d3fa437be9b4c5cfac1282d9b1c` — INDEPENDENT CODE_DIFF AUDIT PASS.

## Runtime incident

Installed candidate `0.2.14 (43)` exposed a real no-waveform regression after the first successful session. Preserved runtime evidence showed valid `PHYSICAL_HTT` AUDIO_START, BLE notifications and decoded PCM, while the matching HID press was rejected `voice_session_busy` and `AudioPipe.remoteActive` never became true.

Incident record:

`docs/incidents/2026-10-30-042-no-waveform-physical-htt-admission-race.md`

The confirmed fault was ownership ordering: a pre-HID physical ATVV stream was being published as session-owned `remoteStreaming`, poisoning direct-session admission.

## Corrective source acceptance

Independent Web audit of exact head `7dfd2e0c9ab71d3fa437be9b4c5cfac1282d9b1c` accepts the bounded corrective source semantics:

- pre-HID physical streaming is separated from `VoicePressCoordinator` session ownership;
- candidate-only pre-HID streaming no longer makes the matching HID press busy;
- direct HID admission still establishes normal profile/trigger ownership and activates the existing remote route;
- an already-active physical stream is adopted before the host-MIC_OPEN path, preventing a duplicate host MIC_OPEN for that stream;
- the existing AudioPipe candidate prebuffer is preserved and promoted through the normal route activation path;
- normal no-preexisting-stream activation still uses the Gate B strict-READY host-MIC_OPEN path;
- unowned physical stream retirement clears candidate state;
- adopted stream retirement continues through the existing Gate A-E tail/output-drain/session-ID boundaries;
- long-lived READY, strict READY, ATVV framing/codec, Gate C ring, Gate D 45 ms reserve, driver and runtime policy were not changed.

Executor evidence at the corrective head records focused suites `225/225` (corrective subset `64/64`), full Swift `574/574`, arm64/x86_64 Release builds, protocol self-tests `3/3`, and `git diff --check` passing. Independent audit accepts source semantics only; installed corrective runtime behavior is not yet accepted.

## Current phase — Corrective candidate preparation

The corrective source identity is frozen at:

`7dfd2e0c9ab71d3fa437be9b4c5cfac1282d9b1c`

The next authorized action is to build/package/install exactly this corrective source (plus control-only descendants whose product-source diff is empty), prove candidate/installed provenance, launch it, and stop for human RC003 runtime retest.

Do not modify product source during candidate preparation. Do not merge, tag, release, reset TCC, replace/reload the driver, alter the 45 ms reserve, or create Gate F.

## Stop / next

Prepare and install one provenance-locked corrective candidate, then stop at `READY_FOR_HUMAN_CORRECTIVE_RUNTIME_RETEST`.

The user must personally retest the original failure mode: first voice session plus repeated subsequent RC003 presses, verifying Doubao waveform/audio remains present after READY transport reuse. Agent-side packaging or automated tests cannot approve the runtime acceptance.
