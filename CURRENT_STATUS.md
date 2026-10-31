# CURRENT_STATUS

Last updated: 2026-10-31
State: `RO-VOICE-PIPELINE-SIMPLIFICATION-042 — RC003_RUNTIME_ACCEPTANCE_FAIL / CORRECTIVE_REQUIRED`
Repository: `Lost0rz/RemoteOrbit`
Active branch: `codex/voice-pipeline-simplification-042`

## Current authority

- Runtime candidate under test came from accepted product source `ef606a3f712304cf43da2e9fb849a87a0bb02a1b` plus control-only descendants.
- Installed app identity was verified during the failed run: `/Applications/RemoteOrbit.app`, PID `31333`, version `0.2.14 (43)`, executable SHA-256 `2799d6a4b2b13a08f4304e00b75962c2dfaf95fd6d25e65894ae7e7ad30ee935`.
- Independent Web `CODE_DIFF` audit of `ef606a3f...` remains a source-level PASS; the fresh RC003 hardware/runtime acceptance is now FAIL.
- New runtime evidence/design addendum: `docs/incidents/2026-10-31-042-rc003-runtime-owner-race.md`.
- Prior design authority remains `docs/incidents/2026-10-30-042-host-mic-open-rapid-repress.md`.
- `AGENTS.md` remains durable repository authority; `CURRENT_TASK.md` is the sole active execution authorization.

## Human runtime result

Human RC003 acceptance: `FAIL`.

The user reproduced the remaining symptom under extreme rapid release/re-press: Doubao can show the listening waveform while the new utterance carries no usable RemoteOrbit audio/transcription.

The latest capture is sufficient for corrective work. No additional broad probe phase is required.

### Finding A — production hardware-owner timing gap

Fresh diagnostics contain:

- `PHYSICAL_TRANSPORT_SUPERSEDED`: 18;
- direct re-press deferred for `direct_output_drain`: 10;
- later rejected as `pending_hardware_repress_owner_missing`: 10;
- `PENDING_HARDWARE_REPRESS_BEGIN`: 0;
- `PENDING_HARDWARE_REPRESS_PROMOTE`: 0;
- `REPLAY_UP_PASS_ACK`: 0;
- production hardware gate release resolved `noOptionEdge` on all 36 direct openings in the fresh run, with matching stale old Option-up release observations.

The deployed ordering differs from the prior deterministic test assumption. The direct path arms and immediately resolves the hardware gate before the mapped Option DOWN reaches the event tap. That DOWN therefore passes to Doubao, but no `heldHardwareOptionSessionID` is created. During a rapid B re-press the coordinator still records B as deferred, while `VoiceKeyFilter.beginPendingHardwareOptionRepress` silently fails because it requires an old filter-owned UP/replay owner. B's mapped DOWN can then pass to Doubao and open a waveform. When A drains, B promotion fails because there is no pending hardware owner/captured DOWN, so the B candidate never becomes the active RemoteOrbit route. This directly explains waveform-without-audio.

### Finding B — released HOST_MIC_OPEN drain still blocks physical B

The fresh run also contains three terminal HOST_MIC_OPEN drain overlaps where old `streamID=0` is inside the 350 ms AUDIO_STOP drain and a new explicit physical `reason=0x03` / new stream ID is ignored as `late AUDIO_START`.

- one matching HID DOWN was rejected `voice_session_busy`;
- two matching HID DOWN/UP pairs were suppressed by debounce after the physical start had already been discarded.

The existing released-HOST supersession rule only activates after the drain barrier is gone, so it is too late for this overlap.

## Corrective direction

Continue the existing Task 042 with two bounded corrections:

1. make direct-output-drain B hardware capture explicit even when A has no filter-owned old-UP owner; do not ignore pending-owner arm failure; require a two-condition promotion barrier: A terminal/output ownership complete and B mapped DOWN actually captured;
2. allow a new physical reason `0x03` / different stream ID to supersede a terminal released HOST_MIC_OPEN drain when released-host grace proves A is already physically released, while preserving queued A output, READY, epoch protection and stale-MIC_CLOSE safety.

Do not add a generic Doubao delay/re-arm timer yet. The user's observation that Doubao may reject input while post-processing remains plausible, but the current capture already proves two independent RemoteOrbit failures. Revisit IME readiness only after these internal failures are removed and a later capture shows healthy RemoteOrbit route/render with Doubao still refusing speech.

## Preserved boundaries

- Keep the normal 350 ms no-replacement tail window.
- Keep generic 180 ms debounce except existing evidence-gated physical-candidate bypass.
- Preserve candidate PCM isolation, A-terminal/B-candidate supersession, HOST stale-MIC_CLOSE safety, READY, Gate C ring, Gate D 45 ms reserve, ATVV codec/framing and driver/TCC behavior.
- No global UNKNOWN remap.
- No driver/TCC mutation.
- No package/install/runtime retest before the next independent Web source audit.
- No merge/tag/release/Gate F.

## Next

Implement the bounded corrective on the existing Task 042 branch, add deterministic regressions matching the deployed ordering, run focused/full tests plus release/protocol checks, update controls with actual evidence, push and verify the existing branch, then stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`.
