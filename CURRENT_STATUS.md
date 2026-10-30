# CURRENT_STATUS

Last updated: 2026-10-30
State: `RO-VOICE-PIPELINE-SIMPLIFICATION-042 — CORRECTIVE_IMPLEMENTED / WAITING_FOR_INDEPENDENT_WEB_AUDIT`
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
- Gate E / accepted source candidate: `2d09b6d77f9f75aa46bb4a13838cd22d5589f524` — CLOSED / INDEPENDENT SOURCE AUDIT PASS before runtime acceptance.

## Runtime acceptance result

Human runtime acceptance FAILED on installed candidate `0.2.14 (43)`:

- the RC003 voice key still invokes the configured Doubao trigger;
- Doubao opens;
- there is no usable remote-microphone waveform/audio.

The preserved diagnostic bundle is sufficient. No new probe is required.

The installed candidate remains the previously accepted runtime candidate and
was not rebuilt, packaged, installed, or retested by this source corrective.

## Confirmed incident boundary

Root cause is a session-admission ordering defect exposed by the Gate B long-lived READY transport.

After the first routed attempt, ATVV remains READY with notifications subscribed. On later physical presses, the remote can emit:

`AUDIO_START reason=0x03 / session_origin=PHYSICAL_HTT`

before the matching HID voice-key down is admitted.

Current source behavior then does:

1. `BLEBridge` accepts the physical `AUDIO_START`, begins bounded remote candidate pre-roll, sets internal `isStreaming=true`, and calls `notifyStreaming(true)`.
2. The main callback forwards this into `voicePress.setRemoteStreaming(true)`.
3. `VoicePressCoordinator.hasReleaseOrTailOwnershipForReconfiguration` includes `remoteStreaming`.
4. The matching HID press is rejected as `voice_session_busy`.
5. `remoteRouted` / `AudioPipe.remoteActive` never become true for that press.
6. BLE notifications and ADPCM decode can still succeed, but decoded PCM is not promoted into the active AudioPipe render route.

Runtime evidence includes repeated physical streams with valid decoded audio while the route remains inactive. Examples include stream 35 with 84 frames / 20,160 samples and stream 44 with 115 frames / 27,600 samples. Their `AUDIOPIPE_SUMMARY` records no active render/fill while idle callbacks continue.

The detailed incident record is:

`docs/incidents/2026-10-30-042-no-waveform-physical-htt-admission-race.md`

## Corrective direction

Preserve Gate B long-lived READY and Gate C/D/E audio semantics. Separate transport-level pre-HID streaming/pre-roll from session-owned streaming.

Required behavior:

- a pre-HID `PHYSICAL_HTT` stream may decode and retain bounded candidate pre-roll;
- it must not by itself make the matching HID press fail admission;
- once the HID press is admitted, the already-active physical stream must be adopted/bound to that session and the remote route activated;
- adopting an already-active physical stream must not send a duplicate host `MIC_OPEN`;
- after adoption, normal streaming, tail, drain, trigger-up, stale-callback and rapid-next-session rules remain unchanged;
- unrelated/stale prior-session ownership must still block admission where appropriate.

## Local corrective receipt

The bounded corrective is implemented from audited control HEAD
`8d92fd6382b0bca9f1c5808c497df68590f2934d`.

- `BLEBridge` now distinguishes `preHIDPhysical` transport ownership from
  session-owned streaming, publishes pre-HID state through a separate callback,
  and adopts an active physical stream before the host `MIC_OPEN` path.
- `VoicePressCoordinator` treats pre-HID physical streaming as candidate-only
  state; it is excluded from release/tail admission ownership.
- Existing `AudioPipe` candidate buffering and route activation promote the
  pre-HID PCM without a second audio pipeline.
- Unowned physical retirement clears candidate state; adopted retirement keeps
  the existing Gate A-E stop/tail/drain/session-ID lifecycle.
- Deterministic corrective coverage was added for pre-HID admission, candidate
  ownership, adoption without duplicate `MIC_OPEN`, prebuffer promotion,
  strict READY host `MIC_OPEN`, unowned stop, adopted retirement, and rapid
  next-session behavior.

Validation receipt:

- focused corrective suites: `64/64` passed;
- full Swift test suite: `574/574` passed;
- arm64 Release build: completed;
- x86_64 Release build: completed;
- protocol self-tests: `3/3` passed;
- `git diff --check`: passed.

No package/install, driver, TCC, runtime, merge, tag, release, or Gate F
operation was performed.

## Stop / next

The bounded corrective is complete locally. Publish the same 042 branch,
verify exact local/remote equality, then stop at
`WAITING_FOR_INDEPENDENT_WEB_AUDIT`.

Do not merge, tag, release, change the 45 ms reserve, change the 96,000-frame ring, modify the driver/TCC, or create Gate F.
