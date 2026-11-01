# RemoteOrbit Current Task

## RO-DIAGNOSTICS-LEGACY-RETIREMENT-045 — Wave B / Domain 6 Local Microphone Capture Retirement

Status: `READY_FOR_IMPLEMENTATION_HANDOFF`
TASK_CLASS: `BOUNDED LEGACY RETIREMENT`
Repository: `Lost0rz/RemoteOrbit`
Design authority: `docs/design/2026-11-01-045b-domain-6-local-microphone-capture-retirement.md`
Human runtime/UI acceptance: `PENDING / USER-OWNED`

## Completed prerequisite

Domain 5 is accepted and closed:

- PR #36 independent exact-head audit: PASS (`FRESH_CONTEXT`);
- final reviewed PR head: `cbc5f981f6f72e5041739774b38f94cf1f695fea`;
- exact-head durable PR CI `41271384083` / job `124744691635` passed on `remoteorbit-macmini`;
- merged as `07c6f294e436a987d526a085d7386c7f15b830b1` with exact expected head;
- post-merge main CI `41271866992` / job `124746108991` passed Full Swift 502/502, Native Release and Universal2 `x86_64 arm64` packaging.

## Domain execution rule

Legacy retirement remains serial:

`Web audit/freeze → local cleanup → Web exact-head audit → merge/closeout → next domain`

Domain 6 has already been audited and designed by Web. Local execution performs freshness/identity reconciliation, implementation and verification only. Do not redo the domain audit or choose a different retirement boundary. If live facts materially conflict with this authority, stop with `AUTHORITY_RECONCILIATION_REQUIRED`.

Before any product mutation, fetch live `main`, read `AGENTS.md`, `CURRENT_STATUS.md`, this file and the Domain 6 design authority, and require the durable CI attached to the live Domain 6 authority/control commit to be successful.

## Domain 6 purpose

Retire RemoteOrbit's obsolete local/external microphone AVCapture pipeline and microphone-TCC requirement while preserving the current user-facing system input selector and the remote-only LONG voice path.

The user-selected system input is a persistent preference, not a local-capture source. A remote LONG temporarily leases the system default input to `RemoteOrbit Mic 2ch`; the saved preference is restored only after the final remote PCM output drain, with the lease transferred across an immediate direct rapid-repress successor.

## Authorized mutation

### `remote-orbit/Sources/RemoteOrbit/AudioPipe.swift`

Retire the local/external microphone capture implementation where directly owned by the obsolete path, including as applicable:

- `AVFoundation` / `CoreMedia` imports no longer required after capture removal;
- `AVCaptureAudioDataOutputSampleBufferDelegate` conformance;
- `AVCaptureSession`, local capture queue and local permission/request state;
- `setLocalMicrophoneCaptureEnabled(...)`;
- microphone permission request logic;
- local microphone start/stop/session configuration helpers;
- sample-buffer delegate `captureOutput(...)` and conversion of physical microphone buffers into the output ring;
- `scheduledMacBuffers` and local-only diagnostics/state directly owned by this capture path;
- obsolete calls to stop/restart local capture during remote route changes.

Preserve the remote producer, prebuffer/candidate, fixed-capacity ring, playout reserve, IOProc/render path, output drain, realtime diagnostics and remote timing behavior.

Do not use Domain 6 as permission for a broad rewrite of the realtime ring.

### Temporary system-input lease

Preserve:

- `SystemAudioDeviceManager.inputDevices()` current physical + RemoteOrbit menu behavior;
- `selectInput(identifier:)` and persisted preferred input identifier;
- `applyPreferredInputSelection()` startup/driver-reload restoration;
- `selectRemoteOrbitInputForVoice()` temporary remote selection without overwriting preference.

Reconcile route lifecycle so:

1. promoted remote LONG still selects `RemoteOrbit Mic 2ch`;
2. transport stop / `setRemoteActive(false)` does NOT restore a physical input before queued remote PCM drains;
3. after actual output drain and current direct session completion, the saved preferred input is restored when there is no immediately pending direct successor;
4. a rapid A→B direct repress transfers the temporary RemoteOrbit input lease and does not restore/reacquire a physical input between sessions;
5. after the final session drains, the preference is restored exactly once/boundedly;
6. a saved RemoteOrbit preference remains RemoteOrbit and is idempotent.

Use the smallest deterministic/testable ownership seam. Do not place physical-input restoration inside `AudioPipe.setRemoteActive(false)`.

### `remote-orbit/Sources/RemoteOrbit/AudioPipeRealtime.swift` and audio diagnostics

Remove only local-microphone runtime state or branches that become directly dead and whose removal is local/compile-bounded.

Do NOT broadly redesign `FixedCapacityPCMFrameRing`, remote queue attribution or realtime synchronization. `AudioPipePCMSource.local` / mixed-source attribution may remain intentionally until Wave D if removing it would broaden the data-plane change. If a compile-only deletion is required, keep remote semantics byte-for-byte equivalent in observable behavior and explain the necessity in the receipt.

### Packaging / docs

Remove the obsolete `NSMicrophoneUsageDescription` from `remote-orbit/Packaging/Info.plist` once no production code requests/captures the macOS microphone.

Update current operational documentation only where directly affected:

- RemoteOrbit does not require macOS microphone TCC for the remote BLE microphone path;
- SHORT does not open local/external microphone capture;
- the menu-bar input-device selector remains supported and persisted;
- remote LONG temporarily selects `RemoteOrbit Mic 2ch`, then restores the saved input only after final output drain unless an immediate direct successor owns the lease.

Do not rewrite historical incident/design records solely to erase old terminology.

### Tests

Update/delete local-capture-only tests and assertions after proving they are obsolete. Add deterministic coverage for the temporary input lease and restore ordering without mutating the machine's actual CoreAudio/default-device state during tests.

Prefer injected/pure lifecycle seams for system input selection/restoration assertions.

## Explicit KEEP boundary

Do not delete, redesign or weaken:

- menu-bar `输入设备` / `输出设备` functionality;
- persisted preferred system input/output settings and device filtering;
- `RemoteOrbit Mic 2ch` temporary voice selection;
- Gate-A LONG-only candidate and `holdActivationThreshold == 0.30`;
- SHORT `<300 ms` absolute no-op and LONG `>=300 ms` direct voice contract;
- `.opening / .streaming / .draining` direct lifecycle;
- direct rapid LONG/release/LONG ownership and pending repress;
- short-discard tombstone, mapped-edge suppression and suppression handoff;
- hardware Option ownership/held-UP acknowledgement and synthetic fallback;
- pre-HID candidate;
- BLE READY/reuse, ATVV, codec, gain, sample rate;
- AudioPipe remote candidate/prebuffer/ring/playout reserve/IOProc/render/output drain/post-release grace;
- receiver readiness;
- Task 045A diagnostics gating and independent debug recording;
- primary profile/mapping authority.

`NSMicrophoneUsageDescription` is not needed for BLE remote PCM or CoreAudio output alone; remove it only together with proof that no local AVCapture microphone request remains.

## Explicit non-goals

Do not:

- start Wave D / another retirement domain;
- remove the system input selector or physical input preference;
- restore preferred input at transport stop before output drain;
- introduce input-device flicker between rapid direct A→B sessions;
- broadly simplify/rewrite the fixed-capacity realtime ring/source-attribution architecture;
- change 300 ms semantics;
- alter BLE/ATVV protocol, codec, sample rate, gain or remote prebuffer;
- alter primary HID mapping/profile semantics;
- install/replace the app;
- mutate live driver/CoreAudio/TCC/default audio devices as part of implementation or CI;
- tag/release;
- merge the Domain 6 PR locally.

## Verification required

Focused evidence must prove at minimum:

1. production source has no AVCapture physical/external microphone capture/session/delegate path;
2. no production code requests macOS microphone permission;
3. no production caller/API remains for `setLocalMicrophoneCaptureEnabled(...)`;
4. packaged Info.plist no longer declares obsolete microphone usage permission;
5. menu-bar input selector still exposes supported physical inputs plus RemoteOrbit and persists selection;
6. a remote LONG still temporarily selects `RemoteOrbit Mic 2ch` without overwriting preferred-input persistence;
7. preferred physical input is NOT restored at transport stop / before actual output drain;
8. after final output drain, a saved physical input is restored;
9. direct rapid repress A→B retains/transfers the RemoteOrbit input lease without intermediate restore;
10. after B/final session drains, restore occurs once/boundedly;
11. saved RemoteOrbit preference remains RemoteOrbit;
12. remote AudioPipe candidate/prebuffer/ring/reserve/render/output-drain behavior remains green;
13. current LONG-only/tombstone/suppression/hardware/synthetic/transport-loss regressions remain green;
14. diagnostics gating, debug recording, receiver readiness, primary runtime/profile/mapping and BLE regressions remain green;
15. tests do not mutate the host's live default input, driver, CoreAudio or TCC state;
16. current README/SETUP operational permission and input-lease wording matches implementation.

At minimum run focused suites covering:

- `AudioPipeTests`
- `AudioPipeRealtimeTests`
- `AudioDataPlaneMeasurementBoundaryTests`
- `AudioDeviceManagerTests`
- `VoicePipelineSimplificationTests`
- `VoicePressCoordinatorTests`
- `PrimaryVoiceRuntimeTests`
- `VoiceKeyFilterTests`
- relevant BLE / diagnostics / readiness tests

Then run:

- full `swift test`;
- `swift build -c release`;
- `git diff --check`;
- durable `.github/workflows/remoteorbit-ci.yml` on `remoteorbit-macmini`;
- Universal2 build-only packaging smoke.

## Workspace / delivery

Start from fresh live `main` after reconciliation. Use one fresh worktree/branch, suggested:

`codex/task045b-domain6-local-microphone-capture-retirement`

The merged Domain 5 worktree may be retired only after confirming clean state and merged ancestry. Preserve branch/history unless separately authorized.

Create one Draft PR. Do not merge locally.

After implementation/test/CI evidence is available, atomically update `CURRENT_STATUS.md` and `CURRENT_TASK.md` in one final handoff commit. Do not encode that control commit's own future SHA; resolve final PR head and post-push CI from GitHub at independent audit time.

## Stop

After implementation, verification, push, Draft PR, durable CI and atomic control handoff, stop at:

`WAITING_FOR_INDEPENDENT_WEB_AUDIT`

Do not start Wave D, install the app, mutate live driver/CoreAudio/TCC/default devices, tag/release or merge locally.

Return actual governance route/capability, topology/subagents, fresh start main, branch/worktree, implementation/final heads, remote equality, Draft PR, changed/deleted paths, retired AVCapture surface, retained input-selector/persistence surface, lease implementation/ordering evidence, local attribution residue disposition, permission/Info.plist result, focused/full/build/diff/CI/package results, predecessor-worktree disposition, scope-mutation flags, unresolved uncertainty, `HUMAN_UI_ACCEPTANCE`, merge state and final actual state.