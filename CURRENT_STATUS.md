# CURRENT_STATUS

Last updated: 2026-10-31
State: `RO-IME-READINESS-PROMPT-SYNC-043 — SOURCE_AUDIT_STOP / CORRECTIVE_REQUIRED`
Repository: `Lost0rz/RemoteOrbit`
Active branch: `codex/ime-readiness-prompt-sync-043`
Merged main baseline: `e090bd74692c44996c1e9d0a08c28512ec2bc92c`
Design authority: `docs/design/2026-10-31-043-ime-readiness-prompt-sync.md`
Audited implementation: `9c4187590065fb8a01b6ef3f356baaf30265d068`

## Predecessor Task 042

Task 042 is merged into `main` and CLOSED. Its accepted BLE/AudioPipe/pending-repress ownership model remains frozen for Task 043.

## Task 043 implementation status

The bounded receiver-readiness/HUD implementation is source-level sound in its main path:

- external receiver truth requires a non-RemoteOrbit PID, active input IO, and input-scoped membership for `RemoteOrbit Mic 2ch`;
- internal `.streaming`, `AUDIO_START`, `AUDIO_FIRST`, or remote-audio availability alone no longer produces the green `正在语音中` HUD state;
- `BLEBridge.swift`, `AudioPipe.swift`, ATVV, driver/TCC, Task 042 ownership/timing, and the macOS 13 deployment target were not changed.

Independent Web CODE_DIFF audit found one blocking observer-authority defect:

1. failure to install the system process-list listener publishes `.unsupported` but the code then continues into snapshot refresh/evaluation, which can republish `.inactive` or `.listening` without durable observation authority;
2. individual process listener registration failures are ignored while the same process snapshot may still be accepted as long-lived listening truth;
3. this allows a stale green HUD if the initial snapshot says listening but listener authority was never fully established;
4. the Core Audio process-object availability guard should use the actual API availability boundary (`macOS 14.2+`), not `14.0`.

## Authorized corrective direction

Same Task 043. Do not redesign the HUD or receiver model.

- Treat complete listener authority as a prerequisite for publishing durable `.inactive` / `.listening` truth.
- If system listener setup fails, do not continue into trusted snapshot evaluation; remain/fall back `.unsupported`.
- If required process listeners cannot be established for a process whose snapshot would otherwise affect readiness, that process must not contribute durable listening truth; observation-authority loss must conservatively remove green state.
- Correct the runtime availability gate to macOS 14.2+ while keeping the package deployment target at macOS 13.
- Add deterministic regressions for listener-installation failure and stale-listening prevention.

## Boundaries

Not authorized:

- HUD redesign beyond the accepted Task 043 states;
- BLEBridge/AudioPipe/ATVV changes;
- Task 042 state-machine changes;
- cooldown/retry/trigger delay/admission gating;
- Doubao-specific private API / AX / unified-log scraping / process-name hardcoding;
- driver/CoreAudio/TCC mutation;
- package/install/runtime replacement before the next independent source audit;
- merge/tag/release/Gate F.

## Next

Implement only the observer-authority corrective on the existing Task 043 branch, rerun focused/full verification, update controls together, push, and stop again at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`.
