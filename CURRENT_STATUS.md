# CURRENT_STATUS

Last updated: 2026-11-01
State: `RO-DIAGNOSTICS-LEGACY-RETIREMENT-045 — DOMAIN_6_IMPLEMENTATION_COMPLETE / WAITING_FOR_INDEPENDENT_WEB_AUDIT`
Repository: `Lost0rz/RemoteOrbit`
Human runtime/UI acceptance: `PENDING / USER-OWNED`

## Task 045 progress

- Task 045A: `DIAGNOSTICS_GATING / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 1: `LEGACY_VOICE_PRODUCT_SURFACE / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 2: `LEGACY_VOICE_PERSISTED_PREFERENCE_AUTHORITY / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 3: `PERSISTENT_VOICE_RUNTIME_STATE_MACHINE / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 4: `DUAL_RECEIVER_RUNTIME_STATE_MACHINE / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 5: `LEGACY_GENERIC_SHORT_CLASSIFIER_RUNTIME / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 6: `LOCAL_MICROPHONE_CAPTURE / IMPLEMENTATION_COMPLETE / DRAFT_PR_OPEN / WAITING_FOR_INDEPENDENT_WEB_AUDIT`

## Domain 5 independent Web audit and closeout

Audit independence: `FRESH_CONTEXT`.

- Final reviewed PR #36 head: `cbc5f981f6f72e5041739774b38f94cf1f695fea`.
- Immutable implementation HEAD: `e4c285ecbe2ad9a3a79e4dd2f01607857fdc4c37`.
- Exact-head PR CI run `41271384083`, job `124744691635`, passed on `remoteorbit-macmini` through source contracts, protocol self-tests, full Swift 502/502, Native Release and Universal2 `x86_64 arm64` packaging.
- Independent source audit confirmed the obsolete non-direct SHORT/LONG classifier, `.pending/.holding`, legacy tail/repress/short-local-mic caller plumbing and obsolete tests were retired while current Gate-A LONG-only, direct rapid repress, tombstone/suppression/handoff, transport-loss and output-drain ownership remained intact.
- `AudioPipe.swift` was unchanged in Domain 5.
- PR #36 was converted from Draft to Ready only after audit PASS and merged with exact expected head as `07c6f294e436a987d526a085d7386c7f15b830b1`.
- Post-merge main CI run `41271866992`, job `124746108991`, passed every durable stage including Full Swift 502/502, Native Release and Universal2 packaging.
- No app install, driver/CoreAudio/TCC/default-device mutation, tag/release or machine-owned RC003/Doubao acceptance was performed.

Canonical audit basis for Domain 6: `main@07c6f294e436a987d526a085d7386c7f15b830b1`.

## Legacy retirement execution model

Retirement remains serial by bounded domain:

`Web audit/freeze → local cleanup → Web exact-head audit → merge/closeout → next domain`

Local execution performs freshness/identity reconciliation for the frozen domain. It does not re-audit or redesign the domain unless live repository facts materially conflict with authority; then it stops with `AUTHORITY_RECONCILIATION_REQUIRED`.

## Domain 6 implementation — Local Microphone Capture & Temporary Input Lease

Design authority: `docs/design/2026-11-01-045b-domain-6-local-microphone-capture-retirement.md`.
Pre-mutation gate: fresh `main@c6976aa5e4db799747e7f86ba9c8278cbe051241` matched authority; control-only CI run `41272632076`, job `124748359282`, final `SUCCESS` on `remoteorbit-macmini` including the build-only packaging smoke step.

### Implementation facts

- Implementation HEAD: `84bd468ad9059b0313f07e905f169b1d41cd53e2` (single implementation commit, direct child of `c6976aa`).
- Branch: `codex/task045b-domain6-local-microphone-capture-retirement`; worktree clean and in sync with remote.
- Draft PR #37 (`Retire local microphone capture and add temporary RemoteOrbit input lease (Task 045B Domain 6)`), not merged, not made Ready.
- Exact-head durable PR CI run `41275976852`, job `124758115909`, `SUCCESS` on `remoteorbit-macmini` through source contracts, protocol self-tests, full Swift tests, Native Release and Universal2 build-only packaging smoke. Final PR head and post-push evidence are to be re-resolved from GitHub at independent audit time.
- Local verification before push: focused suites green (AudioPipe/AudioPipeRealtime/AudioDataPlaneMeasurementBoundary/AudioDeviceManager/VoicePipelineSimplification/VoicePressCoordinator/PrimaryVoiceRuntime/VoiceKeyFilter plus BLE/diagnostics/readiness suites), full `swift test` 509/509, `swift build -c release`, `git diff --check` clean, local Universal2 build-only packaging produced `x86_64 arm64` with no `NSMicrophoneUsageDescription` in the packaged Info.plist.

### Retired surface

- `AudioPipe` physical/external AVCapture ownership: capture session/queue, `AVCaptureAudioDataOutputSampleBufferDelegate`, microphone permission request lifecycle, `setLocalMicrophoneCaptureEnabled(...)`, start/stop/configuration helpers, sample-buffer → local PCM scheduling, directly-owned local counters/diagnostics branches, and the AudioPipe-side loopback name filter used only for capture discovery.
- `AVFoundation` / `CoreMedia` imports; restore-at-`setRemoteActive(false)` branch gated on the retired local-capture flag; `scheduledMacBuffers`; the permanently-false realtime local-microphone render state (`.localMicrophone` render state, `localMicrophoneActive`, marker 3) removed as a compile-local, behavior-equivalent deletion.
- `NSMicrophoneUsageDescription` from packaged Info.plist; obsolete microphone-TCC wording in current README/SETUP instructions.

### Retained surface

- Menu-bar `输入设备`/`输出设备` selection, physical input enumeration, persisted preferred input, startup/driver-reload preferred-input restore, temporary `selectRemoteOrbitInputForVoice()`.
- All remote AudioPipe transport: candidate/prebuffer, fixed-capacity ring, playout reserve, IOProc/render, output drain/grace; Gate-A LONG-only, rapid repress, tombstone/suppression, hardware/synthetic trigger, pre-HID, BLE/ATVV, codec/gain/sample rate, receiver readiness, diagnostics gating, debug recording, primary profile/mapping.
- `AudioPipePCMSource.local` and mixed-source ring attribution intentionally frozen for the final Wave D audit; `DiagnosticExport`'s historical-log keyword filter mentioning `avcapture` is read-side evidence triage, not capture ownership, and stays.
- Tests use injected/pure seams; no test mutated host default input, driver, CoreAudio or TCC state (host default input remained `RemoteOrbit Mic 2ch` before and after the run).

### Temporary system-input lease

`VoicePressCoordinator` owns the lease through a new injected `onRemoteInputLeaseRelease` seam wired to `SystemAudioDeviceManager.applyPreferredInputSelection()`:

- promoted remote LONG acquires/retains the lease (route activation still temporarily selects `RemoteOrbit Mic 2ch` without overwriting the saved preference);
- transport stop / `setRemoteActive(false)` does not restore;
- at post-drain direct-session completion the lease transfers to an immediate direct successor (registered rapid repress, pending hardware repress, or a live replacement physical candidate epoch);
- otherwise the persisted preferred input is restored exactly once (repeated drain completions are bounded no-ops; a saved RemoteOrbit preference restores idempotently);
- a lease retained for a successor that dies without promoting is released at that successor's end boundary (candidate cancel/failure, pending-repress release before activation, pre-HID epoch end, coordinator stop).

New deterministic coverage: `RemoteVoiceInputLeaseTests` (5 tests) and `LocalMicrophoneCaptureRetirementContractTests` (3 tests); obsolete `testLocalMicrophoneRenderIsExcludedFromRemoteDiagnostics` removed.

### Workspace disposition

- Domain 5 worktree removed after clean + merged-ancestry confirmation; branch `codex/task045b-domain5-legacy-generic-short-classifier-retirement` and history preserved.
- No Wave D / next-domain mutation, merge, app install, driver/CoreAudio/TCC/default-device mutation, tag/release, or machine-owned hardware acceptance was performed.

## Next gate

Independent Web exact-head audit of PR #37, then merge/closeout. No Wave D or next-domain work is authorized before that audit.
