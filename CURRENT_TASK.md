# RemoteOrbit Current Task

## RO-DIAGNOSTICS-LEGACY-RETIREMENT-045 — Wave B / Domain 6 Local Microphone Capture Retirement

Status: `WAITING_FOR_INDEPENDENT_WEB_AUDIT`
TASK_CLASS: `BOUNDED LEGACY RETIREMENT`
Repository: `Lost0rz/RemoteOrbit`
Design authority: `docs/design/2026-11-01-045b-domain-6-local-microphone-capture-retirement.md`
Human runtime/UI acceptance: `PENDING / USER-OWNED`

## Implementation handoff evidence

Domain 6 implementation is complete on branch `codex/task045b-domain6-local-microphone-capture-retirement`:

- pre-mutation gate: fresh live `main@c6976aa5e4db799747e7f86ba9c8278cbe051241` matched authority; control-only CI run `41272632076` / job `124748359282` final `SUCCESS` on `remoteorbit-macmini`;
- implementation HEAD: `84bd468ad9059b0313f07e905f169b1d41cd53e2` (single commit, direct child of `c6976aa`);
- Draft PR #37 created, not merged, not made Ready;
- exact-head durable PR CI run `41275976852` / job `124758115909` `SUCCESS` on `remoteorbit-macmini` through source contracts, protocol self-tests, full Swift tests, Native Release and Universal2 build-only packaging smoke;
- local verification: focused suites green, full `swift test` 509/509, `swift build -c release`, `git diff --check` clean, local Universal2 packaging `x86_64 arm64` with no `NSMicrophoneUsageDescription`;
- Domain 5 worktree retired after clean + merged-ancestry confirmation; branch/history preserved.

Final PR head, remote equality and post-push CI must be re-resolved from GitHub at independent audit time; this control commit does not encode its own SHA.

## Domain execution rule

Legacy retirement remains serial:

`Web audit/freeze → local cleanup → Web exact-head audit → merge/closeout → next domain`

Domain 6 was audited and designed by Web; local execution performed freshness/identity reconciliation, implementation and verification only. The frozen boundary below records what was executed; it is not re-opened for local redesign.

## Domain 6 purpose

Retire RemoteOrbit's obsolete local/external microphone AVCapture pipeline and microphone-TCC requirement while preserving the current user-facing system input selector and the remote-only LONG voice path.

The user-selected system input is a persistent preference, not a local-capture source. A remote LONG temporarily leases the system default input to `RemoteOrbit Mic 2ch`; the saved preference is restored only after the final remote PCM output drain, with the lease transferred across an immediate direct rapid-repress successor.

## Executed mutation summary

### `remote-orbit/Sources/RemoteOrbit/AudioPipe.swift`

Retired: `AVFoundation`/`CoreMedia` imports; `AVCaptureAudioDataOutputSampleBufferDelegate` conformance; `AVCaptureSession`, capture queue and local permission/request state; `setLocalMicrophoneCaptureEnabled(...)`; permission request logic; start/stop/configuration helpers; sample-buffer `captureOutput(...)` local PCM path; `scheduledMacBuffers` and directly-owned local diagnostics branches; the AudioPipe-side loopback name filter used only for capture discovery; the restore-at-`setRemoteActive(false)` branch gated on the retired local-capture flag; the unused `outputChannels` constant.

Preserved: remote producer, prebuffer/candidate, fixed-capacity ring, playout reserve, IOProc/render path, output drain, realtime diagnostics, remote timing behavior, startup/driver-reload `applyPreferredInputSelection()`, and temporary `selectRemoteOrbitInputForVoice()` at route activation.

### Temporary system-input lease (executed)

`VoicePressCoordinator` owns the lease via injected `onRemoteInputLeaseRelease` wired to `SystemAudioDeviceManager.applyPreferredInputSelection()`:

1. promoted remote LONG selects `RemoteOrbit Mic 2ch` (unchanged route activation) without overwriting the saved preference;
2. transport stop / `setRemoteActive(false)` does NOT restore;
3. at post-drain direct-session completion the lease transfers to an immediate direct successor (registered rapid repress, pending hardware repress, or live replacement physical candidate epoch);
4. otherwise the persisted preferred input is restored exactly once (bounded; saved RemoteOrbit preference idempotent);
5. a lease retained for a successor that dies without promoting is released at that successor's end boundary (candidate cancel/failure, pending-repress release before activation, pre-HID epoch end, coordinator stop).

No restoration was placed inside `AudioPipe.setRemoteActive(false)`.

### `AudioPipeRealtime.swift` / audio diagnostics

Removed only the compile-local, behavior-equivalent local-microphone render state that became permanently false after capture deletion (`localMicrophoneActive`, `.localMicrophone` render state/marker). `FixedCapacityPCMFrameRing`, remote queue attribution and `AudioPipePCMSource.local` remain untouched, frozen for Wave D.

### Packaging / docs

`NSMicrophoneUsageDescription` removed from `remote-orbit/Packaging/Info.plist`. README/SETUP current operational wording updated for no-microphone-TCC and the temporary input lease; historical records untouched.

### Tests

Added `RemoteVoiceInputLeaseTests` (5 deterministic injected-seam tests) and `LocalMicrophoneCaptureRetirementContractTests` (3 source/plist contracts). Removed obsolete `testLocalMicrophoneRenderIsExcludedFromRemoteDiagnostics`. No test mutates host default input, driver, CoreAudio or TCC state.

## Explicit KEEP boundary (unchanged authority)

Menu-bar `输入设备`/`输出设备` functionality; persisted preferred system input/output settings and device filtering; `RemoteOrbit Mic 2ch` temporary voice selection; Gate-A LONG-only candidate and `holdActivationThreshold == 0.30`; SHORT `<300 ms` absolute no-op and LONG `>=300 ms` direct voice contract; `.opening/.streaming/.draining` direct lifecycle; direct rapid LONG/release/LONG ownership and pending repress; short-discard tombstone, mapped-edge suppression and suppression handoff; hardware Option ownership/held-UP acknowledgement and synthetic fallback; pre-HID candidate; BLE READY/reuse, ATVV, codec, gain, sample rate; AudioPipe remote candidate/prebuffer/ring/playout reserve/IOProc/render/output drain/post-release grace; receiver readiness; Task 045A diagnostics gating and independent debug recording; primary profile/mapping authority.

## Verification results

Focused suites green: `AudioPipeTests`, `AudioPipeRealtimeTests`, `AudioDataPlaneMeasurementBoundaryTests`, `AudioDeviceManagerTests`, `VoicePipelineSimplificationTests`, `VoicePressCoordinatorTests`, `PrimaryVoiceRuntimeTests`, `VoiceKeyFilterTests`, `RemoteVoiceInputLeaseTests`, `LocalMicrophoneCaptureRetirementContractTests`, plus BLE/diagnostics/readiness suites (`BLEBridgeTests`, `DiagnosticsRuntimeGateTests`, `VoiceReceiverReadinessTests`, `AudioDataPlaneDiagnosticsTests`, `AudioPipePlayoutReserveTests`, `DiagnosticHardeningTests`).

Full `swift test`: 509/509. `swift build -c release`: pass. `git diff --check`: clean. Durable CI run `41275976852` / job `124758115909` on `remoteorbit-macmini`: `SUCCESS` including Universal2 build-only packaging smoke. Local packaging smoke: `x86_64 arm64`, packaged plist without microphone permission.

Scope-mutation flags: LONG-only semantics — unchanged; BLE/ATVV — unchanged; remote AudioPipe realtime — unchanged (compile-local dead-state deletion only, behavior-equivalent); primary mapping — unchanged; live install/driver/CoreAudio/TCC/default-device — none.

## Workspace / delivery (state)

Branch `codex/task045b-domain6-local-microphone-capture-retirement`; worktree clean and remote-synced; Draft PR #37 open. This control handoff commit updates `CURRENT_STATUS.md` and `CURRENT_TASK.md` atomically.

## Next gate

Independent Web exact-head audit of Draft PR #37. Only after that audit PASS may the PR be made Ready and merged, followed by post-merge main CI and the next domain freeze — each as its own authorized transition.

## Stop

Local execution stops at:

`WAITING_FOR_INDEPENDENT_WEB_AUDIT`

Do not start Wave D, install the app, mutate live driver/CoreAudio/TCC/default devices, tag/release or merge locally.
