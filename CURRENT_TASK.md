# RemoteOrbit Current Task

## RO-VOICE-PIPELINE-SIMPLIFICATION-042 — HOST_MIC_OPEN Rapid Re-press Corrective

Status: `SOURCE_AUDIT_PASS / HUMAN_RUNTIME_ACCEPTANCE_PENDING`

Repository: `Lost0rz/RemoteOrbit`
Active branch: `codex/voice-pipeline-simplification-042`
Accepted corrective source before this remaining edge: `b1736f2feedd7ed13e4520ecdfaa0c6bf6e9b332`
Evidence/design record: `docs/incidents/2026-10-30-042-host-mic-open-rapid-repress.md`
Frozen 041 observability baseline: `ac3132986197bfee4440bb8f388e3d2e5f478f03`
Admission-atomic source corrective: `ea126c4c1742bfb3aa5e800e0cf7023771a5b08f`
Independent Web source-audit PASS target: `6fb609ea9fdda31cbe7dbd87b78c64839e47a065`

## Objective

Fix the final evidence-confirmed rapid re-press edge without changing the accepted steady-state PHYSICAL_HTT path.

Two observed failures (`09B0`, `BAFD`) occur when a new explicit physical `AUDIO_START reason=0x03` arrives before the prior released HOST_MIC_OPEN request/grace has retired. Current state then makes the new physical stream look host/session-owned and the matching HID press is rejected `voice_session_busy`.

The source corrective is now independently accepted. The remaining Task 042 gate is human RC003 runtime acceptance using a freshly built/installed app candidate containing the audited product source.

## Required corrective model

### A. BLE host-grace supersession

Track enough session-specific host-MIC_OPEN ownership to distinguish a released host request from the incoming physical stream.

When all are true:

1. incoming `AUDIO_START reason == 0x03`;
2. a previous HOST_MIC_OPEN owner is still represented by a matching waiting post-release grace;
3. that owner has observed physical release;
4. no old AUDIO_STOP drain barrier is active;

then, before assigning incoming stream identity:

- cancel the matching old grace / invalidate its delayed callback;
- retire only that old host voice intent locally (`voiceInputRequested`, `micOpenRequested`);
- do not send MIC_CLOSE for the superseded host request;
- publish the truthful terminal streaming=false boundary for the old coordinator owner when it still needs transport-stop retirement;
- retain READY;
- process the incoming reason=0x03 stream as `preHIDPhysical` candidate ownership.

The rule is explicit physical-start supersession, not a global UNKNOWN remap.

### B. Direct-session re-press serialization

A new direct HID DOWN may arrive while the previous direct session is still completing output drain/trigger release after supersession.

For exactly this terminal-overlap case:

- retain at most one pending direct re-press instead of returning `voice_session_busy`;
- require the previous direct session to have physical UP already observed / be in terminal retirement;
- require a live pre-HID physical candidate for the new press;
- capture the new session ID, `VoiceInputProfile`, and hardware/synthetic trigger mode;
- do not emit the new trigger DOWN or activate a route while the old session still owns output drain/trigger UP;
- when `completeDirectVoiceSession` finishes the old session, activate the retained new press on the next main-queue turn and adopt the candidate;
- if HID UP for the pending press arrives before activation, cancel that pending press cleanly with no trigger leak and no stale adoption.

Do not permit two simultaneous direct sessions.

### C. Hardware-mapped direct re-press serialization

When the direct pending branch is entered with `usesHardwareOption == true`,
the old direct session and the new pending press may temporarily own different
edges only:

- `OLD_HELD_UP_OWNER` retains the old mapped UP components and replay/pass acknowledgement.
- `NEW_PENDING_DOWN_OWNER` captures and suppresses only the new mapped DOWN components.

The new owner must be armed before its mapped DOWN can pass. It must not reuse
`beginOptionDeferral(newSession)` while the old held-UP owner exists, because
that operation treats the old owner as stale and aborts it. The old UP replay
must pass the event-tap acknowledgement boundary before the new owner is
promoted on a fresh main-queue turn. Promotion replays the captured B DOWN
through the existing event path and does not emit a synthetic trigger.

If B's raw HID UP arrives before promotion, discard captured B DOWN and retain
only a bounded tombstone that consumes the expected mapped UP components. Keep
exactly one pending direct owner. Synthetic re-presses continue through the
existing synthetic ordering path, and normal non-overlap hardware presses keep
their existing gate/output-drain ordering.

## MIC_CLOSE rule

For the superseded host request, **do not send MIC_CLOSE after the new physical reason=0x03 stream has arrived**. ATVV v1.0 MIC_CLOSE is stream-ID-bearing, while `streamID` becomes the incoming physical stream ID; a delayed close can terminate the new stream.

Normal non-superseded HOST_MIC_OPEN behavior remains unchanged:

- if no superseding physical start occurs, existing post-release grace remains;
- grace expiry still retires the host request and sends exactly one MIC_CLOSE where appropriate;
- the existing no-AUDIO-START terminal `notifyStreaming(false)` path remains.

## Required deterministic tests

At minimum cover:

1. `HOST_AUDIO_STOP_DRAINED_THEN_REASON03_BEFORE_HID_SUPERSEDES_HOST_GRACE` — reproduce `09B0`: no busy reject, no old MIC_CLOSE, incoming ownership preHIDPhysical, matching HID admitted/adopted.
2. `HOST_NO_TERMINAL_STREAM_THEN_REASON03_DURING_RELEASE_GRACE_DEFERS_DIRECT_REPRESS` — reproduce `BAFD`: old direct session terminally retires, new HID is retained while old output drain completes, then admitted/adopted.
3. `SUPERSEDED_HOST_GRACE_CALLBACK_CANNOT_CLOSE_NEW_PHYSICAL_STREAM`.
4. `SUPERSEDED_HOST_REQUEST_RETAINS_READY`.
5. `NORMAL_HOST_NO_AUDIO_START_GRACE_STILL_SENDS_ONE_MIC_CLOSE_AND_TERMINAL_STOP`.
6. `NORMAL_HOST_AUDIO_START_REASON_NOT_03_IS_NOT_SUPERSEDED`.
7. `REASON03_WITHOUT_RELEASED_HOST_GRACE_DOES_NOT_APPLY_HOST_SUPERSESSION_RULE`.
8. `PENDING_DIRECT_REPRESS_RELEASE_BEFORE_ACTIVATION_CLEARS_WITHOUT_TRIGGER_LEAK`.
9. `ONLY_ONE_PENDING_DIRECT_REPRESS_ALLOWED`.
10. `PREVIOUS_DIRECT_OUTPUT_DRAIN_AND_TRIGGER_UP_COMPLETE_BEFORE_NEW_TRIGGER_DOWN`.
11. Existing adopted-PHYSICAL rapid-cycle tests remain green.

Hardware-mapped edge cases added for this continuation:

12. `testHardwareDirectRepressCapturesNewDownBeforeOldUpRetires`.
13. `testHardwareOldUpAcknowledgedBeforePendingNewDownRelease`.
14. `testHardwarePendingRepressReleaseBeforeActivationHasNoTriggerLeak`.
15. `testHardwareOnlyOnePendingDirectRepressOwner`.
16. `testHardwarePendingRepressPreservesNormalHardwareOutputOrdering`.
17. `PROMOTED_HARDWARE_REPRESS_FULL_LIFECYCLE` — promoted B owns physical UP, mapped UP, output-drain replay, and replay-pass acknowledgement before retirement.
18. `ADMISSION_BLOCKED_PROMOTED_HARDWARE_REPRESS_ROLLBACK` — blocked admission causes no B DOWN replay, no held-UP owner, no stale hardware gate, no coordinator ownership leak, and bounded pending tombstone cleanup.

Run relevant BLEBridge, VoicePipelineSimplification/direct-session, VoiceBoundaryOrdering, VoiceTriggerRuntime, PostReleaseCaptureGrace, AudioPipe/realtime/reserve and ATVV protocol tests, full Swift tests, arm64/x86_64 Release builds, protocol self-tests, and `git diff --check` when product source changes. No further product-source mutation is authorized by the runtime-preparation step unless new evidence requires STOP/reconciliation.

## Runtime acceptance authorization

The independent Web source audit is PASS. The next bounded action is authorized:

- fetch/reconcile the existing 042 branch and verify the current HEAD is a control-only descendant of the accepted source state, with no product-source drift after the audited product source;
- build/package the latest `RemoteOrbit.app` candidate using the repository's existing app build/install flow;
- replace/update the installed RemoteOrbit application used for testing;
- do **not** reinstall, rebuild, unload, or otherwise mutate the audio driver;
- do **not** reset or mutate TCC/privacy permissions;
- launch the freshly installed app and verify process/bundle identity sufficiently to prove the new candidate is running;
- stop at `READY_FOR_HUMAN_RUNTIME_ACCEPTANCE` so the user performs the RC003 hardware rapid re-press test;
- preserve/capture runtime logs for post-test evidence review.

Human acceptance itself remains user-owned. The local agent must not claim runtime PASS from build/install or simulated interaction.

## Explicitly not authorized

Do NOT:

- globally remap UNKNOWN;
- treat every reason=0x03 as supersession without the matching released host grace;
- send old MIC_CLOSE after installing the new physical stream ID;
- overlap two direct session trigger owners;
- remove/shorten host grace globally;
- disconnect per session;
- change long-lived READY or strict READY;
- change ATVV codec/framing;
- change Gate C ring;
- change Gate D 45 ms reserve;
- change/reinstall the audio driver;
- reset/mutate TCC;
- add broad probes;
- make new product-source changes during runtime preparation without STOP/reconciliation;
- merge/tag/release;
- create Gate F.

If the runtime preparation cannot preserve these boundaries, STOP and report the dependency instead of broadening scope.

## Required return

For runtime preparation return actual evidence including:

- `CARD_ID`, `TASK_ID`, `MODE`, `CAPABILITY`, `TARGET`, `OUTCOME`;
- governance route / skills / topology / subagents;
- start/final/local/remote identity;
- product-source equivalence/drift check against the audited source state;
- build/package/install commands and exit results;
- installed app path, bundle version/build and running process identity;
- confirmation driver/TCC were untouched;
- log/runtime evidence location;
- control alignment / unresolved / next safe action.

After successful runtime preparation, update `CURRENT_STATUS.md` and `CURRENT_TASK.md` together only if needed to record `READY_FOR_HUMAN_RUNTIME_ACCEPTANCE`, push only the existing 042 branch, verify local/remote equality, and stop for user testing. No merge/tag/release before human runtime acceptance and subsequent evidence reconciliation.

## Observed execution evidence

### Hardware-mapped rapid re-press continuation

- Stage A result: `FINDING_CONFIRMED`. At start, local and remote branch HEAD were both `9cae6c60f2f0fafaa2e27b49dd5a0fdcb646c93e`, the canonical writer was `/private/tmp/remoteorbit-voice-pipeline-simplification-042`, and the worktree was clean.
- The production path passes `usesHardwareOption=isVoiceHIDMappingEnabled()`. Before this continuation, the direct pending branch returned without hardware capture ownership; existing `beginOptionDeferral(newSession)` would abort the old held-UP owner. The first RED test observed `pass` instead of a captured B mapped DOWN.
- The corrective adds explicit old-UP/new-DOWN ownership serialization in `main.swift`, including old replay pass acknowledgement gating, fresh-turn B promotion, early-UP tombstone suppression, and one-slot enforcement. No BLE semantic change was needed; `BLEBridge.swift` did not change.
- Hardware deterministic cases: `5/5`; focused requested suites: `238/238`; full Swift tests: `595/595`.
- Final commands and evidence:
  - `swift build -c release --scratch-path /private/tmp/remoteorbit-042-arm64-release --triple arm64-apple-macos14.0` — exit `0`.
  - `swift build -c release --scratch-path /private/tmp/remoteorbit-042-x86-release --triple x86_64-apple-macos14.0` — exit `0`.
  - `./run-self-tests.sh` — exit `0`.
  - `git diff --check` — exit `0`.
- No runtime retest, driver/TCC change, merge, tag, release, or Gate F action was performed.

- Audited start control HEAD: `3d0ae437bb43efaca529a7278de519141a65d31d`; live remote remained equal after fetch/reconcile before control update.
- The corrective is implemented within the authorized boundary. HOST_MIC_OPEN supersession is reason `0x03` plus matching released host grace, physical release, and no active AUDIO_STOP drain; it locally retires only the old host intent, cancels its grace callback, suppresses its MIC_CLOSE, preserves READY, and admits the incoming stream as `preHIDPhysical`.
- Direct re-press serialization uses exactly one pending direct slot containing the new session ID, profile, and hardware/synthetic trigger mode. It waits for old output drain and trigger UP, preserves the live pre-HID candidate, activates on the next main-queue turn, and cancels cleanly on an early pending HID UP.
- New deterministic tests passed: 9/9. Affected focused suites passed: 217/217. Full Swift tests passed: 590/590.
- arm64 Release build passed with the repository flow equivalent command:
  `swift build -c release --scratch-path /private/tmp/remoteorbit-042-arm64-release --triple arm64-apple-macos14.0`.
- x86_64 Release build passed with:
  `swift build -c release --scratch-path /private/tmp/remoteorbit-042-x86-release --triple x86_64-apple-macos14.0`.
- Protocol self-tests passed 3/3. `git diff --check` passed.
- Product source/test changes are limited to the five paths listed in `CURRENT_STATUS.md`; no packaging script changed.
- No driver/TCC mutation, runtime retest, merge, tag, release, or Gate F action was performed.

### Promoted-B hardware-owner continuation

- Stage A finding: `FINDING_CONFIRMED` against audited source/control HEAD `d54bfd56a3f098766ed1013116928e1f77822277`. `promotePendingHardwareOptionRepress(B)` replayed the captured B DOWN but established neither the existing hardware gate resolution nor B's held UP/output-drain owner. The deterministic pre-fix test observed B mapped UP as `pass` and no B replayed UP.
- Implemented only the existing-model correction: promotion resolves the captured B DOWN through `HardwareOptionGate` as physical hardware replay, records B in `heldHardwareOptionSessionID`, and posts B DOWN before the matching physical-UP arm. The existing output-drain/replayed-UP acknowledgement boundary then retires B.
- Full promoted-B lifecycle test: RED `1 test / 3 assertion failures`; GREEN `1/1`, covering `B_DOWN → B physical UP → held B mapped UP → B output drain → replayed B mapped UP → pass acknowledgement → idle`.
- Focused requested suites: `239/239`; full Swift tests: `596/596`.
- Release builds: arm64 and x86_64 passed with the established commands. Protocol self-tests passed `3/3`; `git diff --check` passed. Only existing macOS deprecation warnings appeared.
- Product source/test changes are limited to `remote-orbit/Sources/RemoteOrbit/main.swift` and `remote-orbit/Tests/RemoteOrbitTests/VoicePipelineSimplificationTests.swift`; no BLE semantic, driver, TCC, or runtime change was made.
- Human corrective runtime acceptance remains pending.

### Admission-atomic promotion continuation

- Stage A finding: `FINDING_CONFIRMED` against audited source/control HEAD `251536d1d46e73680140b10b2f8d6cb9d21b3e7f`. The pre-fix coordinator promoted/replayed B before the final admission guard, permitting `voice_session_busy` after B hardware ownership had already been mutated.
- Corrective ordering: `startDirectVoicePress()` resolves the existing admission guard first. Only after admission is confirmed does it call the existing pending-hardware promotion callback, which establishes B's hardware owner and replays B DOWN; the direct session is then committed. Admission rejection invokes the existing bounded pending-cancel/tombstone path before any B replay.
- RED: `testAdmissionBlockedPromotedHardwareRepressDoesNotReplayOrLeakOwnership` failed 3 assertions against the pre-fix source: B DOWN replay was present, B held-UP ownership remained, and the active hardware gate remained. GREEN: the blocked-promotion test passed `1/1`, and `testPromotedHardwareRepressOwnsMappedUpThroughOutputDrain` passed `1/1`.
- Focused requested suites: `240/240`; full Swift tests: `597/597`; both have 0 failures.
- arm64 Release: exit `0` using `swift build -c release --scratch-path /private/tmp/remoteorbit-042-arm64-release --triple arm64-apple-macos14.0`.
- x86_64 Release: exit `0` using `swift build -c release --scratch-path /private/tmp/remoteorbit-042-x86-release --triple x86_64-apple-macos14.0`.
- Protocol self-tests: `3/3`, exit `0`. `git diff --check`: exit `0`. Build warnings were limited to existing macOS deprecations.
- Product source/test changes are limited to `remote-orbit/Sources/RemoteOrbit/main.swift` and `remote-orbit/Tests/RemoteOrbitTests/VoicePipelineSimplificationTests.swift`. No BLE/protocol ownership expansion, Gate C/D change, driver/TCC/runtime change, merge, tag, release, or Gate F action occurred.
- Control transition audited at start HEAD `251536d1d46e73680140b10b2f8d6cb9d21b3e7f`; both controls were updated together in transition commit `ea126c4c1742bfb3aa5e800e0cf7023771a5b08f`, pushed only on the existing 042 branch, and verified equal to its remote ref.

### Independent Web source audit

- `AUDIT_PROFILE=CODE_DIFF`; `AUDIT_INDEPENDENCE=SEPARATE_AGENT`.
- Audit target: `6fb609ea9fdda31cbe7dbd87b78c64839e47a065`.
- Verdict: `PASS`.
- Passed: HOST grace supersession, A-UP-before-B-DOWN, pending hardware DOWN capture, promoted-B full lifecycle, admission-before-promotion, blocked-promotion no-DOWN leak, blocked-promotion no-owner leak, early-UP tombstone, and one-pending-owner behavior.
- GitHub had no independent CI status/workflow run for that HEAD; the source-audit gate accepted the code-diff based on the verified local validation receipt and direct source review.
- This PASS does not constitute RC003 runtime acceptance or merge/release approval.

## Stop state

Task 042 is `SOURCE_AUDIT_PASS / HUMAN_RUNTIME_ACCEPTANCE_PENDING`. The next safe action is app-only runtime preparation from the current 042 branch, followed by user-owned RC003 testing. Audio driver/TCC changes remain prohibited. Merge/tag/release remain blocked until human runtime acceptance and evidence reconciliation are complete.
