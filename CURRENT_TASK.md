# RemoteOrbit Current Task

## RO-VOICE-PIPELINE-SIMPLIFICATION-042 — Single-Path Voice Pipeline

Status: `WAITING_FOR_INDEPENDENT_WEB_AUDIT`

Repository: `Lost0rz/RemoteOrbit`

Active branch: `codex/voice-pipeline-simplification-042`

Baseline / parent: `ac3132986197bfee4440bb8f388e3d2e5f478f03`

## Objective

Replace the current multi-mode voice-key control surface with one deterministic remote-voice path, while preserving the proven ATVV protocol and 041 observability baseline.

The product contract is:

```text
VOICE DOWN
→ begin selected voice-input trigger + remote voice opening immediately

VOICE UP
→ stop remote capture through a clean drain
→ release the selected voice-input trigger only after already-received audio/output is safely drained
```

The voice key is transport control, not mode control.

## User / project decisions

1. The voice key has one high-frequency responsibility: remote voice start/stop.
2. Remove voice-key SHORT/LONG/DOUBLE behavior from the primary voice path.
3. Remove Persistent voice mode from the primary voice path.
4. Remove voice-key receiver A/B switching and voice-key input-method switching.
5. Voice-input/IME selection is a low-frequency menu-bar action.
6. Menu-bar voice profiles may preset the trigger key used by a target input method; the selected profile persists.
7. A profile is captured for a voice session and cannot switch mid-session.
8. Primary optimization target is complete, stable Xiaomi RC003 audio delivery to the selected voice input, especially start, active continuity, and clean tail behavior.

## Retained evidence / compatibility authority

- Keep the existing ATVV v0.4/v1.0 protocol implementation unless new evidence proves a protocol defect.
- Keep 041 `voice_attempt_id`, BLE/decode/PCM/render ordering evidence, underrun episodes, runtime health, DiagnosticAuthority, bounded trace, DiagnosticExporter, and privacy limits.
- Keep historical 041 evidence as a before/after baseline; do not reinterpret old observations as proof of a new root cause.
- Do not add another always-on diagnostic ring or duplicate diagnostic authority.

## Gate sequence

The architecture plan has five implementation gates. Only Gate A is currently authorized.

### Gate A — Voice control-plane simplification — AUTHORIZED

Goal: make the voice path semantically single-purpose before changing BLE or audio data-plane architecture.

Authorized work:

1. Replace primary voice-key SHORT/LONG/Persistent routing with one direct session lifecycle such as `IDLE → OPENING → STREAMING → DRAINING → IDLE`.
2. Remove the 300 ms voice hold classifier from the primary remote-voice path.
3. Retire primary-path ownership of:
   - `VoiceSessionMode.persistentOpen`;
   - `RemoteSegmentTriggerPolicy.audioOnly` / momentary-vs-persistent branching;
   - persistent toggle state;
   - dual receiver A/B voice gesture selection;
   - voice-key double/short semantics where they participate in the remote-voice path;
   - repress/deferred branches that exist only to reconcile those retired modes.
4. Add/establish one selected `VoiceInputProfile` authority suitable for low-frequency menu-bar selection. A profile must at minimum have stable identity, display name, and trigger key. Avoid coupling it to automatic app/IME detection.
5. Migrate existing trigger preferences conservatively. Legacy preference keys may remain for compatibility/rollback, but they must stop being competing runtime authorities once migration succeeds.
6. Ensure one session captures its selected trigger/profile at start and uses the same trigger for release.
7. Prefer preserving the existing hardware-trigger path where safe. Simplify its ownership to immediate voice-start semantics and delayed release-after-drain semantics; do not replace it with synthetic events merely for convenience.
8. Adapt tests and diagnostic event semantics only as required to represent the new single-path state machine truthfully.
9. Remove dead old-mode code only where its non-use is proven by callers/tests; preserve unrelated remote-button mappings and non-voice product behavior.

Expected primary ordering after Gate A:

```text
physical voice DOWN
→ create/bind voice_attempt_id
→ capture selected voice profile
→ begin selected trigger immediately
→ request remote voice / MIC_OPEN immediately through existing BLEBridge boundary
→ AUDIO_START / AUDIO_FIRST / PCM / output

physical voice UP
→ enter DRAINING
→ stop remote stream using existing transport shutdown semantics
→ drain already-received PCM/output
→ release the same selected trigger
→ IDLE
```

Gate A intentionally keeps the current underlying BLE connection lifecycle and AudioPipe implementation so behavioral changes remain attributable to control-plane simplification.

### Gate B — Long-lived ATVV transport — PLANNED / NOT AUTHORIZED

Design intent only:

- split `DISCONNECTED / CONNECTING / READY` transport lifetime from `IDLE / OPENING / STREAMING / DRAINING` voice-stream lifetime;
- keep ATVV connection/discovery/subscription/capability readiness alive across voice sessions where the hardware/protocol permits;
- move CoreBluetooth ingestion to a dedicated serial queue and keep UI/control work off the audio notification path;
- preserve protocol semantics and diagnostics.

No Gate B mutation is authorized by the current task phase.

### Gate C — Realtime-safe audio data plane — PLANNED / NOT AUTHORIZED

Design intent only:

- fixed-capacity single-producer/single-consumer PCM ring;
- preallocated CoreAudio render path;
- no ordinary blocking lock, dynamic Array growth/compaction, formatting, JSON, or I/O on the realtime callback;
- retain bounded counters/traces for submitted/rendered/underrun evidence.

No Gate C mutation is authorized by the current task phase.

### Gate D — Small measured jitter reserve — PLANNED / NOT AUTHORIZED

Design intent only:

- after Gate C, evaluate the smallest reserve that absorbs observed 30–80 ms arrival jitter without creating material dictation latency;
- treat permanent BLE delivery deficit separately from jitter;
- no multi-second buffer and no claim that buffering restores frames that never arrive.

No Gate D mutation is authorized by the current task phase.

### Gate E — Start/tail boundary convergence — PLANNED / NOT AUTHORIZED

Design intent only:

- receiver/trigger ready no later than remote audio start;
- event-driven drain based on AUDIO_STOP / last arrival / ring/output empty where available;
- fixed delays become bounded safety timeouts rather than the primary ownership model;
- RemoteOrbit must not add avoidable tail truncation, while acknowledging that audio not captured by the remote after physical release cannot be recovered in software.

No Gate E mutation is authorized by the current task phase.

## Gate A non-goals / forbidden changes

Do not in Gate A:

- change ATVV command, framing, codec, ADPCM, sample rate, gain, or AUDIO_SYNC semantics;
- change CoreBluetooth delegate queue, connection persistence, reconnect policy, keepalive policy, service discovery, notification subscription, or transport shutdown timing except detaching obsolete old-mode callers without semantic change;
- change AudioPipe queue size, queue type, render policy, resampler, gain, limiter, playout policy, or underrun correction;
- add a jitter buffer;
- change virtual audio driver behavior;
- add automatic input-method/app detection;
- add another voice gesture, double-click, short action, or new voice-key mode;
- expand always-on diagnostics beyond minimal semantic adaptation;
- package, install, replace `/Applications/RemoteOrbit.app`, reload CoreAudio, mutate TCC, or alter Air runtime;
- merge, tag, release, close preserved PRs, or mutate 039/040/041 historical branches.

If Gate A appears to require one of these changes, STOP and report the dependency rather than silently expanding scope.

## Gate A verification requirements

At minimum prove:

1. exact starting branch/head and clean canonical local writer;
2. primary voice DOWN no longer waits for SHORT/LONG classification before starting the remote-voice opening path;
3. primary voice path contains no reachable Persistent/dual-receiver voice mode transition;
4. selected profile is captured once and the same trigger identity owns DOWN and UP;
5. profile switch is either rejected/deferred while active and cannot split a session across two triggers;
6. voice UP enters draining and trigger release remains after already-received output drain;
7. rapid sequential sessions do not inherit stale session/profile/trigger ownership;
8. BLE/ATVV protocol and AudioPipe focused regressions remain unchanged and pass;
9. existing 041 attempt/start/continuity/output evidence remains truthful after removal of `HOLD_CONFIRMED` as a product boundary; obsolete diagnostic fields/events are removed or explicitly versioned rather than emitting false state;
10. unrelated remote-button mappings remain unchanged;
11. full Swift tests, release build, required x86 build, protocol self-tests, and `git diff --check` pass where supported by the established repository flow;
12. no product code outside Gate A scope is changed without explicit evidence and authority.

Human natural-use acceptance remains owner-owned and must not be replaced with synthetic UI interaction.

## Gate A implementation receipt

The authorized Gate A implementation is complete in canonical writer worktree `/private/tmp/remoteorbit-voice-pipeline-simplification-042`.

- Production raw-HID microphone DOWN/UP no longer enters the short/long/double classifier, Persistent session mode, or Receiver A/B selector. It starts one direct voice session and drains before releasing the captured trigger.
- `VoiceInputProfile` is the selected low-frequency menu-bar authority. It has stable ID/display/trigger fields, conservative legacy-momentary migration, and session capture semantics.
- Existing ATVV/BLE, reconnect/keepalive, AudioPipe, driver, packaging, runtime, and TCC boundaries were not changed.
- Historical classifier/dual-receiver seams remain only for compatibility tests; no production microphone edge calls that seam.
- 041 diagnostics were adapted to truthful `VOICE_SESSION_OPENING`, `STREAMING`, `DRAINING`, profile, and trigger fields; production no longer emits `HOLD_CONFIRMED` for the direct voice boundary.

## Gate A verification receipt

- Full Swift tests: `swift test --package-path remote-orbit` — 505/505 passed.
- Release builds: arm64 `swift build --package-path remote-orbit -c release` passed; x86_64 `swift build --package-path remote-orbit -c release --triple x86_64-apple-macos13.0` passed.
- Protocol self-tests: `./remote-orbit/run-self-tests.sh` — 3/3 passed.
- Static checks: `git diff --check` passed; changed paths were inspected.
- Not performed by this Gate A executor: app packaging/install, installed-runtime replacement, TCC changes, Air runtime mutation, rendered UI inspection, human natural-use acceptance, and independent Web audit.

## Gate A completion / stop state

This transition updates `CURRENT_STATUS.md` and `CURRENT_TASK.md` together with the implementation. After the transition commit, push the exact authorized branch, verify remote/local match, and stop at:

`WAITING_FOR_INDEPENDENT_WEB_AUDIT`

Do not advance to Gate B automatically. Gate B requires an explicit post-audit control-plane transition.

## Gate 0 transition receipt

Gate 0 is a remote-only governance transition from 041 baseline `ac3132986197bfee4440bb8f388e3d2e5f478f03` to the 042 branch. It changes only `CURRENT_STATUS.md` and `CURRENT_TASK.md` in one direct-child commit. It does not construct, package, install, launch, merge, tag, or release product code.
