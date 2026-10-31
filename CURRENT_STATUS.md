# CURRENT_STATUS

Last updated: 2026-10-31
State: `RO-IME-READINESS-PROMPT-SYNC-043 — IMPLEMENTATION_AUTHORIZED / READINESS_SPIKE_FIRST`
Repository: `Lost0rz/RemoteOrbit`
Active branch: `codex/ime-readiness-prompt-sync-043`
Merged main baseline: `e090bd74692c44996c1e9d0a08c28512ec2bc92c`
Design reconciliation merge: `7c4ba75107e30cf3ca7110f9d61cc81842c37242`
Design authority: `docs/design/2026-10-31-043-ime-readiness-prompt-sync.md`

## Predecessor Task 042

Task 042 is merged into `main` and CLOSED. Its accepted BLE/AudioPipe/pending-repress ownership model is frozen for Task 043.

The fresh accepted candidate established:

- response speed acceptable;
- no stuck Doubao waveform after release;
- active Doubao voice bar receives RemoteOrbit audio;
- prior waveform-without-audio and old-A/new-B ownership crossover failures were not reproduced.

The remaining defect is separate: RemoteOrbit can show its voice HUD while the external IME has not actually reopened/listened.

## Task 043 authority

Task 043 is now authorized for bounded implementation, with a mandatory readiness-signal spike before the observer may control the green listening HUD.

Selected architecture:

1. keep `VoicePressCoordinator`, BLE ownership, AudioPipe routing, 350 ms tail, 180 ms debounce and Task 042 rapid-repress semantics unchanged;
2. add a read-only `VoiceReceiverReadinessObserver` outside those owners;
3. runtime-validate Core Audio process/input/device membership on supported macOS before treating it as receiver truth;
4. preserve macOS 13 compatibility with availability gating and explicit unsupported/unknown state;
5. project HUD from local voice state + remote-audio readiness + receiver readiness;
6. never show green `正在语音中` solely from `.streaming` or `AUDIO_FIRST`;
7. if the readiness signal is unsupported or unreliable, fall back to truthful local states (`等待输入法` / `音频已就绪`) and STOP the external-confirmation path rather than inventing a substitute.

## Boundaries

Not authorized:

- BLEBridge/AudioPipe ownership or timing changes;
- Task 042 state-machine changes;
- fixed cooldown;
- automatic trigger retry;
- trigger delay/admission gating;
- Doubao-specific private API / AX / unified-log scraping / process-name hardcoding;
- driver/CoreAudio/TCC mutation;
- package/install/runtime replacement before source audit;
- merge/tag/release/Gate F.

## Next

Execute the Task 043 construction card: first prove/disprove the Core Audio receiver-readiness signal on the target environment; only if reliable, connect it to HUD truth projection. Stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT` after bounded implementation and verification.
