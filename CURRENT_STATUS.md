# CURRENT_STATUS

Last updated: 2026-10-31
State: `RO-IME-READINESS-PROMPT-SYNC-043 — WAITING_FOR_INDEPENDENT_WEB_AUDIT`
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

## Completed implementation evidence

Gate A was exercised with a disposable Core Audio process-object probe on the target host (`macOS 26.6.2`, build `25G83`, `RemoteOrbit Mic 2ch` device ID `79`, UID `RemoteOrbit Mic2ch_UID`). The probe excluded the RemoteOrbit process (`PID 95613`, bundle `com.lost0rz.RemoteOrbit`) and required `running_input=true` plus input-scoped membership for device ID `79`.

- normal Doubao listening: external process `PID 859`, bundle `com.bytedance.inputmethod.doubaoime`, matched the target device;
- Doubao stopped: no external matching process;
- rapid re-press ignored during post-processing: no external matching process;
- later successful reopen: the Doubao process matched again.

The supported signal is therefore used for the truthful HUD projection. The bounded source change is limited to `VoiceReceiverReadiness.swift`, `main.swift`, `RemoteActionHUD.swift`, and corresponding tests. `BLEBridge.swift`, `AudioPipe.swift`, ATVV, driver, TCC, and the macOS 13 deployment target are unchanged.

Verification evidence: focused readiness tests `10/10`; Task 042 focused suites `34/34`, `51/51`, and `53/53`; full Swift test `620/620`; arm64 Release and x86_64 Release builds produced the expected single-architecture executables; protocol self-tests `3/3`; `git diff --check` passed. No package, install, runtime replacement, merge, tag, release, or Gate F was performed. Human UI acceptance remains `PENDING`.

## Next

Independent Web source audit of the exact pushed 043 implementation. After that audit, retain the explicit human UI/runtime acceptance boundary; do not package/install or claim acceptance from source tests alone.
