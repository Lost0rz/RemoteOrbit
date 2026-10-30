# CURRENT_STATUS

Last updated: 2026-10-30
State: `RO-VOICE-PIPELINE-SIMPLIFICATION-042 — WAITING_FOR_INDEPENDENT_WEB_AUDIT`
Repository: `Lost0rz/RemoteOrbit`

## Current authority

- Active control branch: `codex/voice-pipeline-simplification-042`.
- 042 parent / frozen evidence baseline: `codex/diagnostic-hardening-041` at `ac3132986197bfee4440bb8f388e3d2e5f478f03`.
- 041 is retained as `FROZEN_OBSERVABILITY_BASELINE`: its one-shot diagnostics, exporter, packaged Air observation candidate, and evidence conclusions remain available for before/after comparison. It is not being merged, tagged, released, or mutated by Gate 0.
- Gate 0 established the 042 control branch. Gate A was implemented in the canonical writer worktree `/private/tmp/remoteorbit-voice-pipeline-simplification-042` on the active branch. ATVV/BLE transport, AudioPipe, driver, packaging, installed runtime, Air runtime, and TCC boundaries remain unchanged.
- `AGENTS.md` remains the durable repository rule authority and is unchanged.
- `CURRENT_TASK.md` is the sole active execution authorization for 042.
- PR #25 / `codex/release-v0.2.15` and PR #26 / `codex/mapping-config-simplify-040` remain preserved and out of scope for 042 unless a later explicit transition says otherwise.

## Accepted product direction

The voice key is now defined as transport control, not mode control:

- physical voice DOWN starts one remote-voice session;
- physical voice UP begins a clean drain/stop sequence;
- the voice key no longer owns SHORT/LONG/DOUBLE classification, Persistent voice mode, receiver A/B switching, or input-method switching;
- voice-input/IME trigger choice becomes a low-frequency menu-bar profile selection with a persisted selected profile;
- profile switching must not change an active voice session mid-press.

The primary product goal is a single deterministic path from Xiaomi RC003 remote audio to the selected voice-input trigger and `RemoteOrbit Mic 2ch`, with minimal state and measurable start/continuity/tail behavior.

## Architecture decisions retained for the plan

- Preserve the existing ATVV protocol implementation unless later evidence proves a protocol defect.
- Preserve 041 diagnostic authority, bounded traces, underrun episodes, exporter, and privacy boundary; adapt semantics only as the product pipeline changes.
- Separate long-lived ATVV transport readiness from short-lived voice-stream state in a later gate.
- Move BLE ingestion off the UI/control scheduling path in a later gate.
- Replace the current dynamic/locking audio queue with a fixed-capacity realtime-safe producer/consumer path in a later gate.
- Tune any small jitter reserve only after the structural transport/audio changes are independently measurable.
- Tail shutdown should ultimately be event-driven with bounded safety timeouts, not a stack of fixed-delay ownership rules.

## Current authorized next gate

`Gate A — Voice control-plane simplification` is implemented and locally verified. The current stop state is `WAITING_FOR_INDEPENDENT_WEB_AUDIT`; no Gate B work is authorized.

Gate A may change voice-session/controller semantics, trigger-profile configuration, menu/profile presentation needed by that contract, compatibility migration for old trigger preferences, and tests/diagnostic semantics directly coupled to removal of the old voice modes.

Gate A must NOT change:

- CoreBluetooth connection lifetime or delegate queue;
- ATVV protocol/codec/sample-rate semantics;
- BLE reconnect/keepalive behavior except where dead old-mode code must be detached without changing transport behavior;
- AudioPipe queue/playout/resampling/gain policy;
- jitter-buffer policy;
- virtual audio driver behavior;
- packaging/install/runtime/TCC state;
- merge/tag/release state;
- 041 always-on probe scope beyond the minimum semantic adaptation required by removal of old state names.

Planned Gates B–E remain design intent only and are not authorized for implementation until Gate A is completed, independently audited, and the control plane is advanced.

## Gate A target behavior

- No 300 ms voice SHORT/LONG classifier on the primary voice path.
- No Persistent voice-session state on the primary voice path.
- No dual-receiver voice gesture state on the primary voice path.
- Selected voice profile is resolved before a session and remains fixed for that session.
- Physical DOWN begins trigger/remote-voice opening immediately through the existing transport boundary.
- Physical UP begins draining; trigger release remains ordered after already-received remote PCM/output drain so RemoteOrbit does not add avoidable tail truncation.
- Existing hardware-trigger delivery should be simplified rather than replaced gratuitously; synthetic delivery remains fallback-only where already required.
- Existing 041 observability remains capable of comparing input edge, MIC_OPEN/AUDIO_START/AUDIO_FIRST, BLE/decode/PCM/render continuity, underrun, and output/tail boundaries.

## Gate A local receipt

- Canonical writer: `/private/tmp/remoteorbit-voice-pipeline-simplification-042`.
- Audited parent before implementation: `6ab19f409210dad5aef55301bff6e4cd8e5ff5c6` on `codex/voice-pipeline-simplification-042`.
- Production microphone HID edges now use one direct `OPENING → STREAMING → DRAINING → IDLE` lifecycle; selected `VoiceInputProfile` identity is captured before trigger DOWN and retained through trigger UP.
- Profile migration reads only the legacy momentary trigger; Persistent and Receiver B preferences remain compatibility projections/non-authorities for the primary path.
- UI exposes the direct transport contract and a menu-bar profile selector; old microphone short/long/dual cards are no longer rendered.
- Validation: `swift test --package-path remote-orbit` passed 505/505; arm64 release build passed; x86_64 release build passed; `./remote-orbit/run-self-tests.sh` passed 3/3; `git diff --check` passed.
- Gate A tail corrective completed from audited implementation parent `718a85f20362c8826305a49fb6c2dc40bf96dff0`: direct physical UP now enters `DRAINING`, arms the captured hardware release, requests the existing AppController/BLE stop flow, and keeps the remote AudioPipe route/candidate active until the existing `onStreamingChanged(false)` transport/audio-stop boundary. Only then does it end the candidate, deactivate the route, request output drain, and release the same trigger after output completion. Transport-loss and no-`AUDIO_START` paths use the same observed-stop boundary; no fixed delay was added.
- Tail corrective validation: `swift test --package-path remote-orbit` passed 510/510; focused VoicePipelineSimplification, VoiceBoundaryOrdering, VoiceTriggerRuntime, BLEBridge, ATVV telemetry, AudioPipe, AudioDataPlaneDiagnostics, VoiceBoundaryDiagnostics, DiagnosticHardening, and P1A5 suites passed; arm64 and x86_64 release builds passed; protocol self-tests passed 3/3; `git diff --check` passed. `BLEBridge.swift` and `AudioPipe.swift` are unchanged.
- Human natural-use/UI acceptance, rendered visual inspection, independent Web audit, installed runtime, TCC, and Air-side acceptance remain unverified/user-owned.

## Gate A tail corrective receipt

- The corrected ordering is: `PHYSICAL_UP → DRAINING / hardware release armed → existing AppController stop request → existing transport/audio-stop completion → end remote candidate + route inactive → output drain → captured trigger UP → IDLE`.
- Focused coverage includes active-release ordering, late-tail PCM eligibility, stream-stop/output-drain trigger ownership, no-`AUDIO_START` release cleanup, rapid next-session admission, hardware-trigger release, and AppController stop-callback ordering.
- No change was made to BLEBridge post-release grace/AUDIO_STOP duration, CoreBluetooth/ATVV behavior, AudioPipe architecture, jitter, driver, packaging, installation, TCC, Air runtime, menu/profile behavior, or planned Gates B–E.

## Stop state

Remain at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`. Do not begin Gates B–E, merge, tag, release, install, mutate the Air runtime, or advance the control plane without the explicitly authorized post-audit transition.
