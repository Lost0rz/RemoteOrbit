# CURRENT_STATUS

Last updated: 2026-10-30
State: `RO-VOICE-PIPELINE-SIMPLIFICATION-042 — READY_FOR_LOCAL_GATE_B`
Repository: `Lost0rz/RemoteOrbit`

## Current authority

- Active control branch: `codex/voice-pipeline-simplification-042`.
- 042 parent / frozen evidence baseline: `codex/diagnostic-hardening-041` at `ac3132986197bfee4440bb8f388e3d2e5f478f03`.
- `AGENTS.md` remains the durable repository rule authority and is unchanged.
- `CURRENT_TASK.md` is the sole active execution authorization for 042.
- PR #25 / `codex/release-v0.2.15` and PR #26 / `codex/mapping-config-simplify-040` remain preserved and out of scope unless a later explicit transition says otherwise.

## Gate A — independently accepted

Gate A implementation lineage:

- Gate 0 control transition: `6ab19f409210dad5aef55301bff6e4cd8e5ff5c6`.
- Gate A implementation: `718a85f20362c8826305a49fb6c2dc40bf96dff0`.
- Gate A tail-order corrective / audited semantic head: `50b1d9efabe15f04d5479b39af227d0e6f43a4e3`.

Independent Web `CODE_DIFF` audit at `50b1d9e...` is `PASS` for the Gate A boundary:

- production microphone HID DOWN enters the direct `OPENING → STREAMING → DRAINING → IDLE` path without the old 300 ms SHORT/LONG classifier;
- selected `VoiceInputProfile` is captured once and owns the same trigger through release;
- Persistent/Receiver A-B voice modes are not reachable from the production microphone path;
- physical UP keeps the remote route/candidate active until the existing BLE transport/audio-stop completion signal;
- `BLEBridge` keeps its existing post-release grace and 350 ms AUDIO_STOP drain, and only after that boundary does the direct path disable the remote route, drain queued output, and release the captured trigger;
- no Gate B/C implementation was introduced by the Gate A corrective; `BLEBridge.swift` and `AudioPipe.swift` were unchanged in that corrective.

Local executor verification recorded at the audited semantic head: Swift tests 510/510, focused voice/BLE/ATVV/AudioPipe/diagnostic suites pass, arm64/x86_64 release builds pass, protocol self-tests 3/3, `git diff --check` pass.

Human natural-use/UI acceptance, installed runtime, TCC state, and Air-side acceptance remain owner-owned and pending; they are not prerequisites for beginning the bounded Gate B source change, but they remain required before final product acceptance/release.

## Accepted product direction

The voice key is transport control, not mode control:

- physical voice DOWN starts one remote-voice session;
- physical voice UP begins a clean stop/drain sequence;
- no SHORT/LONG/DOUBLE/Persistent/Receiver-A-B mode on the primary voice path;
- input-method trigger selection is a low-frequency persisted menu-bar `VoiceInputProfile`;
- a session captures one profile and cannot switch mid-session.

The product goal is one deterministic Xiaomi RC003 → ATVV → PCM → `RemoteOrbit Mic 2ch` path with minimal control-state noise and measurable start/continuity/tail behavior.

## Current authorized next gate

`Gate B — Long-lived ATVV transport + dedicated BLE ingestion queue` is now authorized.

Gate B must preserve the Gate A direct voice-session contract while changing only the transport/control scheduling architecture required to:

1. separate app-lifetime ATVV connection readiness from per-press voice-stream lifetime;
2. keep a prepared/ready ATVV connection alive across normal voice sessions where CoreBluetooth/device state permits;
3. move CoreBluetooth delegate/notification handling from `.main` to one dedicated serial queue;
4. marshal only lightweight control/UI state back to the main queue;
5. preserve ATVV command/framing/codec/sample-rate/AUDIO_SYNC semantics, existing 041 observability, existing tail-drain semantics, and the current AudioPipe data plane.

Gate B must NOT implement Gate C/D/E: no SPSC audio ring, no CoreAudio render rewrite, no jitter-buffer tuning, no codec/gain/resampler change, no new start/tail delay policy, no driver/package/install/TCC/Air runtime change, and no merge/tag/release.

## Next action

Local construction should fetch the exact live 042 branch, reconcile against this control state, establish one canonical writer, and execute Gate B only. After implementation/verification, push the same authorized branch and stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`. Do not begin Gate C automatically.
