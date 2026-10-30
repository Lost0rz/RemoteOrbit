# RemoteOrbit Current Task

## RO-VOICE-PIPELINE-SIMPLIFICATION-042 — HOST_MIC_OPEN Rapid Re-press Reconciliation

Status: `FINAL_RUNTIME_EVIDENCE_REVIEW_STOP / NEEDS_STATE_OWNERSHIP_RECONCILIATION`

Repository: `Lost0rz/RemoteOrbit`
Active branch: `codex/voice-pipeline-simplification-042`
Accepted corrective source: `b1736f2feedd7ed13e4520ecdfaa0c6bf6e9b332`
Installed candidate: `0.2.14 (43)`
Final evidence archive: `RemoteOrbit-diagnostics-20261030-135113.tar.gz`
Incident record: `docs/incidents/2026-10-30-042-host-mic-open-rapid-repress.md`
Frozen 041 observability baseline: `ac3132986197bfee4440bb8f388e3d2e5f478f03`

## Evidence verdict

Final POST_CHANGE/runtime evidence review is STOP for merge/release readiness.

The adopted-PHYSICAL path is strongly validated in steady state: 34 consecutive physical sessions after 13:45:57 UTC are admitted and render successfully, and the final 20 completed sessions are fully clean with zero `voice_session_busy`, zero decode rejects, non-zero AudioPipe render, per-session stale-intent retirement, and no transport reset/loss.

The same final stress activity nevertheless contains two earlier hidden `voice_session_busy` rejects tied to the HOST_MIC_OPEN post-release path:

- `09B0` after host session `C8AAD51D-E665-44A5-AC4D-2C9D201A6154`;
- `BAFD` after host session `8A416474-28E0-4090-BE07-D28206153EA5`.

In both cases an explicit physical `AUDIO_START reason=0x03` arrives while stale HOST_MIC_OPEN state/grace is still active; current ownership classification publishes the new stream as session-owned before its matching HID DOWN, causing `voice_session_busy`.

## Design question

Define the smallest safe ownership transition for this exact case:

`old HOST_MIC_OPEN session physically released + post-release grace still waiting + new explicit physical AUDIO_START(reason=0x03) arrives before the next HID DOWN`.

The selected rule must allow the new physical stream to become a pre-HID candidate without letting the old host session poison admission, while preserving protocol correctness for MIC_CLOSE and not allowing a stale callback to mutate the new session.

## Verified constraints

- Do not regress the accepted `preHIDPhysical -> voiceSession` adoption path.
- Do not globally reclassify `UNKNOWN`.
- `reason=0x03` is the observed explicit physical start discriminator in this incident.
- HOST_MIC_OPEN sessions still require correct MIC_CLOSE semantics; v1.0 `MIC_CLOSE` includes a stream ID.
- Do not send a close that can terminate the newly arriving physical stream.
- Preserve long-lived READY and strict READY.
- Preserve Gate C ring and Gate D 45 ms reserve.
- Preserve ATVV codec/framing and existing drain/tail/trigger ordering.
- No driver/TCC/install change.
- No new probes are needed.
- No Gate F.

## Authorized work

Design/reconciliation only until the ownership rule is explicit and evidence-supported:

1. Inspect the existing HOST_MIC_OPEN close/grace lifecycle and stream-ID ownership around `stopVoiceInputOnBLEQueue`, `sendMicCloseAfterPostReleaseGrace`, `handleControl(.audioStart)`, and `finishAudioStopAfterDrain`.
2. Compare the smallest credible state-transition options for a superseding `reason=0x03` physical start during released host grace.
3. Select one rule that is session-specific, stale-callback-safe, and cannot close the newly arriving physical stream.
4. Define deterministic tests for both observed failure sequences and normal HOST_MIC_OPEN/no-AUDIO_START behavior.
5. Return the selected design and whether CURRENT_TASK needs a corrective-implementation transition.

## Explicitly not authorized

Do NOT yet:

- modify product source/tests/package scripts;
- globally map UNKNOWN to physical;
- disable host grace wholesale;
- disconnect per session;
- change long-lived READY/strict READY;
- change Gate C/Gate D;
- change protocol/codec;
- rebuild/repackage/reinstall;
- change driver/TCC;
- merge/tag/release;
- create Gate F.

## Required design return

Return:

- exact verified state sequence for `09B0` and `BAFD`;
- ownership/state variables that make the new physical stream look host-owned;
- 2–3 smallest credible transition options;
- selected option and rationale;
- MIC_CLOSE/stream-ID handling;
- stale-grace handling;
- behavior when old host AUDIO_STOP already drained vs no host AUDIO_START ever occurred;
- behavior for `reason != 0x03`;
- required deterministic tests;
- `TASK_RECONCILIATION_REQUIRED: YES/NO`.

Stop after design reconciliation. Product implementation requires a subsequent explicit control transition.
