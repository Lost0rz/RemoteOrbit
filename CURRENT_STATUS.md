# CURRENT_STATUS

Last updated: 2026-10-31
State: `RO-IME-READINESS-PROMPT-SYNC-043 — DESIGN_COMPLETE / IMPLEMENTATION_NOT_AUTHORIZED`
Repository: `Lost0rz/RemoteOrbit`
Active branch: `codex/ime-readiness-prompt-sync-043`

## Predecessor Task 042 runtime conclusion

Task 042 core voice-pipeline acceptance is complete for its authorized scope based on the user's fresh RC003 runtime observations and preserved candidate logs from app identity:

- `/Applications/RemoteOrbit.app`
- version/build `0.2.14 (43)`
- executable SHA-256 `9bf5faa5706a26699b614714573300c4944cfb8dd6770454aea8d1c4e52bc535`
- runtime PID `95613`

Human observations relevant to Task 042:

- overall reaction speed is acceptable;
- the prior stuck-Doubao-waveform-after-release symptom was not reproduced;
- whenever the Doubao voice bar actually appears, speech is accepted;
- the prior waveform-without-RemoteOrbit-audio failure was not reproduced;
- rapid re-press ownership/candidate crossover failures from Task 042 were not reproduced;
- an extreme press can still arrive while the prior IME/session is cleaning up and fail to reopen Doubao, but the next press works after cleanup.

The remaining user-visible defect is now separated from Task 042: RemoteOrbit can display its own voice HUD state even when Doubao has not actually entered a listening/capture state. This is classified as receiver-readiness / HUD truth mismatch rather than a BLE/AudioPipe ownership failure.

Task 042 remains unmerged/unreleased. This control transition does not merge, tag, release, create Gate F, mutate driver/TCC/CoreAudio, or change product source.

## Task 043 design authority

Durable design: `docs/design/2026-10-31-043-ime-readiness-prompt-sync.md`.

Verified current architecture facts:

- `VoicePressCoordinator.State.streaming` is a RemoteOrbit transport/session state, not proof that the external IME is listening.
- `AppController.updateVoiceHUD` currently maps `.streaming` directly to the green `recording` HUD state.
- `voicePress.onRemoteAudioChanged(true)` also directly shows the green `recording` HUD state.
- `RemoteActionHUDState.recording` renders the user-facing title `正在语音中`.
- `AudioPipe` starts and keeps its own CoreAudio IOProc running for `RemoteOrbit Mic 2ch`, so device-level `kAudioDevicePropertyDeviceIsRunningSomewhere` cannot be treated as external-consumer readiness.
- The package deployment target remains macOS 13.

External platform research relevant to the design:

- modern Core Audio exposes process objects and per-process `isRunningInput` state;
- process-object/device properties are only available on newer macOS versions, so any observer must be availability-gated and preserve macOS 13 compatibility;
- input-scoped process/device reporting must be runtime-validated before it is trusted because the platform has known edge-case behavior when processes switch devices while streaming.

## Selected direction

Task 043 is a truth-layer/HUD-synchronization task, not a new voice-pipeline corrective.

Selected architecture:

1. introduce a read-only `VoiceReceiverReadinessObserver` that attempts to detect an external process actively consuming `RemoteOrbit Mic 2ch`;
2. keep `VoicePressCoordinator`, BLE ownership, AudioPipe routing, 350 ms tail, 180 ms debounce and Task 042 rapid-repress semantics unchanged;
3. make AppController own the projection from local voice state + remote-audio availability + receiver readiness into the HUD;
4. never show a user-facing `正在语音中` claim solely because RemoteOrbit reached `.streaming` or `AUDIO_FIRST`;
5. do not add a fixed cooldown, trigger retry, trigger delay, Doubao-specific Accessibility scraping, unified-log scraping, or admission gating in Task 043;
6. if the Core Audio process signal is unsupported or unreliable, fall back to a truthful local state such as `音频已就绪` / `等待输入法`, not a false external-listening claim.

## Next

Implementation is not yet authorized. The next safe action is user review of the Task 043 design, followed by a bounded construction card if approved.
