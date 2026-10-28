# RemoteOrbit Current Task

## RO-RUNTIME-RELIABILITY-038 — Task 038

- Status: BASE_RATE_AUDIT_COMPLETE — 038-B STOP.
- Task class: RUNTIME RELIABILITY / DIAGNOSTIC EVIDENCE.
- Repository: `Lost0rz/RemoteOrbit`.
- Canonical repository: `/Volumes/Jack-Dev/Projects/remoteorbit`.
- Control baseline: `main` after PR #23 merge commit `79f3db92024e8a901d3a0fcec2c1f194c7136753` and the paired 038-B activation transition.
- 038-A is merged and closed to further product mutation unless a new regression specifically reopens it.
- Task 037 human acceptance debt remains pending and is not rewritten by Task 038.

## Roadmap state

- `038-A MERGED / COMPLETE`: rapid re-press admission.
- `038-B BASE_RATE_AUDIT_COMPLETE`: the same 10 usable natural sessions were reanalyzed with ACTIVE-STREAM denominators; BLE cadence remains a recurring contributor, PCM-supply causality is downgraded, and root cause remains NARROWED_NOT_ESTABLISHED. No new runtime capture is authorized.
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

The 10-session evidence set is frozen and the authorized 038-B base-rate/lag audit is complete. Stop here; do not request another session, mutate product behavior, change TCC, driver, or CoreAudio, or merge.

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

## 038-B first natural session result

- `SESSION_ID`: FACT — `F406982F-E2F8-4EE6-A228-C12A37B20BE7`.
- `SESSION_INTERVAL`: FACT — `2026-10-28 19:19:13.941 +0800` through `19:19:23.822 +0800`.
- `HID_TRIGGER_STATUS`: FACT — HID down, `VOICE_DOWN`, `HOLD_CONFIRMED`, physical up; one natural session only.
- `PREWARM_STATUS`: FACT — demand-triggered transport prewarm and saved-UUID connect executed.
- `CONNECTION_STATE`: FACT — ATVV peripheral connected.
- `SERVICE_DISCOVERY_STATE`: FACT — ATVV service discovered.
- `CHARACTERISTIC_DISCOVERY_STATE`: FACT — command, audio, and control characteristics discovered/subscribed.
- `CAPABILITIES_STATE`: FACT — capabilities response accepted, codec `ADPCM 16 kHz`.
- `ATVV_READY_STATE`: FACT — `ATVV 语音链路已就绪`.
- `MIC_OPEN_TX_STATUS`: FACT — transmitted at +312.8 ms.
- `AUDIO_START_STATUS`: FACT — received at +370.3 ms.
- `FIRST_AUDIO_PACKET_STATUS`: FACT — first audio at +370.6 ms / +16.0 ms from AUDIO_START.
- `DECODE_STATUS`: FACT — 516 frames / 123,840 samples; decode rejects `0`; zero-sample decodes `0`.
- `PCM_SUBMISSION_STATUS`: FACT — 371,520 submitted frames.
- `AUDIOPIPE_RENDER_STATUS`: FACT — 393,216 requested; 371,520 filled; 21,696 unfilled; 62 active underrun callbacks / 452.0 ms; overflow drops `0`.
- `CONTINUITY_SESSION_PRESENT`: YES.
- `CONTINUITY_BUCKET_PRESENT`: YES — 83 buckets at 100 ms.
- `SESSION_JOIN_INTEGRITY`: PASS — same session ID joins timing, BLE/decode, submission, render, and continuity records.
- `RENDER_CAPACITY_DROP_STATUS`: `0`.
- `HUMAN_AUDIO_RECEPTION`: UNKNOWN — remote PCM/WAV evidence exists; target input-method waveform was not independently observed.
- `LAST_CONFIRMED_GOOD_STAGE`: `CONTINUITY SESSION/BUCKET CLOSE`.
- `FIRST_FAILED_OR_UNCONFIRMED_STAGE`: `NONE` for required stage reachability; quality deficits were observed in BLE supply cadence and AudioPipe active render.
- `PROBE_HEALTH_STATUS`: `PASS` — complete evidence chain, not an audio-quality verdict.
- `ROOT_CAUSE_STATUS`: UNKNOWN — one session is insufficient for causal attribution; no corrective action authorized.
- `SOURCE_CHANGED`: NO.
- `CHANGED_FILES`: control records only; no product source changed.
- `NEXT_ACTION`: STOP. Do not perform a second session or fix source until this session is evaluated under a separate continuation decision.

## 038-B multi-session capture activation

- `CONTROL_TRANSITION`: FACT — `FIRST_SESSION_PROBE_PASS` → `MULTI_SESSION_CAPTURE_ACTIVE`, authorized by `RO-038-B-MULTI-SESSION-CONTINUITY-CAPTURE-20261028`.
- `FIRST_SESSION_PROBE`: FACT — one usable natural LONG session completed the full BLE → decode → PCM submission → AudioPipe render → continuity evidence chain.
- `RUNTIME_PROBE_HEALTH`: FACT — installed PID `21428` remains the expected `/Applications/RemoteOrbit.app` diagnostic runtime with `REMOTE_ORBIT_CONTINUITY_EVIDENCE=1`; no runtime identity or environment drift observed.
- `CAPTURE_TARGET`: FACT — at least 10 usable natural LONG sessions total.
- `CAPTURE_PROGRESS`: FACT — 1 usable session already exists; at least 9 additional usable sessions are required.
- `SESSION_METHOD`: FACT — natural press-and-hold voice interactions only, with naturally varying utterance lengths and ordinary release; no synthetic events, manufactured weak Bluetooth, CPU load, or intentional underrun induction.
- `STOP_BOUNDARY`: FACT — stop on continuity probe regression, session-identity join failure, `render_capacity_dropped > 0` compromising evidence, runtime/environment drift, source-change requirement, out-of-scope evidence, or need for corrective product work.
- `ROOT_CAUSE_STATUS`: UNKNOWN — the first session observed BLE cadence deficit and active AudioPipe underrun, but causal ownership remains unproven.
- `SOURCE_CHANGED`: NO.
- `CHANGED_FILES`: control records only; no product source changed.
- `NEXT_ACTION`: collect at least 9 additional usable natural LONG sessions, then perform the required 038-B correlation analysis; do not fix or merge.

## 038-B multi-session causal analysis result

- `CONTROL_TRANSITION`: FACT — `MULTI_SESSION_CAPTURE_ACTIVE` → `CAUSAL_ANALYSIS_COMPLETE`, authorized by `RO-038-B-MULTI-SESSION-CAUSAL-ANALYSIS-20261028`.
- `RUNTIME_PROCESS_IDENTITY`: FACT — PID `21428`, `/Applications/RemoteOrbit.app/Contents/MacOS/RemoteOrbit`, `com.lost0rz.RemoteOrbit`, version/build `0.2.14 (43)`, executable SHA-256 `926d5ddf4b8796303ec07fe051b1da36cd539fc045973bb8bb24c0bea9a588fc`, `REMOTE_ORBIT_CONTINUITY_EVIDENCE=1`.
- `EVIDENCE_WINDOW`: FACT — `2026-10-28 19:19:13.941–19:58:44.510 +0800`; source files were `/Users/ox_miles/Library/Logs/RemoteOrbit/RemoteOrbit.log`, `voice-diagnostic-current.jsonl`, and `diagnostic-events-v1.jsonl`.
- `TOTAL_CAPTURED_SESSIONS`: FACT — 10 current-runtime sessions in the frozen window.
- `USABLE_SESSION_COUNT`: FACT — 10.
- `EXCLUDED_SESSION_COUNT`: FACT — 1 complete historical candidate excluded; earlier pre-window records are not part of the candidate set.
- `EXCLUDED_SESSION_REASONS`: FACT — `A2B3B6DA-524C-4882-BD0C-C718D839B07E` belonged to PID `18405`, not PID `21428`, and preceded the frozen window.
- `SESSION_JOIN_INTEGRITY`: FACT — all 10 have matching BLE/decode, PCM submission, AudioPipe render, continuity session, exact bucket counts, and JSONL gesture identity; all `render_capacity_dropped=0`.

### Per-session metrics

| Session | Duration ms / class | BLE notif / bytes | Max/p95 gap ms | >20/>30/>50/>100 | Decode frames / samples | Reject / zero | Deficit ms / ratio | Submitted | Render req / filled / unfilled | Unfilled ratio | Buckets |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `F406982F-E2F8-4EE6-A228-C12A37B20BE7` | 8195.5 / LONGER | 516 / 61920 | 46.8 / 20.0 | 10/3/0/0 | 516 / 123840 | 0 / 0 | 73.3 / .991 | 371520 | 393216 / 371520 / 21696 | .0552 | 83 |
| `D79D6B0C-8CFF-454A-A564-7005FEA87657` | 4350.7 / MID | 260 / 31200 | 43.8 / 20.0 | 4/2/0/0 | 260 / 62400 | 0 / 0 | 71.8 / .982 | 187200 | 208896 / 187200 / 21696 | .1039 | 44 |
| `0D51AF58-FA64-4257-9685-E853A65D197F` | 4248.1 / MID | 256 / 30720 | 30.1 / 20.0 | 6/2/0/0 | 256 / 61440 | 0 / 0 | 27.2 / .993 | 184320 | 203776 / 194304 / 9472 | .0465 | 47 |
| `BA456267-CF2B-4232-BAD9-4233247DCED9` | 4007.3 / MID | 238 / 28560 | 43.6 / 20.0 | 5/2/0/0 | 238 / 57120 | 0 / 0 | 56.8 / .984 | 171360 | 192000 / 171360 / 20640 | .1075 | 41 |
| `71E09B69-3CEE-44E2-972B-B9341685FA7E` | 4375.1 / MID | 263 / 31560 | 29.0 / 20.0 | 4/0/0/0 | 263 / 63120 | 0 / 0 | 42.4 / .989 | 189360 | 209920 / 199856 / 10064 | .0479 | 48 |
| `F7DEE325-89C4-44F4-9EE8-C7D5E5D5A58B` | 4457.8 / MID | 268 / 32160 | 43.1 / 20.0 | 4/1/0/0 | 268 / 64320 | 0 / 0 | 56.4 / .986 | 192960 | 214528 / 192960 / 21568 | .1005 | 45 |
| `7F3C5863-CB0A-4551-9B43-B005F4E3C81F` | 3858.6 / SHORTER | 230 / 27600 | 29.2 / 20.0 | 3/0/0/0 | 230 / 55200 | 0 / 0 | 25.6 / .993 | 165600 | 185344 / 178256 / 7088 | .0382 | 43 |
| `1E93CE1D-92FC-4278-833D-9EF5702717F2` | 4040.7 / MID | 240 / 28800 | 42.4 / 20.0 | 5/1/0/0 | 240 / 57600 | 0 / 0 | 58.1 / .984 | 172800 | 194560 / 182368 / 12192 | .0627 | 45 |
| `AECDBF50-CBDE-406F-A755-9D449051D710` | 3991.2 / SHORTER | 238 / 28560 | 29.0 / 20.0 | 4/0/0/0 | 238 / 57120 | 0 / 0 | 44.5 / .988 | 171360 | 192000 / 182368 / 9632 | .0502 | 44 |
| `CD939D47-F114-48E3-998C-1B49527C4A74` | 3813.9 / SHORTER | 225 / 27000 | 43.6 / 20.0 | 4/1/0/0 | 225 / 54000 | 0 / 0 | 56.8 / .983 | 162000 | 182784 / 171056 / 11728 | .0642 | 42 |

- Per-session render/lifecycle facts: `max_underrun_frames=512` for all; total underrun callbacks/ms are respectively `62/452.0`, `53/452.0`, `19/197.3`, `48/430.0`, `20/209.7`, `51/449.3`, `14/147.7`, `24/254.0`, `19/200.7`, `23/244.3`. `tail_rendered_frames=0`, `idle_render_callbacks=0`, `queue_depth_min=0`, `queue_depth_end=0`, and `overflow_dropped_frames=0` for every session. Queue maxima in row order are `2688, 1568, 11264, 1680, 11632, 1424, 13632, 10368, 11872, 10320` frames; tail-empty callbacks are `1,1,0,1,1,0,0,0,0,1`; compaction counts are `81,41,42,37,43,42,39,39,39,37`. `HUMAN_QUALITY=NOT_REPORTED` for all.

### Cross-session and bucket findings

- `SHORTER_VS_LONGER_COMPARISON`: INFERENCE — active underrun occurred in 0/3 SHORTER, 3/6 MID, and 1/1 LONGER sessions. The longer session has more absolute audio/tail volume, but no monotonic duration effect is established.
- `NORMAL_VS_WEAK_COMPARISON`: UNKNOWN — no human weak/normal quality report was captured; telemetry alone is not promoted to human quality.
- `SESSION_LEVEL_CORRELATIONS`: INFERENCE — all sessions had p95 gap `20.0 ms`; max gaps were `29.0–46.8 ms`, with no >50 or >100 ms summary gaps. The four active-underrun sessions had max gaps `43.1–46.8 ms`, but a no-active session also had `43.6 ms`; delivery ratios/deficits overlap, so session aggregates are not sufficient.
- `BUCKET_LEVEL_TEMPORAL_FINDINGS`: INFERENCE — 48 active unfilled buckets were observed across four sessions. Fifteen had same-bucket submitted frames ≥ requested frames, while 33 were below; 19 had gap maxima >20 ms and 7 >30 ms. Example: F406 `300–500 ms` had BLE 11 / max gap 46.8 ms / decoded 2640 / submitted 7920 versus render requested 6656, yet 912 frames were unfilled. Conversely D79 `3800–3900 ms` had gap 43.1 ms / submitted 3600 versus requested 5120 / 1312 unfilled, and BA `2700–2800 ms` had gap 43.6 ms / submitted 3600 versus requested 4608 / 1440 unfilled. This supports a recurring upstream contribution but also shows starvation with healthy aggregate submission.
- `STARTUP_UNDERRUN_ANALYSIS`: FACT — no startup/prestable bucket had render unfilled frames. Six sessions had `AUDIO_FIRST` before `AUDIO_START` by `199.7–247.8 ms`; those provisional buckets had no render demand and were not counted as active underrun.
- `ACTIVE_STREAM_UNDERRUN_ANALYSIS`: FACT — active unfilled frames were `15808` across four sessions with 73 active underrun callbacks; active unfilled ratio over all active render requests was about `0.86%`. Same-bucket healthy submission in 15 buckets is evidence against a purely upstream-supply explanation.
- `TAIL_UNDERRUN_ANALYSIS`: FACT — tail/teardown unfilled frames were `129968` (about `89.2%` of all unfilled frames), beginning at/after `AUDIO_STOP`; they are kept separate from active-stream continuity.

### Causal verdict

- `DECODER_REJECTION_CAUSAL_STATUS`: `DOWNGRADED` — FACT: zero rejects and zero-sample decodes in all 10 sessions.
- `OVERFLOW_CAUSAL_STATUS`: `DOWNGRADED` — FACT: zero overflow drops in summaries and buckets.
- `BLE_CADENCE_CAUSAL_STATUS`: `SUPPORTED` — INFERENCE: repeated active buckets show cadence gaps coinciding with reduced submission and unfilled render, but this is a contributor verdict, not an exclusive root cause.
- `PCM_SUPPLY_TO_UNDERRUN_CAUSAL_STATUS`: `SUPPORTED` — INFERENCE: 33 active unfilled buckets had submitted frames below requested; 15 active unfilled buckets had submitted frames at least equal to requested.
- `ACTIVE_STREAM_UNDERRUN_STATUS`: `FACT` — four of ten sessions contain active-stream unfilled frames; the other six show only boundary/tail unfilled frames.
- `FINAL_TEXT_OMISSION_STATUS`: `UNKNOWN` — no 038-F observation was added.
- `ROOT_CAUSE_STATUS`: `NARROWED_NOT_ESTABLISHED`.
- `ROOT_CAUSE_EVIDENCE`: FACT — decoder rejection and overflow are not supported; INFERENCE — BLE/PCM supply contributes to some active starvation; FACT — active starvation also occurs with healthy same-bucket submitted supply and tail dominates aggregate unfilled frames.
- `COMPETING_EXPLANATIONS_REMAINING`: AudioPipe intra-bucket queue/render scheduling or demand timing; BLE/PCM cadence contribution; boundary/teardown behavior; no evidence for final text omission; no human quality classification.
- `SMALLEST_JUSTIFIED_NEXT_ACTION`: STOP for 038-B evidence capture. Any AudioPipe/BLE corrective proposal requires a separate governance transition and must not be implemented from this receipt.
- `SOURCE_CHANGED`: NO.
- `CHANGED_FILES`: control records only; no product source changed.
- `FINAL_TEXT_OMISSION_STATUS`: UNKNOWN.

## 038-B active-bucket base-rate audit result

- `CONTROL_TRANSITION`: FACT — `CAUSAL_ANALYSIS_COMPLETE` -> `EXISTING_EVIDENCE_BASE_RATE_AUDIT` was published at `a29b7c1b60581a2a58eb2238fef9ff6a9c31bddd`; this result returns 038-B to a stopped state.
- `AUDIT_PROFILE`: FACT — `FORMAL_READ_ONLY_BASE_RATE_AND_LAG_AUDIT` over the frozen 10-session evidence set; no new runtime capture.
- `AUDIT_INDEPENDENCE`: FACT — `SELF_CHECK` with fresh raw-log reanalysis and a separate ACTIVE-STREAM denominator; not separate-agent acceptance.
- `EVIDENCE_SET_IDENTITY`: FACT — PID `21428`, `/Applications/RemoteOrbit.app/Contents/MacOS/RemoteOrbit`, bundle `com.lost0rz.RemoteOrbit`, version/build `0.2.14 (43)`, executable SHA-256 `926d5ddf4b8796303ec07fe051b1da36cd539fc045973bb8bb24c0bea9a588fc`, environment `REMOTE_ORBIT_CONTINUITY_EVIDENCE=1`; frozen window `2026-10-28 19:19:13.941–19:58:44.510 +0800`; sources `/Users/ox_miles/Library/Logs/RemoteOrbit/RemoteOrbit.log`, `/Users/ox_miles/Library/Logs/RemoteOrbit/voice-diagnostic-current.jsonl`, and `/Users/ox_miles/Library/Logs/RemoteOrbit/diagnostic-events-v1.jsonl`.
- `BUCKET_CLASSIFICATION`: FACT — 482 total buckets: 18 startup/prestable, 391 ACTIVE, 73 tail; only ACTIVE buckets entered the base-rate denominators. `ACTIVE_UNDERRUN_BUCKET_COUNT=48`; `ACTIVE_NO_UNDERRUN_BUCKET_COUNT=343`; all 10 session joins remained exact and `render_capacity_dropped=0`.
- `ACTIVE_UNDERRUN_METRICS`: FACT — 293 BLE notifications / 48 buckets (6.1042 per bucket), decoded samples `70,320`, submitted frames `210,960`, render requested/filled/unfilled `222,208/206,400/15,808`; mean max BLE gap `22.4250 ms`, mean submitted/requested ratio `0.961100`, mean queue min/max/end `0/1228/604.3333` frames.
- `ACTIVE_NO_UNDERRUN_METRICS`: FACT — 2,260 BLE notifications / 343 buckets (6.5889 per bucket), decoded samples `542,400`, submitted frames `1,608,480`, render requested/filled/unfilled `1,622,528/1,622,528/0`; mean max BLE gap `16.9327 ms`, mean submitted/requested ratio `0.993964`, mean queue min/max/end `5432.0233/6595.2187/6006.5773` frames.
- `BLE_GT20_RATE_UNDERRUN`: FACT — `19/48 = 39.5833%`.
- `BLE_GT20_RATE_CONTROL`: FACT — `33/343 = 9.6210%`; effect `+29.9623 pp`, risk ratio `4.1143`.
- `BLE_GT30_RATE_UNDERRUN`: FACT — `7/48 = 14.5833%`.
- `BLE_GT30_RATE_CONTROL`: FACT — `6/343 = 1.7493%`; effect `+12.8341 pp`, risk ratio `8.3368`.
- `SUPPLY_DEFICIT_RATE_UNDERRUN`: FACT — `33/48 = 68.7500%` for `submitted_frames < render_requested`.
- `SUPPLY_DEFICIT_RATE_CONTROL`: FACT — `204/343 = 59.4752%`; effect `+9.2748 pp`, risk ratio `1.1559`; aggregate submitted/requested ratios were `0.949381` versus `0.991342`.
- `LAG_MINUS_2_FINDING`: FACT — 43 eligible active neighbors; gap `>20 ms` `9.3023%`, `>30 ms` `0%`, supply deficit `67.4419%`; no consistent upstream relationship.
- `LAG_MINUS_1_FINDING`: FACT — 44 eligible active neighbors; gap `>20 ms` `20.4545%`, `>30 ms` `6.8182%`, supply deficit `70.4545%`; supply deficit is present before the underrun but BLE-gap precedence is not consistent.
- `LAG_ZERO_FINDING`: FACT/INFERENCE — 48 eligible active buckets; gap `>20 ms` `39.5833%`, `>30 ms` `14.5833%`, supply deficit `68.7500%`; BLE cadence is enriched and coincides with underrun, while supply deficit is only weakly enriched.
- `LAG_PLUS_1_FINDING`: FACT — 47 eligible active neighbors; gap `>20 ms` `8.5106%`, `>30 ms` `8.5106%`, supply deficit `55.3191%`; no repeated downstream relationship.
- `INTRA_BUCKET_ORDERING_STATUS`: UNKNOWN — `submitted_frames >= render_requested` is an aggregate 100 ms fact and does not establish that PCM arrived before each render demand within the bucket.
- `DECODER_REJECTION_CAUSAL_STATUS`: DOWNGRADED — FACT: all 10 sessions had zero decode rejects and zero zero-sample decodes.
- `OVERFLOW_CAUSAL_STATUS`: DOWNGRADED — FACT: all session summaries and buckets had zero overflow drops.
- `BLE_CADENCE_CAUSAL_STATUS`: SUPPORTED_AS_RECURRING_CONTRIBUTOR — INFERENCE: gap thresholds are materially enriched in active underrun buckets and peak at lag zero; this is not an exclusive root-cause claim.
- `PCM_SUPPLY_TO_UNDERRUN_CAUSAL_STATUS`: DOWNGRADED_FROM_SUPPORTED — INFERENCE: supply deficit is only weakly enriched versus active controls and has no consistent lagged precedence; same-bucket ordering remains UNKNOWN.
- `ACTIVE_STREAM_UNDERRUN_STATUS`: FACT — 48 active underrun buckets across four of ten sessions; startup/prestable underrun was absent, and tail/teardown remains a separate boundary population.
- `NORMAL_VS_WEAK_COMPARISON`: UNKNOWN — no human weak/normal quality labels were captured.
- `FINAL_TEXT_OMISSION_STATUS`: UNKNOWN — no text-output observation was authorized or captured.
- `ROOT_CAUSE_STATUS`: NARROWED_NOT_ESTABLISHED — FACT: decoder rejection and overflow are not supported; INFERENCE: BLE cadence recurs as a contributor; UNKNOWN: AudioPipe intra-bucket ordering/scheduling and final human/text impact.
- `UNVERIFIED_REQUIRED_CLAIMS`: FACT — human-visible waveform/audio reception, normal-versus-weak quality, intra-bucket ordering, and final text omission remain unverified.
- `AUDIT_VERDICT`: STOP — the required evidence boundary is complete, but it does not authorize a corrective product change or establish an exclusive root cause.
- `SMALLEST_JUSTIFIED_NEXT_ACTION`: STOP. Any BLE/AudioPipe corrective proposal or finer-grained ordering probe requires a new governance transition; do not request another session in this pass.
- `SOURCE_CHANGED`: NO.
- `CHANGED_FILES`: `CURRENT_STATUS.md` and `CURRENT_TASK.md` control records only.
- `PR_STATE`: OPEN / DRAFT / UNMERGED; no merge performed.
- `WORKTREE_STATUS`: CLEAN after the control-only result commit.
- `FINAL_STATE`: `BASE_RATE_AUDIT_COMPLETE — TASK 038-B STOP`.
