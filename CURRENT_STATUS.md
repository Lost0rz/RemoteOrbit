# CURRENT_STATUS

Last updated: 2026-10-28
State: BLOCKED_ATVV_PREPARATION — TASK 038-B VERIFY
Repository: Lost0rz/RemoteOrbit

## Repository authority

- Canonical development repository: `/Volumes/Jack-Dev/Projects/remoteorbit`.
- Canonical branch: `main`.
- Verified origin: `https://github.com/Lost0rz/remoteorbit.git`.
- Fresh local `main` and `origin/main` are aligned at `e80c8be50fa489c7f04c4ca5567aff7cc5d3af9b`, the 038-B activation/control head.
- PR #23 is merged into `main` at merge commit `79f3db92024e8a901d3a0fcec2c1f194c7136753` from audited head `dab6ea1c6d2143a889bd22a91f6eb13d64050209`.
- Task 038-A rapid re-press admission is merged and complete at the source/code boundary. Its final product commit is `68ed029c582c3befb12f4f9996277e96bd2ecf60`.
- Recorded Task 038-A verification: `VoicePressCoordinatorTests` 39/39 PASS; `BLEBridgeTests` 18/18 PASS; full Swift 410/410 PASS; release build PASS; diff check PASS.
- Task 037 remains merged with `HUMAN_UI_ACCEPTANCE: PENDING` for Command-Space, Command-Shift-4, Option-A, pure modifier recording, and normal shortcut restoration after recorder close/cancel.
- `AGENTS.md` durable rules were re-read for this transition and require no semantic change.
- The prior 038-A worktree `/private/tmp/remoteorbit-runtime-reliability-038-a-rapid-repress` was verified clean, fully merged/reachable from current `main`, and without unique/unpushed commits; it was removed and its local branch was deleted. Its remote branch remains retained. Task 037's historical worktree remains untouched.
- PR #24 is OPEN + DRAFT + UNMERGED; its live head is the current tip of the authorized branch and was remote-verified for this transition. Current GitHub metadata reports `mergeable=true`; this is only a repository fact and does not authorize merge. The independent Web CODE_DIFF audit was passed at the audited product head `6b5fde0b767933a89b8b7643dabe473e46040df8`; later commits are paired control-only runtime transition/result records. Corrective-2 delivery commit `ebd6f1daa6a15f4790ec0faa342dc80a1a0c518a` removes the remaining lifecycle observer-effect. Corrective-3 delivery commit `7d33e01cf94aa3685ccfdecc6df28207258cb1bb` closes only the AUDIO_START-before-HID continuity-correlation gap. Corrective-4 source/test delivery commit `652ea306dc4a22ee3c489b254d87becc6f9a4ed0` removes the remaining submission-path probe contention. The card authorizes only the diagnostic runtime build/install/run and evidence capture; merge, audio tuning, production correction, and 038-C/D/E/F work remain prohibited.

## Task 038-B writer identity

- Authorized branch: `codex/runtime-reliability-038-b-continuity-evidence`.
- Authorized worktree: `/private/tmp/remoteorbit-runtime-reliability-038-b-continuity-evidence`.
- Start HEAD: `e80c8be50fa489c7f04c4ca5567aff7cc5d3af9b`.
- Worktree registration: this paired control commit; worktree was clean before any source/test or diagnostic mutation.
- Current source/test HEAD: `652ea306dc4a22ee3c489b254d87becc6f9a4ed0`, pushed and verified equal to the authorized remote branch before this paired closeout control update.
- Corrective-1 audit baseline: PR #24 head `59fa6a5f0a20f48b623d0edefd1863e6c9073460`; render-side continuity capture currently calls the shared `VoiceTimingLogger` lock and mutates its bucket dictionary while `AudioPipe.stateLock` is held.
- Corrective-1 delivery: source/test commit `0c26c61c2a2ec1f147f6179b20a864f335af1dfb`; render-side capture now uses AudioPipe-owned fixed-capacity storage and merges a lifecycle snapshot outside the render path.
- Corrective-2 delivery: source/test commit `ebd6f1daa6a15f4790ec0faa342dc80a1a0c518a`; enabled storage is prepared before the lock, end detaches under the lock, and snapshot/filter runs after unlock.

## Task 038 roadmap

- `038-A MERGED / COMPLETE`: rapid re-press admission.
- `038-B BLOCKED_ATVV_PREPARATION`: the post-grant fresh installed diagnostic launch reached CoreBluetooth readiness (`[BLE] 蓝牙已就绪`), but no passive ATVV transport preparation was observed before any voice-key interaction; no natural session is authorized yet.
- `038-C DEFERRED`: Option-edge authority.
- `038-D DEFERRED`: interaction latency.
- `038-E DEFERRED`: runtime telemetry/log retention.
- `038-F DEFERRED`: privacy-preserving text-output observation.

## 038-B evidence basis

Historical runtime evidence motivating this slice shows repeated BLE delivery deficits and AudioPipe underruns while decoder rejects and overflow drops remained zero. This is not yet end-to-end proof of text omission and must not be promoted to root cause without fresh session-level correlation.

The fresh safe log check used `/Users/ox_miles/Library/Logs/RemoteOrbit/RemoteOrbit.log`, from `2026-10-27 22:54:47 UTC` through `2026-10-28 04:47:40 UTC` (`21174` lines, `3493732` bytes). It contains only `AUDIO-METER` records; voice continuity lines and `diagnostic-events-v1.jsonl` are absent, so `SESSION_COUNT=0` for this evidence slice. The installed/running `/Applications/RemoteOrbit.app` is a separate old identity (`com.lost0rz.RemoteOrbit`, version `0.2.11`, build `40`, executable SHA-256 `4dcd1cc27d7b56bbf5c9b67240eb5fcef4a8c966fbc4a86e029a7877288fe66c`) and is not evidence for source HEAD `5b3003b`.

038-B therefore investigates the continuity chain only:

`BLE notification cadence -> decoded PCM supply -> AudioPipe queue/render underrun`

The goal is to determine whether a reproducible, session-level causal relationship exists and which layer owns the deficit. No product tuning is authorized by this transition.

## Current phase and next action

- Phase: 038-B VERIFY — fresh authorization-resume launch is blocked at CoreBluetooth central `Unauthorized`; no voice session is authorized.
- First local action completed: reconciled fresh `main`, proved and retired the merged 038-A worktree, and fast-forwarded canonical `main` to the activation head.
- Current conclusion: existing telemetry was insufficient for mid-stream temporal alignment; the minimum opt-in 100 ms monotonic/session bucket ledger remains in source/test commit `652ea30`, and buffer sizing, pacing, codec behavior, gesture semantics, Option handling, and text-output behavior remain unchanged.
- Audit property reproduced: the prior render-side probe acquired the shared logger lock and mutated its dictionary while `AudioPipe.stateLock` was held, creating probe self-contention risk.
- Corrective-1 result: render-side continuity capture now uses AudioPipe-owned preallocated fixed-capacity storage (8,192 buckets), with no new logger lock, dictionary/hash mutation, formatting/printing, synchronous dispatch, or unbounded allocation in the probe path; snapshot/filter/merge occur after capture ends.
- Corrective-2 audit basis (before delivery): begin/end reset or filtered the full 8,192-bucket ledger while holding `AudioPipe.stateLock`; the default-off path also performed the full reset.
- Corrective-2 boundary: preserve the fixed-capacity render ledger and evidence fields, but make disabled activation/deactivation cheap, keep lock-held transitions bounded metadata/state work, and detach snapshot creation without racing render writes.
- Corrective-2 result: disabled begin/end keep the ledger nil; enabled begin allocates before `stateLock`, end detaches under `stateLock`, and snapshot/filter runs after unlock with no render race.
- Verification: focused `AudioDataPlaneDiagnosticsTests` 28/28 PASS; affected `AudioPipeTests` 4/4 PASS; full `swift test` 417/417 PASS; `swift build -c release` PASS; `git diff --check` PASS.
- Corrective-3 result: AUDIO_START now owns a stable opt-in capture identity even when no HID session exists; pre-session BLE/decode/render observations remain on that capture, and the matching later session can bind it once. Binding is exact-identity and one-shot; wrong or repeated session bindings are rejected. HID-before-AUDIO_START reuses the same bound capture identity.
- Verification: focused `AudioDataPlaneDiagnosticsTests` 31/31 PASS; affected `AudioPipeTests` 4/4 PASS; `VoiceBoundaryOrderingTests` 3/3 PASS; `VoicePressCoordinatorTests` 39/39 PASS; full `swift test` 420/420 PASS; `swift build -c release` PASS; `git diff --check` PASS.
- Product/runtime boundary: UNKNOWN — the authorized runtime capture has not yet produced evidence; root cause remains UNKNOWN.
- Current next action: stop at `BLOCKED_BLUETOOTH_AUTHORIZATION`; preserve fresh PID `56531` evidence and do not request a voice session, change TCC, modify Bluetooth logic, change the driver, restart CoreAudio, or merge.

## BLE central-readiness diagnosis transition receipt

- Transition authority: FACT — the current 038-B BLE central-readiness card explicitly authorizes this control-only transition and bounded existing-evidence diagnosis.
- Previous incident outcome: FACT — `OUTCOME_A_PRE_MICOPEN_FAILURE`; the session reached the long-activation route boundary but no ATVV-ready, `MIC_OPEN_TX`, `AUDIO_START`, or first remote audio packet evidence was observed.
- Missing fact: FACT — the existing runtime evidence does not yet identify the exact CoreBluetooth central readiness/authorization state that prevented `.poweredOn` transport progress.
- Scope: FACT — preserve the observed runtime; no product correction, reconnect/ATVV behavior change, TCC/driver/CoreAudio mutation, rebuild/reinstall, merge, or second user session is authorized.

## BLE central-readiness diagnosis result receipt

- Evidence interval: FACT — process launch `2026-10-28 15:37:55.792 +0800` through incident release `2026-10-28 15:45:44.685 +0800`; the selected incident is `AD04FCCB-020E-4071-BD90-B24EFB4B2ACE`.
- Runtime identity: FACT — PID `59512`, `/Applications/RemoteOrbit.app/Contents/MacOS/RemoteOrbit`, bundle `com.lost0rz.RemoteOrbit`, version `0.2.14 (43)`, executable SHA-256 `926d5ddf4b8796303ec07fe051b1da36cd539fc045973bb8bb24c0bea9a588fc`, with `REMOTE_ORBIT_CONTINUITY_EVIDENCE=1`.
- Central state: FACT — `bluetoothd` reported `state updated ... state "Unauthorized"` at `15:37:55.906 +0800` for the PID-59512 CoreBluetooth session; no later state update for that session was observed through the incident.
- Central authorization: FACT — the central session was unauthorized; the numeric `CBManager.authorization` property was not separately emitted. Bluetooth power-only status remains UNKNOWN.
- HID transport: FACT — HID compatibility input remained functional (`hid_connected=true`, HID down/hold/up evidence); HID health does not prove CoreBluetooth ATVV readiness.
- ATVV/CoreBluetooth: FACT — no powered-on callback evidence, connection, service discovery, capabilities handshake, ATVV-ready marker, `MIC_OPEN_TX`, `AUDIO_START`, or remote audio packet was observed. The app emitted repeated `等待蓝牙就绪…` and CoreBluetooth recorded powered-on-state API misuse during the same process lifetime.
- Source behavior: FACT — `start()` sets `isStarted` then returns when `central.state != .poweredOn`; `.poweredOn` would schedule immediate reconnect only when `voiceInputRequested` is true, while `.unauthorized` falls through without a recovery action. Release cleanup later clears the voice intent, so no powered-on callback/reconnect path was observed in this incident.
- Earliest proven break: FACT — CoreBluetooth central readiness/authorization before ATVV connection and before `micOpen`; the BLE/decode/PCM/AudioPipe stages were never entered.
- Evidence sufficiency: SUFFICIENT — exact minimum fault boundary is established; no diagnostic probe is required for this diagnosis.
- Root cause: INFERENCE — the incident is blocked at an unauthorized CoreBluetooth central boundary. The underlying authorization/TCC cause and any product correction are not established or authorized here.
- Smallest justified next action: STOP after diagnosis. Preserve the runtime and require a separate authority decision for any user-owned authorization review or product correction; do not request another voice session in this pass.
- Source changed: FACT — NO; no probe, build, install, runtime restart, permission change, driver change, CoreAudio restart, or merge was performed.

## BLE authorization-resume verification receipt

- Transition authority: FACT — the current 038-B VERIFY card explicitly authorizes cleanly replacing the prior diagnostic process, relaunching the same installed diagnostic app, and observing fresh CoreBluetooth readiness without a voice session.
- Installed bundle: FACT — `/Applications/RemoteOrbit.app`, bundle `com.lost0rz.RemoteOrbit`, version/build `0.2.14 (43)`, executable SHA-256 `926d5ddf4b8796303ec07fe051b1da36cd539fc045973bb8bb24c0bea9a588fc`; both `NSBluetoothAlwaysUsageDescription` and `NSBluetoothPeripheralUsageDescription` exist.
- Prior runtime: FACT — PID `59512` was quit through the application-level quit path and its launcher exited before the new launch.
- Fresh runtime: FACT — PID `56531`, `RUN_START=2026-10-28 17:22:48.532 +0800`, same installed executable, only `REMOTE_ORBIT_CONTINUITY_EVIDENCE=1` observed.
- Bluetooth authorization: UNKNOWN — the fresh process did not emit a numeric `CBManager.authorization` value; the human Settings action is not substituted for process evidence.
- Central state: FACT — `bluetoothd` sent the fresh PID-56531 central session `state updated ... state "Unauthorized"` at `17:22:48.758 +0800`; no `.poweredOn` transition or `[BLE] 蓝牙已就绪` marker followed.
- Transport preparation: FACT — blocked before reconnect/scan/retrieve, peripheral connection, service discovery, characteristic discovery, capabilities handshake, and ATVV readiness; no synthetic `micOpen` was sent.
- Final state: FACT — `BLOCKED_BLUETOOTH_AUTHORIZATION`; do not request a natural voice session until a separately authorized fresh runtime reaches `.poweredOn` and ATVV readiness.
- Scope: FACT — no source change, TCC mutation, rebuild, reinstall, driver change, CoreAudio change, PR merge, or ten-session run occurred.

## BLE-start incident transition receipt

- Transition authority: FACT — the current 038-B BLE-start incident card explicitly authorizes this control-only transition and existing-evidence diagnosis.
- Incident session: `AD04FCCB-020E-4071-BD90-B24EFB4B2ACE`.
- Incident interval: `2026-10-28 15:45:41.216 +0800` through `2026-10-28 15:45:44.685 +0800`.
- Last confirmed good stage: `INPUT/GESTURE + REMOTE_ROUTE_BEGIN`.
- First failed or unconfirmed stage: `BLE AUDIO START / FIRST REMOTE AUDIO PACKET`.
- Root cause: UNKNOWN — the existing capture does not yet establish whether `micOpen` was transmitted after ATVV readiness.
- Scope: no second user session, no product source change, no BLE/audio behavior change, no rebuild/reinstall/TCC/driver/CoreAudio mutation, and no merge.

## Runtime-capture transition receipt

- Transition authority: FACT — the current execution card records the independent Web CODE_DIFF audit PASS at observed PR head `6b5fde0` and explicitly authorizes an evidence-only runtime build/run/capture.
- Scope: FACT — `REMOTE_ORBIT_CONTINUITY_EVIDENCE=1` is the only required diagnostic mode; no buffer, queue target, pacing, resampling, codec, BLE timing, AUDIO_STOP, Adaptive Playout, text observer, merge, or release change is authorized.
- Runtime status: FACT — installed diagnostic identity still matches the prior capture; fresh process permission health and first-session evidence are pending.
- Root cause: UNKNOWN — no causal claim is made before fresh session-level evidence.

## Runtime-capture result receipt

- Audited/product identity: FACT — independent Web CODE_DIFF audit passed at PR head `6b5fde0b767933a89b8b7643dabe473e46040df8`; semantic source/test identity remains `652ea306dc4a22ee3c489b254d87becc6f9a4ed0`; current PR/control head is `54cdaf2a407d4d24ec6626725c9846bf2bbba80f`, with only paired control records after the audited product head.
- Runtime build: FACT — diagnostic app `com.lost0rz.RemoteOrbit`, version `0.2.14`, build `43`, universal arm64+x86_64, installed at `/Applications/RemoteOrbit.app`; executable SHA-256 `926d5ddf4b8796303ec07fe051b1da36cd539fc045973bb8bb24c0bea9a588fc`; embedded build-control head `54cdaf2a407d4d24ec6626725c9846bf2bbba80f` and product tree unchanged from semantic source/test head.
- Build note: FACT — `remote-orbit/package-app.sh` failed only in its legacy x86 stage under Swift 6.4/Xcode 27.1; native arm64 and disposable `--triple x86_64-apple-macos13.0` builds passed, and the same signed universal app structure was assembled in `/private/tmp/remoteorbit-038-b-runtime-capture.wWfAWx/diagnostic-build` without changing the repository script or product code.
- Capture environment: FACT — the running product process inherited only `REMOTE_ORBIT_CONTINUITY_EVIDENCE=1`; no unrelated experimental mode, TCC change, driver change, CoreAudio restart, or LaunchAgent change was made. Diagnostic stdout/PTY capture is `/private/tmp/remoteorbit-038-b-runtime-capture.wWfAWx/diagnostic.tty.log`; app logs are `/Users/ox_miles/Library/Logs/RemoteOrbit/RemoteOrbit.log` and `voice-diagnostic-current.jsonl`.
- Capture interval: FACT — diagnostic launches at `2026-10-28 15:25:37 +0800`, `15:26:12 +0800`, and `15:26:33 +0800`; stable capture process observed as PID `46970` at `15:27:18 +0800`. The old `0.2.11 (40)` app and log were preserved under `/private/tmp/remoteorbit-038-b-runtime-capture.wWfAWx/preexisting/`.
- Probe health: FACT — FAIL/INCOMPLETE. The product log reports `input=false accessibility=false`; no `CONTINUITY_SESSION` or `CONTINUITY_BUCKET` record was emitted.
- Session/join integrity: UNKNOWN — `TOTAL_VOICE_SESSIONS=0`, `USABLE_SESSION_COUNT=0`, `EXCLUDED_SESSION_COUNT=0`; no session ID existed to join BLE/decode/AudioPipe evidence. No per-session metrics are available.
- Render capacity drop: UNKNOWN — `render_capacity_dropped` was not observable because no continuity session ended.
- Runtime boundary: FACT — installed system driver remains `audio.local.RemoteOrbitAudio2chXX`, version `0.7.1`; no RemoteOrbit LaunchAgent was found; the driver was not replaced and CoreAudio was not restarted.
- Evidence conclusion: UNKNOWN — decoder rejection, overflow causality, BLE cadence causality, PCM-supply-to-underrun causality, active-stream underrun, and final-text omission are all unclassified because probe health and session evidence did not pass.
- Smallest justified next action: user manually grants Input Monitoring and Accessibility to the installed diagnostic App, then performs natural voice sessions; after at least one healthy probe session, resume toward the card's preferred ten usable sessions. No agent TCC mutation or synthetic failure is authorized.

## Corrective-4 delivery receipt

- Audit finding: FACT — `AudioPipe.schedule()` held `stateLock` while `VoiceTimingLogger.recordContinuitySubmitted()` acquired the shared diagnostic lock and mutated the central dictionary ledger.
- Selected architecture: FACT — submission evidence now records into the existing AudioPipe-owned fixed-capacity ledger under `stateLock`; the monotonic timestamp, submitted frames, queue depth, 100 ms bucket, capture identity, and provisional late-binding origin are preserved.
- Merge boundary: FACT — submission and render fields are carried in the detached snapshot and merged into the central ledger once after capture detach; the old shared submission method and call are absent.
- Preservation: FACT — corrective-1/2/3 render, lifecycle, default-off, capture identity, late binding, session isolation, ordering, overflow, and `render_capacity_dropped` invariants remain covered. No production audio redesign, voice semantic change, or runtime capture occurred.
- Verification: FACT — diagnostics 32/32, AudioPipe 4/4, VoiceBoundaryOrdering 3/3, VoicePressCoordinator 39/39, full Swift 421/421, release build PASS, and diff check PASS.

## Protected boundaries

- Do not tune AudioPipe buffers or queue targets.
- Do not introduce or re-enable Adaptive Playout.
- Do not change BLE codec, packet timing, keep-alive, AUDIO_STOP interpretation, or stream semantics.
- Do not change SHORT/LONG, rapid re-press, Option/noOptionEdge, shortcut mapping, or persistent-session behavior.
- Do not add the final text-output Accessibility observer in 038-B.
- Do not redesign DiagnosticAuthority or logging retention in this slice.
- Do not bundle unrelated cleanup, packaging, release, permission, or driver work.

## Acceptance boundary

038-B is complete only when session-level evidence can classify the continuity path with explicit FACT / INFERENCE / UNKNOWN labels and distinguish at minimum:

- BLE notification gaps/cadence;
- decoded frame/sample supply and delivery deficit;
- AudioPipe queue depth and underrun behavior;
- normal versus weak sessions;
- boundary/tail artifacts versus active-stream continuity defects.

A finding may identify a likely layer, but no buffer or playback fix is authorized until a later governance transition explicitly opens corrective implementation.

## 038-B Bluetooth app-identity reconciliation result

- Transition authority: FACT — the current `RO-038-B-BLUETOOTH-APP-IDENTITY-RECONCILIATION` card explicitly authorizes this read-only identity inventory and requires the stale/unresolved stop state when no `Remote Orbital` application can be found while the current diagnostic runtime remains CoreBluetooth Unauthorized.
- Evidence interval: FACT — read-only inventory completed on `2026-10-28 17:36:54 +0800`; the existing diagnostic process launched at `2026-10-28 17:22:48` and remained PID `56531`.
- Current diagnostic identity: FACT — `/Applications/RemoteOrbit.app`, display/name `RemoteOrbit`, bundle `com.lost0rz.RemoteOrbit`, version/build `0.2.14 (43)`, executable SHA-256 `926d5ddf4b8796303ec07fe051b1da36cd539fc045973bb8bb24c0bea9a588fc`, designated requirement `identifier "com.lost0rz.RemoteOrbit"`, CDHash `7465273e606e288198cff206625bb46b46f8c819`, embedded `RemoteOrbitDiagnosticSourceHead=54cdaf2a407d4d24ec6626725c9846bf2bbba80f`.
- Running-process identity: FACT — PID `56531` resolves through `lsof` to `/Applications/RemoteOrbit.app/Contents/MacOS/RemoteOrbit`; the executable hash, bundle ID, version/build, and designated requirement match the installed app.
- Candidate inventory: FACT — 16 plausible on-disk `.app` bundles were found across the authorized application, project/archive, and disposable runtime/build roots. Fifteen use `com.lost0rz.RemoteOrbit`; one observer uses `com.lost0rz.RemoteOrbit.P1A5Observer`. All display as `RemoteOrbit` or `RemoteOrbit P1A5 Observer`; no on-disk `Remote Orbital.app` or `Remote Orbit.app` was found.
- LaunchServices: FACT — 21 exact `com.lost0rz.RemoteOrbit` registration records were observed: the current `/Applications/RemoteOrbit.app` plus stale/nonexistent archive, Trash, backup, volume, and historical build paths. The stale records retain `RemoteOrbit` display names, not `Remote Orbital`.
- Bluetooth UI mapping: FACT/UNKNOWN — `Remote Orbital` is the human-reported Bluetooth UI label; no independent path or bundle identity for that label was available. It cannot be conclusively mapped to the current app or to a different installed app.
- Match: FACT — `STALE_OR_UNRESOLVED_ENTRY`; display name differs, no actual `Remote Orbital` bundle exists in the searched scopes, and the visible label alone does not prove TCC ownership.
- Root-cause boundary: INFERENCE — the current diagnostic app's CoreBluetooth Unauthorized result is not identity-proven as belonging to the visible `Remote Orbital` entry. The underlying TCC/system reason remains UNKNOWN.
- Final state: FACT — `BLUETOOTH_TCC_IDENTITY_STALE_OR_UNRESOLVED`.
- Scope: FACT — no source, app bundle, TCC database, LaunchServices registry, driver, CoreAudio, runtime configuration, voice session, or PR lifecycle was changed.
- Smallest justified next action: STOP. Do not reset TCC or ask for another voice session in this pass; a separately authorized identity-preserving Bluetooth authorization review is required.

## 038-B Bluetooth authorization post-grant verification result

- Transition authority: FACT — the current `RO-038-B-BLUETOOTH-AUTH-POST-GRANT-VERIFY` card explicitly authorizes a clean diagnostic relaunch of the exact installed app and passive CoreBluetooth/ATVV preparation observation without a voice session.
- Evidence interval: FACT — fresh LaunchServices launch `2026-10-28 17:44:08.779 +0800` through final observation; PID `21428` remained running at final inspection.
- Runtime identity: FACT — `/Applications/RemoteOrbit.app/Contents/MacOS/RemoteOrbit`, bundle `com.lost0rz.RemoteOrbit`, version/build `0.2.14 (43)`, executable SHA-256 `926d5ddf4b8796303ec07fe051b1da36cd539fc045973bb8bb24c0bea9a588fc`, designated requirement `identifier "com.lost0rz.RemoteOrbit"`, with only `REMOTE_ORBIT_CONTINUITY_EVIDENCE=1` confirmed in the process environment.
- Bluetooth authorization: UNKNOWN — the fresh runtime did not emit the numeric `CBManager.authorization` value; no `allowedAlways` claim is made from the UI grant alone.
- CoreBluetooth state: FACT — the first fresh app readiness marker was `[BLE] 蓝牙已就绪` at `17:44:08`, proving the central reached `poweredOn`; no later contrary state was observed.
- Startup health: FACT — HID permissions were `input=true accessibility=true`; the HID device was connected in compatibility/monitored mode and the RemoteOrbit audio IOProc started. HID connection is not substituted for ATVV peripheral connection.
- ATVV preparation: FACT — no fresh-interval `[BLE] 已连接`, reconnect/retrieve/scan marker, ATVV service discovery, command/audio/control characteristic discovery, capabilities request/response, codec acceptance, or `ATVV 语音链路已就绪` marker was observed. No `VOICE_DOWN`, `MIC_OPEN_TX`, `AUDIO_START`, or synthetic micOpen occurred.
- Earliest boundary: FACT — `LAST_CONFIRMED_GOOD_STAGE=COREBLUETOOTH CENTRAL READY / POWERED_ON`.
- Earliest unconfirmed boundary: FACT — `FIRST_FAILED_OR_UNCONFIRMED_STAGE=ATVV TRANSPORT PREPARATION (RECONNECT/PREWARM PATH NOT OBSERVED)`.
- Interpretation: INFERENCE — the app does not passively enter the ATVV preparation path while no voice intent exists, or that path did not execute; this is not yet proof of a transport protocol failure.
- Final state: FACT — `BLOCKED_ATVV_PREPARATION`.
- Scope: FACT — no source, TCC, app bundle, rebuild/reinstall, driver, CoreAudio, or voice session was changed or performed.
