# CURRENT_STATUS

Last updated: 2026-11-01
State: `RO-DIAGNOSTICS-LEGACY-RETIREMENT-045 — WAITING_FOR_INDEPENDENT_WEB_AUDIT`
Repository: `Lost0rz/RemoteOrbit`
Task 043: `MERGED / HUMAN_ACCEPTANCE_DEFERRED / USER-OWNED`
Task 045 overall: `ACTIVE`
Task 045A: `DIAGNOSTICS_GATING / CORRECTIVE_COMPLETE / WAITING_FOR_INDEPENDENT_WEB_AUDIT`

## Independent Web audit

Audit target observed at review time:

- PR `#31` (`OPEN / DRAFT`)
- base `main@fb4f8fd34015bb7aee9b8700068fe9f51ffc76d9`
- reviewed head `856fcb065ab94ae01e210df7fa55561a4cfcf11a`
- live `main` remained at the same base during audit
- final reviewed CI run `41214430041` succeeded on `remoteorbit-macmini` against the PR merge ref; full Swift tests were `656/656`, native Release build passed, and Universal2 packaging reported `x86_64 arm64`

Audit independence: `FRESH_CONTEXT` (not a separate agent and not human acceptance).

## Independent Web audit verdict (historical)

`STOP — REQUIRED CORRECTIVE BEFORE MERGE`

The core diagnostics gate is sound and the current LONG-only regressions remain green, but two acceptance contracts are not fully closed:

1. **Runtime diagnostics observer lifecycle is incomplete.**
   `FrontmostApplicationDiagnosticsObserver` is created/stopped only by application launch/termination. A runtime logging toggle does not start it when diagnostics changes OFF→ON and does not stop/unregister it when diagnostics changes ON→OFF. This leaves diagnostic-only notification observation active after disabling and leaves that diagnostic producer absent after runtime enabling.

2. **Recording independence lacks the required direct combination test.**
   The Wave A contract requires recording to remain functional with ordinary diagnostics OFF. Existing `WavRecorderDiagnosticsTests` force diagnostics ON in `setUp`; the new gate test only proves that setting `recordingEnabled = true` does not itself enable diagnostics. It does not exercise an actual WAV/RAW recording lifecycle with diagnostics OFF.

### Non-blocking observations

- Startup still performs a small amount of diagnostic-only metadata work before the structured logger's disabled guard (selected-input registry lookup and run-start calibration/field construction). This is finite one-time work, not a persistent writer/timer. It should be removed in the same corrective if it can be done without widening the voice/runtime boundary, but it is not the primary STOP reason.
- Final branch-control text records the prior handoff SHA/run rather than the later evidence-refresh head/run. Independent Web audit bound the actual final head and CI directly, so this is bookkeeping rather than semantic evidence loss; refresh controls atomically at the next handoff.

## Corrective boundary

Continue in the existing Task 045A branch/worktree/PR. Do not create a successor task or new PR solely for this corrective.

Authorized product mutation is limited to:

- make the frontmost-application diagnostic observer follow the effective diagnostics runtime gate safely for launch and runtime ON/OFF transitions;
- add direct regression coverage proving recording ON still writes/finalizes WAV/RAW while diagnostics are OFF and structured recording metadata remains suppressed by the diagnostics gate;
- remove the finite startup-only diagnostic metadata work while diagnostics are OFF if this remains a local diagnostics-only change;
- update focused tests and the two control files atomically for the next handoff.

Still frozen: Persistent/Dual retirement, microphone SHORT product/config removal, LONG-only semantics, BLE/ATVV, HID mapping correctness, AudioPipe transport/buffer/IOProc, receiver-readiness architecture, app installation, driver/CoreAudio/TCC mutation, tag/release, and merge.

## Corrective execution

Fresh reconciliation started from the audited control head `fceda599da15d48d743e4efb162e396704d45f03` on the existing branch/worktree. The bounded corrective implementation was committed as `cb427c49fc594df6ceddbc202d3c589ae637653a` and pushed to the existing PR branch.

Changed product/test paths:

- `remote-orbit/Sources/RemoteOrbit/Diagnostics/FrontmostApplicationDiagnosticsObserver.swift`
- `remote-orbit/Sources/RemoteOrbit/main.swift`
- `remote-orbit/Tests/RemoteOrbitTests/FrontmostApplicationDiagnosticsTests.swift`
- `remote-orbit/Tests/RemoteOrbitTests/WavRecorderDiagnosticsTests.swift`

The observer now has one gate-owned lifecycle coordinator: OFF→ON creates and starts one observer, ON→OFF stops and releases it, and repeated same-state requests are idempotent. Startup selected-input lookup and P1A4 run-start calibration/fields now execute only when diagnostics are enabled. The recording regression uses the real BLEBridge/WavRecorder lifecycle: diagnostics OFF + recording OFF creates no files; diagnostics OFF + recording ON writes and finalizes valid WAV/RAW files while shared diagnostic authority work metrics remain unchanged.

Local verification:

- frontmost lifecycle focused suite: `6/6`;
- recording diagnostics suite: `8/8`;
- existing diagnostics gate suite: `5/5`;
- LONG-only/current gesture regression suite: `51/51`;
- full `swift test`: `658/658`;
- `swift build -c release`: passed.

Durable machine verification for the corrected product head:

- CI run `41257070849`, attempt `2`, job `124702797074`;
- runner `remoteorbit-macmini`, macOS `26.6.2`, arm64, Apple Swift `6.4.2`;
- source contract checks, protocol self-tests, full Swift `658/658`, native Release build, and build-only packaging smoke all passed;
- Universal2 packaging reported executable architectures `x86_64 arm64`.

The first attempt of this same run exited with XCTest signal 5 after all reported test cases passed; the failed job was rerun without code changes and the retry passed all stages. This remains a machine-runner flake, not a product assertion failure.

Forbidden mutation receipt: Persistent production state `NO`; Dual Receiver `NO`; app/driver/CoreAudio/TCC installation or mutation `NO`; tag/release `NO`; merge `NO`.

## Next gate

The same PR #31 remains `OPEN / DRAFT` on the existing branch. Web must perform a fresh independent audit of the corrected exact head before any merge decision. Current stop state is `WAITING_FOR_INDEPENDENT_WEB_AUDIT`.
