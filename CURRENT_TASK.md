# RemoteOrbit Current Task

## RO-IME-READINESS-PROMPT-SYNC-043 — Receiver Readiness / HUD Truth Design

Status: `DESIGN_COMPLETE / IMPLEMENTATION_NOT_AUTHORIZED`

Repository: `Lost0rz/RemoteOrbit`
Active branch: `codex/ime-readiness-prompt-sync-043`
Predecessor control HEAD: `1eb0fa32847f9213701953835b3f8191844fa114`
Predecessor task: `RO-VOICE-PIPELINE-SIMPLIFICATION-042`
Design authority: `docs/design/2026-10-31-043-ime-readiness-prompt-sync.md`

## Objective

Correct the user-facing mismatch where RemoteOrbit can show a successful/recording voice HUD state even though the external IME has not actually begun consuming `RemoteOrbit Mic 2ch`.

The objective is to make readiness presentation truthful without destabilizing the Task 042 transport/audio ownership model.

## Verified problem

Current code projects internal RemoteOrbit state directly into the HUD:

- `.opening` -> pending voice HUD;
- `.streaming` -> green `recording` HUD;
- `onRemoteAudioChanged(true)` -> green `recording` HUD.

Those signals prove RemoteOrbit's BLE/audio path is active. They do not prove Doubao or another external receiver is listening.

Fresh human/runtime evidence shows a rapid re-press can occur while Doubao is still completing its previous text-processing lifecycle. RemoteOrbit may successfully enter opening/streaming and render audio while Doubao does not start a new capture session. After the previous IME lifecycle settles, a later press opens normally.

## Authorized design conclusion

The selected design is documented in the design authority and has these implementation boundaries:

1. `VoicePressCoordinator` remains transport/session authority only.
2. Introduce a read-only receiver-readiness observer outside the coordinator.
3. On supported macOS versions, the observer may use Core Audio process objects to identify an external process with active input IO scoped to `RemoteOrbit Mic 2ch`.
4. Preserve macOS 13 deployment compatibility through availability-gated implementation and an explicit unsupported/unknown state.
5. `AppController` combines local voice state, remote-audio readiness and receiver readiness into the voice HUD projection.
6. `RemoteActionHUD` may gain voice-specific presentation states, but it remains presentation-only.
7. A green `正在语音中` state requires external-consumer confirmation when the observer is supported/reliable.
8. Without external confirmation, show only truthful local states such as `等待输入法` or `音频已就绪`.

## Explicit non-goals

Task 043 does NOT authorize:

- BLEBridge or AudioPipe ownership/timing changes;
- Task 042 rapid-repress state-machine changes;
- fixed 300/500 ms or other Doubao cooldown;
- automatic trigger retry/replay;
- delaying the initial trigger until receiver readiness;
- holding/buffering speech until the receiver becomes ready;
- Doubao-specific private API, Accessibility scraping, unified-log scraping or process-name hardcoding;
- driver/CoreAudio/TCC mutation;
- package/install/runtime mutation;
- merge/tag/release/Gate F.

## Required pre-implementation spike

Before trusting Core Audio process readiness as product truth, implementation must prove the signal on the actual runtime environment.

Required validation shape:

- enumerate Core Audio process objects on supported macOS;
- identify processes with active input IO;
- query input-scoped process device membership and match the `RemoteOrbit Mic 2ch` device ID;
- exclude the RemoteOrbit process itself;
- correlate state transitions with normal IME voice starts/stops and rapid ignored re-open attempts;
- verify there are no false `listening` transitions during the known Doubao post-processing interval;
- preserve a deterministic unsupported/unknown path on macOS versions where the process properties are unavailable.

If input-scoped process/device identity is unreliable on the target runtime, STOP the readiness-confirmation path and implement only truthful local HUD semantics. Do not invent a substitute signal.

## Required UI semantics

Implementation should distinguish at least:

- local voice activation starting: `等待输入法`;
- RemoteOrbit audio path live but no receiver confirmed: `音频已就绪`;
- external receiver confirmed consuming the virtual mic: `正在语音中`;
- draining/ending: existing truthful ending state.

Do not display a failure toast merely because a very short press ended before receiver confirmation in the first implementation.

## Verification contract for a later implementation

At minimum:

- unit tests for receiver-state projection and unsupported fallback;
- regression proving `.streaming`/`AUDIO_FIRST` alone cannot produce the green external-listening HUD state;
- regression proving confirmed external input consumption does produce the green state;
- regression proving observer loss/unsupported state falls back conservatively;
- macOS 13 deployment target remains unchanged;
- existing Task 042 focused tests remain green;
- full Swift tests and both Release architectures remain green;
- no BLEBridge/AudioPipe product diff unless separately re-authorized.

Human runtime acceptance must include normal starts, rapid ignored re-open, delayed successful re-open, and verification that the HUD never claims `正在语音中` when the IME did not actually enter listening state.

## Next

No implementation under this control state. After user approval, create a bounded execution card and then transition this same Task 043 to implementation authority. Do not create a successor task merely for implementation of this accepted design.
