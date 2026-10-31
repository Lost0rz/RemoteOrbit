# RemoteOrbit Current Task

## RO-IME-READINESS-PROMPT-SYNC-043 — Receiver Readiness / HUD Truth

Status: `IMPLEMENTATION_AUTHORIZED / READINESS_SPIKE_FIRST`

Repository: `Lost0rz/RemoteOrbit`
Active branch: `codex/ime-readiness-prompt-sync-043`
Merged main baseline: `e090bd74692c44996c1e9d0a08c28512ec2bc92c`
Design authority: `docs/design/2026-10-31-043-ime-readiness-prompt-sync.md`

## Objective

Make the RemoteOrbit voice HUD truthful when the external IME has not actually begun listening, without reopening the accepted Task 042 transport/audio ownership architecture.

## Authorized implementation

### Phase A — readiness signal spike

Implement the smallest testable/read-only Core Audio receiver observer needed to validate whether the target runtime can reliably answer:

`Is a process other than RemoteOrbit actively using RemoteOrbit Mic 2ch as an input device?`

Required behavior:

- availability-gated Core Audio process-object API usage;
- exclude the RemoteOrbit PID;
- require active input IO and input-scoped device membership matching the RemoteOrbit Mic device ID;
- represent `unsupported/unknown` explicitly;
- no polling loop in the HUD layer; observer owns bounded observation mechanics;
- no effect on voice admission, trigger timing, BLE, AudioPipe or route state.

Validate on the target environment against four cases:

1. normal IME listening -> observer must report listening;
2. IME stopped -> observer must report inactive;
3. rapid re-press ignored while Doubao is still post-processing -> observer must remain inactive;
4. later successful reopen -> observer must transition to listening.

If the signal is unsupported, unstable, or false-positive during post-processing, STOP the external-confirmation path. Continue only with truthful local HUD semantics; do not add a substitute heuristic.

### Phase B — HUD truth projection

If Phase A passes, integrate receiver readiness into AppController HUD projection.

Required presentation semantics:

- local activation starting -> `等待输入法` / pending;
- RemoteOrbit audio live but no receiver confirmed -> `音频已就绪` / non-green ready state;
- external receiver confirmed -> `正在语音中` / green recording state;
- draining/ending -> existing truthful ending state.

Regression rule: `.streaming`, `AUDIO_START`, `AUDIO_FIRST`, or `onRemoteAudioChanged(true)` alone must never produce the green external-listening claim.

`RemoteActionHUD` remains presentation-only. `VoicePressCoordinator` remains transport/session authority only.

## Expected product-source scope

Normally limited to:

- new `remote-orbit/Sources/RemoteOrbit/VoiceReceiverReadiness.swift`;
- `remote-orbit/Sources/RemoteOrbit/main.swift` for wiring/projection;
- `remote-orbit/Sources/RemoteOrbit/RemoteActionHUD.swift` for truthful voice presentation states;
- directly corresponding tests.

Do not modify `BLEBridge.swift` or `AudioPipe.swift`. If implementation appears to require those files, STOP and return evidence.

## Explicit non-goals

No fixed cooldown, automatic retry/replay, delayed trigger, buffered admission waiting, Doubao-specific process-name hardcoding, private API, Accessibility scraping, unified-log scraping, driver/CoreAudio/TCC mutation, package/install/runtime replacement, merge/tag/release/Gate F.

## Verification

At minimum:

- observer unit tests including supported/listening/inactive/unsupported states;
- HUD projection unit tests;
- regression: `.streaming` / remote audio alone cannot produce green `正在语音中`;
- regression: confirmed external consumer can produce green state;
- regression: observer unsupported/lost -> conservative non-green fallback;
- Task 042 focused regressions remain green;
- full Swift tests;
- arm64 Release;
- x86_64 Release;
- `git diff --check`;
- macOS 13 deployment target unchanged.

## Completion

If implementation and verification succeed, update `CURRENT_STATUS.md` and `CURRENT_TASK.md` together, push the existing 043 branch, verify remote equality and clean worktree, then stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`.

Do not package/install or claim human UI/runtime acceptance before that independent source audit.
