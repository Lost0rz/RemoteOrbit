# RemoteOrbit Current Task

## RO-IME-READINESS-PROMPT-SYNC-043 — Receiver Readiness / HUD Truth

Status: `WAITING_FOR_INDEPENDENT_WEB_AUDIT`

Repository: `Lost0rz/RemoteOrbit`
Active branch: `codex/ime-readiness-prompt-sync-043`
Merged main baseline: `e090bd74692c44996c1e9d0a08c28512ec2bc92c`
Design authority: `docs/design/2026-10-31-043-ime-readiness-prompt-sync.md`
Audited implementation: `9c4187590065fb8a01b6ef3f356baaf30265d068`

## Objective

Make the voice HUD truthful about external IME listening without reopening Task 042 transport/audio ownership.

## Accepted implementation semantics

Keep the existing Task 043 design:

- `VoicePressCoordinator` remains transport/session authority only;
- `VoiceReceiverReadinessObserver` is read-only;
- external listening truth requires a process other than RemoteOrbit with active input IO and input-scoped membership for `RemoteOrbit Mic 2ch`;
- `.streaming`, `AUDIO_START`, `AUDIO_FIRST`, or remote-audio availability alone must never produce green `正在语音中`;
- unsupported/untrusted observer state must project conservatively to non-green HUD states.

## Authorized corrective

Implement the smallest correction for observer observation-authority failure handling.

Required semantics:

1. A durable `.inactive` / `.listening` state may be published only after the observer has established the listener authority required to observe subsequent truth changes.
2. If the system process-list listener cannot be installed, stop trusted evaluation and publish/retain `.unsupported`.
3. For each process whose snapshot can affect readiness, failure to establish the required running-input/device listeners must not allow that snapshot to become durable `.listening` truth.
4. If observation authority is lost or cannot be refreshed safely, degrade to `.unsupported` (or equivalent explicit untrusted state) and ensure the HUD becomes non-green.
5. Correct Core Audio process-object availability checks to the actual supported boundary (`macOS 14.2+`) while preserving `.macOS(.v13)` deployment compatibility.
6. Do not change the accepted HUD state model or Task 042 behavior.

## Required deterministic regressions

Add testable seams as narrowly as necessary and prove at minimum:

- initial process snapshot would evaluate to listening, but system listener installation fails -> final observer truth is unsupported/non-listening;
- process snapshot would evaluate to listening, but one required process listener cannot be established -> it cannot produce durable listening truth;
- established listening followed by observation-authority failure/loss -> state falls back to unsupported/non-green;
- unsupported observer + local streaming/audio-ready never yields green `recording`;
- existing evaluator/HUD tests remain green.

Do not make tests depend on real Doubao or live Core Audio process objects for the deterministic failure paths.

## Expected product-source scope

Normally limited to:

- `remote-orbit/Sources/RemoteOrbit/VoiceReceiverReadiness.swift`;
- `remote-orbit/Tests/RemoteOrbitTests/VoiceReceiverReadinessTests.swift`;
- control files at completion.

`main.swift` and `RemoteActionHUD.swift` should not need product changes for this corrective. If they do, keep changes strictly limited to representing observer trust loss; if broader behavior changes appear necessary, STOP.

Do not modify `BLEBridge.swift`, `AudioPipe.swift`, ATVV, driver code, HID ownership/debounce, or the package deployment target.

## Explicit non-goals

No fixed cooldown, trigger retry/replay, trigger delay, admission gating, speech buffering, Doubao-specific hardcoding/private API/AX/log scraping, driver/CoreAudio/TCC mutation, package/install/runtime replacement, merge/tag/release/Gate F.

## Verification

At minimum:

- new observer-authority failure regressions;
- all existing Task 043 readiness/HUD tests;
- Task 042 focused regressions;
- full Swift tests;
- arm64 Release;
- x86_64 Release;
- protocol self-tests;
- `git diff --check`;
- `.macOS(.v13)` unchanged;
- no `BLEBridge.swift` or `AudioPipe.swift` product diff.

## Corrective evidence

The pre-corrective deterministic RED run executed 13 authority/readiness tests with 6 assertion failures: system listener failure returned `listening` instead of `.unsupported`; partial process listener authority returned `listening`; and authority loss after listening remained `listening` and projected green `recording`.

The corrective now makes system process-list listener installation explicit, requires complete per-process running-input and input-device listener authority before publishing durable `.inactive` or `.listening`, and degrades refresh/authority loss to `.unsupported`. The availability boundary is `macOS 14.2+` while `Package.swift` remains `.macOS(.v13)`.

GREEN evidence: authority/readiness tests `13/13`; Task 042 focused suites `34/34`, `51/51`, `53/53`; full Swift test `623/623`; arm64 Release `arm64`; x86_64 Release `x86_64`; protocol self-tests `3/3`; `git diff --check` passed. `BLEBridge.swift`, `AudioPipe.swift`, `main.swift`, `RemoteActionHUD.swift`, ATVV, driver/TCC, and Task 042 ownership/timing have no product diff. No package/install/runtime replacement, merge/tag/release, or Gate F was performed. Human UI acceptance remains `PENDING`.

## Completion

The bounded corrective and required verification completed on the existing Task 043 branch. `CURRENT_STATUS.md` and `CURRENT_TASK.md` are updated together below in the delivery commit. After push, local/remote equality and a clean worktree will be verified, then the task stops at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`.

Next action: independent Web source audit of the exact pushed corrective. Do not package/install or claim human UI/runtime acceptance before that audit.

Do not package/install or claim human UI/runtime acceptance before the next independent source audit.
