# CURRENT_STATUS

Last updated: 2026-11-01
State: `RO-DIAGNOSTICS-LEGACY-RETIREMENT-045 — DOMAIN_6_AUDIT_COMPLETE / READY_FOR_IMPLEMENTATION_HANDOFF`
Repository: `Lost0rz/RemoteOrbit`
Human runtime/UI acceptance: `PENDING / USER-OWNED`

## Task 045 progress

- Task 045A: `DIAGNOSTICS_GATING / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 1: `LEGACY_VOICE_PRODUCT_SURFACE / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 2: `LEGACY_VOICE_PERSISTED_PREFERENCE_AUTHORITY / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 3: `PERSISTENT_VOICE_RUNTIME_STATE_MACHINE / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 4: `DUAL_RECEIVER_RUNTIME_STATE_MACHINE / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 5: `LEGACY_GENERIC_SHORT_CLASSIFIER_RUNTIME / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 6: `LOCAL_MICROPHONE_CAPTURE / AUDIT_COMPLETE / READY_FOR_IMPLEMENTATION_HANDOFF`

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

## Domain 6 audit — Local Microphone Capture & Temporary Input Lease

Design authority: `docs/design/2026-11-01-045b-domain-6-local-microphone-capture-retirement.md`.

### Verified current facts

- Domain 5 removed every production caller that enabled AudioPipe local/external microphone capture.
- `AudioPipe.swift` still owns an obsolete AVCapture pipeline: AVFoundation/CoreMedia imports, `AVCaptureSession`, permission/request state, `setLocalMicrophoneCaptureEnabled(...)`, start/stop helpers, sample-buffer delegate conversion and local PCM scheduling.
- Current product behavior is explicitly remote-only for the microphone button: SHORT is no-op; LONG consumes Xiaomi ATVV audio through `RemoteOrbit Mic 2ch`.
- The menu-bar `输入设备` selector remains a current product feature. It lists RemoteOrbit plus physical microphones, sets macOS default input, and persists the user's stable input identifier through `SystemAudioDeviceManager`. This preference is not legacy local-capture ownership and must remain.
- On remote activation, `AudioPipe.setRemoteActive(true)` temporarily selects `RemoteOrbit Mic 2ch` without overwriting the persisted user input preference.
- Current deactivation restores the persisted input only when obsolete `localMicrophoneCaptureRequested` is true. With Domain 5 callers gone, a user-selected physical input can therefore be permanently overridden after the first remote LONG until manually reselected/restarted.
- Remote route deactivation occurs before queued PCM output drain. Restoring a physical input inside `setRemoteActive(false)` would therefore be too early and could cut across the tail/drain lifetime.
- Direct rapid repress can transfer A→B ownership across the previous output drain. The temporary RemoteOrbit input must stay leased across that handoff rather than restoring/reacquiring a physical input between sessions.
- `NSMicrophoneUsageDescription` remains in packaged Info.plist solely because of the obsolete AVCapture path. Control Center has no current microphone-TCC permission surface.
- Low-level ring source attribution still contains `.local`/mixed-source bookkeeping. Removing that realtime data-plane abstraction is not required to retire physical microphone capture and is frozen for the final Wave D cleanup unless a compile-only change is strictly necessary.

### Domain 6 classification

`RETIRE NOW`:

- AudioPipe physical/external AVCapture ownership, permission request lifecycle and sample-buffer delegate path;
- local-capture state/counters and local-only scheduling branches directly owned by that path;
- `NSMicrophoneUsageDescription` and current install/setup instructions that tell users RemoteOrbit requires microphone TCC;
- obsolete local-microphone diagnostic state/tests directly tied to the removed capture path;
- stale comments describing AudioPipe as a local+remote microphone mixer.

`KEEP / RECONCILE`:

- menu-bar system input/output device selection;
- persisted preferred system input authority in `SystemAudioDeviceManager`;
- temporary selection of `RemoteOrbit Mic 2ch` for a promoted remote LONG;
- restore of the persisted input only after the final remote output drain, when no immediately pending direct successor owns the same temporary lease;
- rapid-repress transfer of the temporary RemoteOrbit input lease without physical-input flicker;
- all remote AudioPipe transport/ring/reserve/IOProc, BLE/ATVV, codec, gain/sample-rate, candidate/prebuffer, diagnostics gating and recording behavior;
- Gate-A 300 ms LONG-only and all suppression/tombstone/hardware/synthetic correctness mechanisms.

`FROZEN FOR WAVE D`:

- broader simplification of `AudioPipePCMSource.local`, mixed-source ring attribution and generic remote-queue bookkeeping if those symbols can remain behavior-neutral after capture retirement;
- cosmetic naming/history cleanup;
- final resource/regression audit and hardware acceptance.

## Domain 6 selected ownership model

The persisted system input remains a user preference owned by `SystemAudioDeviceManager`. Remote voice temporarily leases the system default input to `RemoteOrbit Mic 2ch`.

- Lease acquire: current remote LONG route activation.
- Lease release: after actual AudioPipe output drain completes, not when transport merely stops.
- Successor transfer: if a direct pending rapid-repress/candidate will immediately own the next remote session, do not restore the physical preference between A and B; the lease transfers to B.
- Final release: once the final remote session reaches post-drain completion with no direct successor, restore the persisted preferred input. If the saved preference is RemoteOrbit itself, restoration is naturally idempotent.

Do not implement preference restoration inside `AudioPipe.setRemoteActive(false)`.

## Next gate

Domain 6 is fully audited/designed/frozen and ready for one bounded local implementation from fresh live `main` after the control-only CI for this authority commit is green. No Wave D/next-domain mutation, merge, app install, driver/CoreAudio/TCC/default-device runtime mutation, tag/release or machine-owned hardware acceptance is authorized.