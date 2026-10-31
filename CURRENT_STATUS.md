# CURRENT_STATUS

Last updated: 2026-10-31
State: `RO-VOICE-PIPELINE-SIMPLIFICATION-042 — SOURCE_AUDIT_PASS / HUMAN_RUNTIME_ACCEPTANCE_PENDING`
Repository: `Lost0rz/RemoteOrbit`
Active branch: `codex/voice-pipeline-simplification-042`

## Current authority

- Corrective A source remains `3d7b55cc557e52e994ff5c5a6b4c2217189f2751`.
- Corrective B callback-ordering source is `b4904f2faf26535fd39ba97d3a5dd30440de13b9`.
- Pre-audit control handoff is `34f4b5892307355948660b9de7d2e2008119e036`.
- Independent Web `CODE_DIFF` audit of Corrective B: `PASS`.
- Human RC003 runtime acceptance for the newly audited source has not yet been run. The prior installed candidate remains a historical `FAIL` and is not reused as acceptance evidence.
- Evidence/design authorities remain:
  - `docs/incidents/2026-10-30-042-host-mic-open-rapid-repress.md`
  - `docs/incidents/2026-10-31-042-rc003-runtime-owner-race.md`

## Independent source audit result

Corrective A remains source-level accepted and unchanged. The `noOptionEdge` pending-owner model still requires B mapped DOWN capture plus A terminal completion before promotion; no `main.swift` change exists in the latest corrective.

Corrective B now closes the previously blocking callback-ordering defect:

- product-source change is exactly one semantic condition in `BLEBridge.supersedeReleasedHostMicOpenGraceIfNeeded`: ordinary `notifyStreaming(false)` is emitted only when `oldSessionWasStreaming && !allowActiveDrain`;
- released HOST_MIC_OPEN active-drain replacement therefore uses the existing `onPhysicalTransportSuperseded` coordinator terminal boundary instead of first enqueueing an ordinary old-A `streaming=false` teardown;
- B is installed as `.preHIDPhysical` before the supersession callback reaches the main queue;
- the cross-component regression uses real `BLEBridge -> main queue -> VoicePressCoordinator -> AudioPipe` callbacks and proves B candidate/prebuffer remains `4 -> 4` through A terminal/output retirement;
- A still completes its terminal/output lifecycle;
- stale A grace/drain callbacks do not mutate B and MIC_CLOSE remains `0`;
- B remains adoptable as `voiceSession` and consumes the preserved prebuffer normally.

Source scope is bounded from `9907005054ff795df947b743dae15e6d9ad08671` through the implementation/control handoff to `BLEBridge.swift`, `BLEBridgeTests.swift`, `CURRENT_STATUS.md`, and `CURRENT_TASK.md`. The implementation commit itself changes only `BLEBridge.swift` and `BLEBridgeTests.swift`.

Reported implementation verification remains: focused suites 118/118 total across the listed Task 042 suites, full Swift 610/610, arm64 Release PASS, x86_64 Release PASS, ATVV self-tests 3/3, and `git diff --check` PASS. These execution results are implementation-context evidence; the independent Web verdict here is a source-level `CODE_DIFF` PASS.

## Preserved boundaries

- Normal 350 ms no-replacement tail unchanged.
- Generic 180 ms debounce unchanged.
- No Doubao post-processing delay/re-arm workaround.
- Candidate PCM isolation, transport epoch/generation protection, READY / strict READY, Gate C ring, Gate D 45 ms reserve, ATVV codec/framing unchanged.
- Driver/CoreAudio/TCC unchanged.
- No merge/tag/release/Gate F before fresh human RC003 acceptance.

## Next

Prepare a fresh App-only runtime from the existing Task 042 branch without product-source mutation. Package/install must preserve audited product source `b4904f2faf26535fd39ba97d3a5dd30440de13b9` plus control-only descendants, verify installed provenance/hash/bundle/version/architectures/PID/log availability, then stop at `READY_FOR_HUMAN_RUNTIME_ACCEPTANCE`.

Human RC003 acceptance remains user-owned. Required retest includes normal holds, rapid re-press, extreme chained re-press, waveform-without-audio, stuck waveform, missing first speech, and old-session/new-session ownership crossover. If failure occurs, preserve the fresh app and logs before restart/reinstall.
