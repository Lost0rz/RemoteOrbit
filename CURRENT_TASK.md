# RemoteOrbit Current Task

## RO-RUNTIME-RELIABILITY-038 — Task 038

- Status: READY_FOR_ONE_NATURAL_SESSION — 038-B EXECUTE.
- Task class: RUNTIME RELIABILITY / DIAGNOSTIC EVIDENCE.
- Repository: `Lost0rz/RemoteOrbit`.
- Canonical repository: `/Volumes/Jack-Dev/Projects/remoteorbit`.
- Control baseline: `main` after PR #23 merge commit `79f3db92024e8a901d3a0fcec2c1f194c7136753` and the paired 038-B activation transition.
- 038-A is merged and closed to further product mutation unless a new regression specifically reopens it.
- Task 037 human acceptance debt remains pending and is not rewritten by Task 038.

## Roadmap state

- `038-A MERGED / COMPLETE`: rapid re-press admission.
- `038-B READY_FOR_ONE_NATURAL_SESSION`: the post-grant fresh installed diagnostic launch reached CoreBluetooth readiness (`[BLE] 蓝牙已就绪`). The prior passive-ATVV readiness expectation was an invalid test assumption; ATVV preparation is demand-triggered by voice-key pending/prewarm.
- `038-C DEFERRED`: Option-edge authority.
- `038-D DEFERRED`: interaction latency.
- `038-E DEFERRED`: runtime telemetry/log retention.
- `038-F DEFERRED`: privacy-preserving text-output observation.

## Objective

Determine, with session-level evidence, whether the observed voice continuity weakness is caused by BLE notification cadence, decoded PCM supply, AudioPipe queue/render behavior, or an interaction between those layers.

The evidence chain under study is:

`BLE notifications -> decode -> PCM submission -> AudioPipe queue -> render/underrun`

Historical logs indicate decoder rejects and overflow drops were zero while delivery deficit and underrun recurred. Treat that as task input, not a predeclared root-cause verdict.

## Authorized lifecycle closeout before 038-B writing

The previous 038-A implementation worktree may be retired locally before creating the 038-B writer. This is explicitly authorized only when the local executor proves:

- the worktree/branch identity is the merged 038-A lineage;
- the worktree is clean;
- all commits are reachable from current `main` or otherwise intentionally retained;
- there is no unique or unpushed work.

If those checks pass, remove the old local 038-A worktree and prune its registration. A local 038-A branch may also be removed if fully merged and non-unique. Remote branch deletion is not required by this transition. If the path is already absent, classify that as reconciliation rather than claiming a deletion.

## 038-B authorized writer identity

- Branch: `codex/runtime-reliability-038-b-continuity-evidence`.
- Worktree: `/private/tmp/remoteorbit-runtime-reliability-038-b-continuity-evidence`.
- Start HEAD: `e80c8be50fa489c7f04c4ca5567aff7cc5d3af9b`.
- Registration: this paired control commit; the worktree was clean before source/test or diagnostic mutation.
- The old 038-A worktree closeout was performed after proving clean state, merged reachability, and no unique/unpushed commits; its local branch was deleted and remote branch retained.
- Current source/test HEAD: `652ea306dc4a22ee3c489b254d87becc6f9a4ed0`, pushed and verified equal to the remote 038-B branch before this paired closeout control update.
- PR #24: OPEN + DRAFT + UNMERGED; its live head is the current tip of the authorized branch and was remote-verified for this transition. Current GitHub metadata reports `mergeable=true`; this is only a repository fact and merge remains prohibited. The independent Web CODE_DIFF audit passed at the audited product head `6b5fde0b767933a89b8b7643dabe473e46040df8`; later commits are paired control-only runtime transition/result records. Corrective-1 reproduced and removed render-path probe self-contention; corrective-2 bounded lifecycle work; corrective-3 closed the AUDIO_START-before-HID correlation gap; corrective-4 removed submission-path probe contention.
- Corrective-2 delivery source/test HEAD: `ebd6f1daa6a15f4790ec0faa342dc80a1a0c518a`; corrective-3 delivery source/test HEAD: `7d33e01cf94aa3685ccfdecc6df28207258cb1bb`, both verified as ancestors of the current branch.

## Authorized 038-B scope

1. Reconcile fresh `main`, open PRs/worktrees, and existing diagnostic authorities before mutation.
2. Perform the authorized 038-A local workspace closeout above before creating the new writer.
3. Create one 038-B branch/worktree from the activation control head and register it before any source/test change.
4. Inventory existing continuity telemetry and tests before adding probes.
5. Build a per-session correlation model using existing fields where possible, including:
   - notification count and gap distribution (`max`, `p95`, `>20/30/50/100ms`);
   - decoded frame/sample counts;
   - expected samples, deficit samples/ms, delivery ratio;
   - stream lifecycle and AUDIO_STOP/drain timing;
   - AudioPipe render requested/filled/unfilled frames;
   - underrun callbacks/duration/max underrun;
   - queue depth min/current/max;
   - overflow/drop counters;
   - active-stream versus tail/boundary classification.
6. Compare representative normal, weak, short, and long sessions rather than relying on one aggregate statistic.
7. Determine whether current telemetry can directly align a BLE supply gap with the corresponding PCM/AudioPipe starvation interval.
8. If the evidence chain is incomplete, add only the smallest observation instrumentation required to correlate those layers by session/time. This was completed as an opt-in 100 ms bucket ledger using the existing P1A4 monotonic clock and VoiceTimingLogger session identity; it must remain diagnostic-only and must not change production behavior.
9. Add focused tests for any new accounting/probe logic.
10. Run proportional verification: focused tests, full Swift tests when source changes, release build for source changes, and diff check.
11. Return to `WAITING_FOR_INDEPENDENT_WEB_AUDIT` if source/test instrumentation changes are delivered. This slice delivered source/test instrumentation in `0c26c61` and corrective-2 in `ebd6f1d`; PR #24 is now at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`. If no later authority transition exists, do not install/release/runtime-capture.
12. Corrective-1 completed: the audit property was reproduced, and the smallest architecture change was made so continuity capture inside CoreAudio IOProc uses no shared logger lock, cross-thread blocking synchronization, dictionary/hash mutation, string formatting/printing, synchronous dispatch, or unbounded allocation. The existing clock, session identity, 100 ms buckets, fields, active/tail/idle accounting, and default-off behavior were preserved.
13. Corrective-2 completed in `ebd6f1d`: the fixed-capacity render-side evidence model is preserved while disabled begin/end are cheap, lock-held begin/end are bounded, and snapshot creation is safely detached from render writes. The clock, session identity, 100 ms buckets, BLE/decode/submission correlation, active/tail/idle accounting, overflow evidence, `render_capacity_dropped`, and default-off behavior are preserved.
14. Corrective-3 authorized in the current execution card: add a deterministic RED regression for AUDIO_START before HID/session creation, then close only the late session-correlation gap. Preserve pre-session observations, reject stale/wrong-session binding, preserve session isolation, and keep corrective-1/2 render and lifecycle invariants unchanged. Stop if this requires a material AudioPipe redesign or changes product voice semantics.
15. Corrective-3 delivered in `7d33e01`: AUDIO_START owns a stable capture identity when the gesture UUID is absent; pre-session observations are retained and bound once to the later HID session. The HID-before-AUDIO_START path remains bound to the same capture identity, while wrong/repeated capture bindings are rejected. No voice semantics, rapid re-press behavior, audio scheduling, queue targets, BLE timing, or AUDIO_STOP interpretation changed.
16. Corrective-4 is authorized in the current execution card: reproduce the remaining `AudioPipe.stateLock -> VoiceTimingLogger.recordContinuitySubmitted -> shared diagnostic lock/dictionary` edge, then move only submission observation into the existing AudioPipe-owned fixed-capacity ledger. Preserve monotonic timestamp, submitted frames, queue depth, 100 ms bucket alignment, capture identity, provisional AUDIO_START-before-HID support, and exact one-time submission-plus-render merge after detach. Preserve corrective-1/2/3 invariants and stop for any production audio redesign, unsafe association, or authority drift.
17. Corrective-4 verification must cover submission bucket/queue evidence, provisional and bound ordering, wrong/stale isolation, same-session submission-plus-render merge, disabled mode, consecutive sessions, focused diagnostics, affected AudioPipe/order/lifecycle tests, full Swift tests, release build, and diff check. After delivery, return to `WAITING_FOR_INDEPENDENT_WEB_AUDIT`; do not install, release, merge, or capture runtime.
18. Corrective-4 delivered in `652ea30`: `AudioPipe.schedule()` records submission evidence in the AudioPipe-owned fixed-capacity ledger, central merge includes submitted frames and queue depth, and `VoiceTimingLogger.recordContinuitySubmitted()` plus its shared-lock/dictionary path were removed. No voice semantics, audio scheduling, queue targets, BLE timing, or AUDIO_STOP interpretation changed.

19. The resume card authorizes only fresh-process permission verification and first-session probe, then natural session capture if probe health passes. The installed identity must remain `com.lost0rz.RemoteOrbit 0.2.14 (43)` with executable SHA-256 `926d5ddf4b8796303ec07fe051b1da36cd539fc045973bb8bb24c0bea9a588fc`; launch only with `REMOTE_ORBIT_CONTINUITY_EVIDENCE=1`. Do not change TCC, merge, release, tune audio, restart CoreAudio, change the driver, add text observation, or begin 038-C/D/E/F.

## Required output / evidence

The 038-B result must include:

- exact source/runtime/log identities used;
- number and duration of sessions analyzed;
- per-session continuity metrics;
- normal-versus-weak comparison;
- whether decoder rejection is supported or downgraded as a cause;
- whether AudioPipe overflow is supported or downgraded as a cause;
- whether BLE cadence deficit temporally precedes or coincides with AudioPipe underrun;
- whether underrun occurs predominantly during active speech supply or only at startup/tail boundaries;
- FACT / INFERENCE / UNKNOWN classification for each causal step;
- the smallest next action justified by evidence.

## Non-goals / prohibited mutation

- No AudioPipe buffer-size, target-depth, scheduling, pacing, resampling, or playback tuning.
- No Adaptive Playout production changes.
- No BLE codec, notification, packet timing, keep-alive, micOpen/micClose, or AUDIO_STOP semantic changes.
- No SHORT/LONG or rapid re-press behavior changes.
- No Option/noOptionEdge fix.
- No text-output Accessibility observer.
- No DiagnosticAuthority redesign or log-retention cleanup.
- No mapping/config backup cleanup.
- No package/install/release/driver/TCC mutation except the explicitly authorized diagnostic app build/install/run already performed in the current runtime-capture card; driver, TCC, LaunchAgent, CoreAudio, and release mutations remain prohibited.
- No opportunistic refactor.

## Stop conditions

- Stop for material authority drift, unexpected active writer/PR, unique unpushed work, or scope conflict.
- If existing telemetry cannot establish time correlation and instrumentation would materially affect the audio path, stop instead of adding an intrusive probe.
- If evidence points to a different layer outside 038-B, report it and stop; do not silently expand into 038-C/D/E/F.
- If a corrective production change becomes justified, stop after the evidence verdict and request a new governance transition before implementing it.
- Corrective-1 stop condition: if safe render observation requires a material AudioPipe redesign or cannot be made non-perturbing within this boundary, revert only the intrusive render-side portion and stop.

## Corrective-1 delivery receipt

- Audit finding: FACT — the previous render-side continuity probe called the shared logger while `AudioPipe.stateLock` was held; that logger acquired a global `NSLock` and mutated a dictionary.
- Architecture: FACT — `AudioContinuityRenderLedger` is AudioPipe-owned, fixed-capacity, preallocated storage; render-side observation only samples the existing monotonic clock, computes a bounded bucket index, and updates fixed counters. Lifecycle snapshot creation and central dictionary merge are outside render.
- Lifecycle/default-off coverage: FACT — focused tests cover active render, tail/overflow, stale timestamp/session reset, consecutive sessions, bounded capacity, disabled context, and snapshot merge.
- Product/runtime boundary: UNKNOWN — no installed/runtime capture was performed, so this commit does not establish runtime underrun behavior or a product audio root cause.

## Corrective-2 scope receipt

- Remaining audit basis: FACT — `beginRemoteAudioDiagnostics()` resets all 8,192 buckets under `stateLock` even when continuity is disabled; `endRemoteAudioDiagnostics()` snapshots/filters and resets the full ledger under the same lock.
- Required result: FACT — delivered in `ebd6f1d`; disabled begin/end avoid capacity-proportional work, enabled begin/end keep lock-held work bounded, and snapshot detachment cannot race render writes.
- Stop boundary: if safe detachment requires a material AudioPipe redesign or new synchronization risk, revert only the intrusive corrective-2 portion and stop.

## Corrective-2 delivery receipt

- Lifecycle ordering: FACT — enabled ledger construction occurs before `stateLock`; end detaches the live ledger and disables capture under `stateLock`, then snapshots the detached ledger after unlock.
- Default-off invariant: FACT — `AudioPipe` keeps no continuity ledger when the context is nil; begin/end perform no fixed-capacity reset or snapshot scan.
- Snapshot race safety: FACT — render writes require the attached ledger and existing `stateLock`; once detached under that lock, render can only observe nil/disabled state, so the detached ledger is stable for snapshot creation.
- Verification: FACT — focused diagnostics 28/28, AudioPipe 4/4, full Swift 417/417, release build PASS, diff check PASS.
- Product/runtime boundary: UNKNOWN — no installed/runtime capture was performed, so this does not establish runtime underrun behavior or an audio root cause.

## Current next action

The launch-to-incident evidence and `centralManagerDidUpdateState` source path establish the exact minimum fault boundary for `AD04FCCB-020E-4071-BD90-B24EFB4B2ACE`. The fresh authorization-resume launch remains `Unauthorized`; stop without creating another runtime incident, requesting another user voice session, mutating product behavior, or changing TCC, driver, CoreAudio, or PR lifecycle.

## 038-B BLE central-readiness diagnosis transition

- Transition authority: FACT — the current 038-B card explicitly authorizes this control-only transition and existing-evidence diagnosis.
- Previous incident outcome: FACT — `OUTCOME_A_PRE_MICOPEN_FAILURE`; no ATVV-ready, `MIC_OPEN_TX`, `AUDIO_START`, or first remote audio packet evidence was observed for `AD04FCCB-020E-4071-BD90-B24EFB4B2ACE`.
- Missing fact: FACT — the exact CoreBluetooth central readiness/authorization state at app start, prewarm, and long activation is not yet established.
- Scope: FACT — no product correction, reconnect/ATVV behavior change, TCC/driver/CoreAudio mutation, rebuild/reinstall, merge, or second user session is authorized. If existing evidence is insufficient, only the card's smallest diagnostic-only probe may be considered.

## 038-B BLE central-readiness diagnosis result

- `RUNTIME_PROCESS_IDENTITY`: FACT — PID `59512`, `/Applications/RemoteOrbit.app/Contents/MacOS/RemoteOrbit`, `com.lost0rz.RemoteOrbit 0.2.14 (43)`, executable SHA-256 `926d5ddf4b8796303ec07fe051b1da36cd539fc045973bb8bb24c0bea9a588fc`, `REMOTE_ORBIT_CONTINUITY_EVIDENCE=1`.
- `EVIDENCE_INTERVAL`: FACT — process launch `2026-10-28 15:37:55.792 +0800` through incident release `2026-10-28 15:45:44.685 +0800`; selected session `AD04FCCB-020E-4071-BD90-B24EFB4B2ACE`.
- `CENTRAL_STATE_AT_APP_START`: FACT — CoreBluetooth daemon reported `Unauthorized` at `15:37:55.906 +0800` for the PID-59512 central session.
- `CENTRAL_STATE_BEFORE_PREWARM`: INFERENCE — no later state update was observed before first prewarm; the last recorded state remained Unauthorized.
- `CENTRAL_STATE_AT_PREWARM`: INFERENCE — the app emitted `等待蓝牙就绪…` at prewarm and no powered-on transition was recorded.
- `CENTRAL_STATE_AT_LONG_ACTIVATION`: INFERENCE — the app again emitted `等待蓝牙就绪…` after `BLE_START_REQUEST`; no powered-on transition or reconnect callback was recorded.
- `CENTRAL_AUTHORIZATION_STATUS`: FACT — central session state was Unauthorized; a separate numeric `CBManager.authorization` value was not emitted.
- `BLUETOOTH_POWER_STATUS`: UNKNOWN — controller power-only status is not separately proven; the app's central was not `.poweredOn` and was explicitly Unauthorized.
- `HID_TRANSPORT_STATUS`: FACT — compatibility HID down/hold/up evidence remained healthy and is independent of CoreBluetooth ATVV.
- `ATVV_COREBLUETOOTH_STATUS`: FACT — no connection, discovery, capabilities, ATVV-ready, `MIC_OPEN_TX`, `AUDIO_START`, or remote audio evidence.
- `POWERED_ON_CALLBACK_OBSERVED`: FACT — NO; neither the app's `蓝牙已就绪` marker nor a powered-on state update for this central was observed.
- `RECONNECT_AFTER_POWERED_ON_STATUS`: FACT — NOT OBSERVED; there was no powered-on callback to trigger the source's reconnect path.
- `TRANSPORT_INTENT_AT_POWERED_ON`: UNKNOWN — no powered-on callback occurred; source behavior would schedule immediate reconnect only for an active voice intent.
- `PREWARM_TO_POWERED_ON_RACE_STATUS`: INFERENCE — not supported as the minimum boundary; the only recorded central state was Unauthorized and no recovery transition occurred.
- `EVIDENCE_SUFFICIENCY`: SUFFICIENT — the minimum fault boundary is established without a new probe.
- `MISSING_FACT`: UNKNOWN — the underlying reason for the Unauthorized result (user/TCC/system policy versus another authorization condition) is not established by this diagnosis.
- `BLOCKED_DECISION`: FACT — no product fix, permission mutation, or second human session is authorized by this card.
- `INCIDENT_CLASSIFICATION`: FACT — `OUTCOME_A_PRE_MICOPEN_FAILURE`, narrowed to CoreBluetooth central authorization/readiness before ATVV connection.
- `ROOT_CAUSE_STATUS`: INFERENCE — unauthorized central admission is the earliest proven blocker; causal attribution beyond that remains UNKNOWN.
- `PROBE_REQUIRED`: FACT — NO.
- `SMALLEST_JUSTIFIED_NEXT_ACTION`: FACT — stop and preserve evidence; any authorization review or product correction requires separate authority.
- `SOURCE_CHANGED`: FACT — NO; no probe, build, install, runtime restart, permission change, driver change, CoreAudio restart, or merge occurred.

## 038-B BLE authorization-resume verification result

- `RUNTIME_PROCESS_IDENTITY`: FACT — PID `56531`, `/Applications/RemoteOrbit.app/Contents/MacOS/RemoteOrbit`, `com.lost0rz.RemoteOrbit 0.2.14 (43)`, executable SHA-256 `926d5ddf4b8796303ec07fe051b1da36cd539fc045973bb8bb24c0bea9a588fc`, only `REMOTE_ORBIT_CONTINUITY_EVIDENCE=1`.
- `INSTALLED_BUNDLE_ID`: FACT — `com.lost0rz.RemoteOrbit`.
- `INSTALLED_VERSION_BUILD`: FACT — `0.2.14 (43)`.
- `INSTALLED_BLUETOOTH_USAGE_KEYS`: FACT — `NSBluetoothAlwaysUsageDescription` and `NSBluetoothPeripheralUsageDescription` both present.
- `BLUETOOTH_AUTHORIZATION`: UNKNOWN — fresh runtime did not emit the numeric `CBManager.authorization` value; do not infer `allowedAlways` from the human Settings action.
- `CENTRAL_INITIAL_STATE`: FACT — `unauthorized` at fresh CoreBluetooth initialization.
- `CENTRAL_FINAL_STATE`: FACT — `unauthorized`; no later transition observed.
- `POWERED_ON_REACHED`: FACT — NO.
- `CONNECTION_STATE`: FACT — NOT REACHED; central remained unauthorized before reconnect/scan/retrieve.
- `SERVICE_DISCOVERY_STATE`: FACT — NOT REACHED.
- `CHARACTERISTIC_DISCOVERY_STATE`: FACT — NOT REACHED.
- `CAPABILITIES_STATE`: FACT — NOT REACHED.
- `ATVV_READY_STATE`: FACT — NOT REACHED; no `ATVV 语音链路已就绪`.
- `FINAL_STATE`: FACT — `BLOCKED_BLUETOOTH_AUTHORIZATION`.
- `SOURCE_CHANGED`: FACT — NO; no source, TCC, driver, CoreAudio, or PR lifecycle mutation.
- `NEXT`: remain stopped; do not ask for a natural session until a separately authorized fresh process reaches `.poweredOn` and ATVV readiness.

## 038-B BLE-start incident diagnosis transition

- Transition authority: FACT — the current BLE-start incident card explicitly authorizes this control-only transition and bounded existing-evidence diagnosis.
- Incident session: `AD04FCCB-020E-4071-BD90-B24EFB4B2ACE`.
- Incident interval: `2026-10-28 15:45:41.216 +0800` through `2026-10-28 15:45:44.685 +0800`.
- `LAST_CONFIRMED_GOOD_STAGE`: `INPUT/GESTURE + REMOTE_ROUTE_BEGIN`.
- `FIRST_FAILED_OR_UNCONFIRMED_STAGE`: `BLE AUDIO START / FIRST REMOTE AUDIO PACKET`.
- Root cause: UNKNOWN.
- No second user session is authorized in this pass.
- No product fix is authorized in this pass.

## Runtime-capture result receipt

- `TOTAL_VOICE_SESSIONS=0`; `USABLE_SESSION_COUNT=0`; `EXCLUDED_SESSION_COUNT=0` because no session was emitted.
- `PROBE_HEALTH=FAIL/INCOMPLETE`: no `CONTINUITY_SESSION`, `CONTINUITY_BUCKET`, matching session identity, or `render_capacity_dropped` record was observed; app log reports `input=false accessibility=false`.
- `SESSION_JOIN_INTEGRITY=UNKNOWN`; `RENDER_CAPACITY_DROP_STATUS=UNKNOWN`; no per-session metrics or comparisons are available.
- `RUNTIME_BUILD_IDENTITY=FACT`: `com.lost0rz.RemoteOrbit` `0.2.14 (43)`, universal arm64+x86_64, installed `/Applications/RemoteOrbit.app`, executable SHA-256 `926d5ddf4b8796303ec07fe051b1da36cd539fc045973bb8bb24c0bea9a588fc`.
- `CAPTURE_ENVIRONMENT=FACT`: only `REMOTE_ORBIT_CONTINUITY_EVIDENCE=1`; log identity is `/Users/ox_miles/Library/Logs/RemoteOrbit/RemoteOrbit.log` plus `voice-diagnostic-current.jsonl`; local PTY capture is `/private/tmp/remoteorbit-038-b-runtime-capture.wWfAWx/diagnostic.tty.log`.
- `ROOT_CAUSE_STATUS=UNKNOWN`: decoder rejection, overflow, BLE cadence, PCM supply, active underrun, and final-text omission remain unclassified. The smallest justified next action is user-owned permission authorization followed by natural voice sessions, with at least one healthy probe session before the preferred ten-session set.

## Corrective-4 delivery receipt

- Audit finding reproduced: FACT — `AudioPipe.schedule()` held `stateLock` across `VoiceTimingLogger.recordContinuitySubmitted()`, which acquired shared diagnostic locking and mutated the central dictionary.
- Architecture delivered: FACT — the same timestamp, submitted frames, queue depth, 100 ms alignment, capture identity, provisional late-binding origin, and session association now use the existing AudioPipe-owned fixed-capacity ledger; detached snapshot merge carries submission and render evidence once.
- State-lock audit: FACT — AudioPipe continuity calls under `stateLock` are now only `continuityRenderLedger?.recordSubmitted`, `recordRender`, and `recordOverflow`; none acquires the VoiceTimingLogger lock, mutates a shared dictionary/hash, formats/prints, dispatches synchronously, or performs unbounded aggregation.
- Verification: FACT — focused diagnostics 32/32, AudioPipe 4/4, VoiceBoundaryOrdering 3/3, VoicePressCoordinator 39/39, full Swift 421/421, release build PASS, and diff check PASS.
- Product/runtime boundary: UNKNOWN — no installed/runtime capture was performed, so this delivery does not establish runtime underrun behavior or an audio root cause.

## Corrective-3 delivery receipt

- Audit finding reproduced: FACT — when AUDIO_START arrived before HID, `currentContinuityContext()` was nil, AudioPipe created no render ledger, and later HID session creation had no binding path.
- Correlation architecture: FACT — opt-in AUDIO_START creates a stable `captureID`; the AudioPipe render ledger stores the capture start and can bind exactly once to the later gesture UUID. HID-before-AUDIO_START creates the same bound capture through the existing logger session.
- Pre-session evidence: FACT — BLE/decode records are accepted while the provisional capture awaits its session, and pre-session render buckets remain in fixed storage until late binding; the bucket origin stays the AUDIO_START monotonic timestamp so the snapshot joins the central ledger.
- Stale/wrong-session protection: FACT — AudioPipe binding requires the exact captureID and an unbound active ledger; wrong and repeated bindings are rejected, and captureID is checked again during snapshot merge.
- Render/lifecycle preservation: FACT — render remains AudioPipe-owned fixed-capacity mutation only; late binding is bounded metadata under `stateLock`; construction remains outside the lock; snapshot remains after safe detach; default-off keeps the ledger nil.
- Product/runtime boundary: UNKNOWN — no installed/runtime capture was performed, so no runtime underrun or audio root-cause claim is made.

## 038-B Bluetooth app-identity reconciliation result

- `RUNNING_DIAGNOSTIC_IDENTITY`: FACT — PID `56531`, `/Applications/RemoteOrbit.app/Contents/MacOS/RemoteOrbit`, bundle `com.lost0rz.RemoteOrbit`, version/build `0.2.14 (43)`, executable SHA-256 `926d5ddf4b8796303ec07fe051b1da36cd539fc045973bb8bb24c0bea9a588fc`, designated requirement `identifier "com.lost0rz.RemoteOrbit"`, CDHash `7465273e606e288198cff206625bb46b46f8c819`.
- `DISCOVERED_APP_COUNT`: FACT — 16 plausible on-disk `.app` bundles; 15 exact `com.lost0rz.RemoteOrbit` bundles and one `com.lost0rz.RemoteOrbit.P1A5Observer` observer bundle.
- `REMOTE_ORBIT_APP_PATH`: FACT — `/Applications/RemoteOrbit.app` is the current installed diagnostic app.
- `REMOTE_ORBITAL_APP_PATH`: FACT — `NONE_FOUND` in `/Applications`, `~/Applications`, `/Users/Shared`, the RemoteOrbit project/archive/build roots, relevant Code/dist roots, and disposable runtime roots.
- `BUNDLE_ID_COLLISIONS`: FACT — 15 on-disk candidates share `com.lost0rz.RemoteOrbit`; they span current 0.2.14 (43), archived 0.2.13 (42), and historical 0.2.11 (40) identities with different executable hashes/CDHashes. The observer has a separate bundle ID.
- `LAUNCHSERVICES_REGISTRATIONS`: FACT — 21 records for `com.lost0rz.RemoteOrbit`: one current `/Applications/RemoteOrbit.app` record and 20 stale/nonexistent historical paths/records, including old mounted-volume, Trash, backup, and miremotevoice dist paths. No `Remote Orbital` registration was observed.
- `BLUETOOTH_UI_VISIBLE_NAME`: FACT — user-reported as `Remote Orbital`; independently captured bundle identity is UNKNOWN.
- `MATCH_STATUS`: FACT — `STALE_OR_UNRESOLVED_ENTRY`.
- `CURRENT_APP_VS_VISIBLE_PERMISSION_ENTRY`: INFERENCE — the current app is not proven to own the visible entry; the name differs and no actual different `Remote Orbital` app exists to establish a cross-application mapping.
- `IDENTITY_CONCLUSION`: FACT — no exact identity match and no conclusively different installed app; with the fresh runtime still recorded as CoreBluetooth `Unauthorized`, stop as `BLUETOOTH_TCC_IDENTITY_STALE_OR_UNRESOLVED`.
- `SOURCE_CHANGED`: FACT — NO.
- `SYSTEM_STATE_CHANGED`: FACT — NO; LaunchServices and TCC were read only.
- `WORKTREE_STATUS`: FACT — clean before and after the control-only record.
- `PR_STATE`: FACT — PR #24 remains OPEN, DRAFT, UNMERGED; current head is this paired control transition after publication.
- `SMALLEST_JUSTIFIED_NEXT_ACTION`: FACT — STOP; do not reset TCC, replace/rebuild/reinstall the app, change drivers/CoreAudio, or request a voice session. Require a separately authorized identity-preserving Bluetooth authorization review.

## 038-B Bluetooth authorization post-grant verification result

- `RUNTIME_PROCESS_IDENTITY`: FACT — PID `21428`, `/Applications/RemoteOrbit.app/Contents/MacOS/RemoteOrbit`, bundle `com.lost0rz.RemoteOrbit`, version/build `0.2.14 (43)`, executable SHA-256 `926d5ddf4b8796303ec07fe051b1da36cd539fc045973bb8bb24c0bea9a588fc`, designated requirement `identifier "com.lost0rz.RemoteOrbit"`; process environment confirms only `REMOTE_ORBIT_CONTINUITY_EVIDENCE=1` as the diagnostic variable.
- `BLUETOOTH_AUTHORIZATION`: UNKNOWN — numeric `CBManager.authorization` was not emitted; the human UI grant is not substituted for process-level numeric evidence.
- `CENTRAL_INITIAL_STATE`: FACT — `poweredOn`, established by the first fresh `[BLE] 蓝牙已就绪` marker at `17:44:08`.
- `CENTRAL_FINAL_STATE`: FACT — `poweredOn`; no later contrary state was observed while PID `21428` remained alive.
- `POWERED_ON_REACHED`: YES.
- `CONNECTION_STATE`: FACT — ATVV peripheral connection was NOT OBSERVED; the only connection marker was HID compatibility/monitored mode.
- `SERVICE_DISCOVERY_STATE`: FACT — NOT REACHED/OBSERVED.
- `CHARACTERISTIC_DISCOVERY_STATE`: FACT — NOT REACHED/OBSERVED.
- `CAPABILITIES_STATE`: FACT — NOT REACHED/OBSERVED.
- `ATVV_READY_STATE`: FACT — NOT REACHED/OBSERVED; no fresh `ATVV 语音链路已就绪` marker.
- `LAST_CONFIRMED_GOOD_STAGE`: `COREBLUETOOTH CENTRAL READY / POWERED_ON`.
- `FIRST_FAILED_OR_UNCONFIRMED_STAGE`: `ATVV TRANSPORT PREPARATION — RECONNECT/PREWARM PATH NOT OBSERVED`.
- `SOURCE_CHANGED`: NO.
- `CHANGED_FILES`: control records only; no product source changed.
- `SMALLEST_JUSTIFIED_NEXT_ACTION`: STOP without a voice session. A new authority decision is required before any active transport trigger or natural session.

## 038-B post-Bluetooth first-natural-session authorization transition

- `CONTROL_TRANSITION`: FACT — the current `RO-038-B-POST-BLUETOOTH-FIRST-NATURAL-SESSION` card corrects the passive-readiness assumption and explicitly authorizes exactly one natural voice session after this control-only transition.
- `BLUETOOTH_AUTHORIZATION_BOUNDARY`: FACT — the fresh installed runtime reached CoreBluetooth `.poweredOn` and emitted `[BLE] 蓝牙已就绪`; the Bluetooth authorization blocker is resolved at runtime boundary.
- `PASSIVE_ATVV_EXPECTATION`: FACT — INVALID TEST ASSUMPTION. ATVV preparation is demand-triggered by voice-key pending/prewarm through `onRemoteTransportPreparation` → `prepareVoiceTransport()`.
- `CURRENT_STATE`: FACT — `READY_FOR_ONE_NATURAL_SESSION`.
- `RUNTIME_PROCESS_IDENTITY`: FACT — preserve PID `21428`, `/Applications/RemoteOrbit.app`, bundle `com.lost0rz.RemoteOrbit`, version/build `0.2.14 (43)`, executable SHA-256 `926d5ddf4b8796303ec07fe051b1da36cd539fc045973bb8bb24c0bea9a588fc`, and only `REMOTE_ORBIT_CONTINUITY_EVIDENCE=1`.
- `ROOT_CAUSE_STATUS`: UNKNOWN — the original audio-continuity problem remains unclassified.
- `SOURCE_CHANGED`: NO.
- `CHANGED_FILES`: control records only; no product source changed.
- `NEXT_ACTION`: FACT — request exactly one natural long voice interaction; no synthetic key event, weak-BLE condition, retry, second session, or corrective source work.
