# CURRENT_STATUS

Last updated: 2026-10-28
State: EXECUTING — TASK 038-B CORRECTIVE-4 SUBMISSION-PATH CONTENTION
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
- PR #24 is OPEN + DRAFT + UNMERGED; its live head is the current tip of the authorized branch and must be read directly for any future transition. Corrective-2 delivery commit `ebd6f1daa6a15f4790ec0faa342dc80a1a0c518a` removes the remaining lifecycle observer-effect. Corrective-3 delivery commit `7d33e01cf94aa3685ccfdecc6df28207258cb1bb` closes only the AUDIO_START-before-HID continuity-correlation gap. No runtime capture, installation, merge, audio tuning, or 038-C/D/E/F work is authorized.

## Task 038-B writer identity

- Authorized branch: `codex/runtime-reliability-038-b-continuity-evidence`.
- Authorized worktree: `/private/tmp/remoteorbit-runtime-reliability-038-b-continuity-evidence`.
- Start HEAD: `e80c8be50fa489c7f04c4ca5567aff7cc5d3af9b`.
- Worktree registration: this paired control commit; worktree was clean before any source/test or diagnostic mutation.
- Current source/test HEAD: `7d33e01cf94aa3685ccfdecc6df28207258cb1bb`, pushed and verified equal to the authorized remote branch before this paired control update.
- Corrective-1 audit baseline: PR #24 head `59fa6a5f0a20f48b623d0edefd1863e6c9073460`; render-side continuity capture currently calls the shared `VoiceTimingLogger` lock and mutates its bucket dictionary while `AudioPipe.stateLock` is held.
- Corrective-1 delivery: source/test commit `0c26c61c2a2ec1f147f6179b20a864f335af1dfb`; render-side capture now uses AudioPipe-owned fixed-capacity storage and merges a lifecycle snapshot outside the render path.
- Corrective-2 delivery: source/test commit `ebd6f1daa6a15f4790ec0faa342dc80a1a0c518a`; enabled storage is prepared before the lock, end detaches under the lock, and snapshot/filter runs after unlock.

## Task 038 roadmap

- `038-A MERGED / COMPLETE`: rapid re-press admission.
- `038-B EXECUTING`: corrective-4 is removing submission-path probe contention; no runtime capture is authorized.
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

- Phase: 038-B EXECUTING — corrective-4 submission-path contention correction.
- First local action completed: reconciled fresh `main`, proved and retired the merged 038-A worktree, and fast-forwarded canonical `main` to the activation head.
- Current conclusion: existing telemetry was insufficient for mid-stream temporal alignment; the minimum opt-in 100 ms monotonic/session bucket ledger remains in source/test commit `ebd6f1d`, and buffer sizing, pacing, codec behavior, gesture semantics, Option handling, and text-output behavior remain unchanged.
- Audit property reproduced: the prior render-side probe acquired the shared logger lock and mutated its dictionary while `AudioPipe.stateLock` was held, creating probe self-contention risk.
- Corrective-1 result: render-side continuity capture now uses AudioPipe-owned preallocated fixed-capacity storage (8,192 buckets), with no new logger lock, dictionary/hash mutation, formatting/printing, synchronous dispatch, or unbounded allocation in the probe path; snapshot/filter/merge occur after capture ends.
- Corrective-2 audit basis (before delivery): begin/end reset or filtered the full 8,192-bucket ledger while holding `AudioPipe.stateLock`; the default-off path also performed the full reset.
- Corrective-2 boundary: preserve the fixed-capacity render ledger and evidence fields, but make disabled activation/deactivation cheap, keep lock-held transitions bounded metadata/state work, and detach snapshot creation without racing render writes.
- Corrective-2 result: disabled begin/end keep the ledger nil; enabled begin allocates before `stateLock`, end detaches under `stateLock`, and snapshot/filter runs after unlock with no render race.
- Verification: focused `AudioDataPlaneDiagnosticsTests` 28/28 PASS; affected `AudioPipeTests` 4/4 PASS; full `swift test` 417/417 PASS; `swift build -c release` PASS; `git diff --check` PASS.
- Corrective-3 result: AUDIO_START now owns a stable opt-in capture identity even when no HID session exists; pre-session BLE/decode/render observations remain on that capture, and the matching later session can bind it once. Binding is exact-identity and one-shot; wrong or repeated session bindings are rejected. HID-before-AUDIO_START reuses the same bound capture identity.
- Verification: focused `AudioDataPlaneDiagnosticsTests` 31/31 PASS; affected `AudioPipeTests` 4/4 PASS; `VoiceBoundaryOrderingTests` 3/3 PASS; `VoicePressCoordinatorTests` 39/39 PASS; full `swift test` 420/420 PASS; `swift build -c release` PASS; `git diff --check` PASS.
- Product/runtime boundary: UNKNOWN — no installed/runtime capture was performed, so this delivery does not establish runtime underrun behavior or an audio root cause.
- Current next action: reproduce the submission-path lock edge, move only the submission observation into the existing AudioPipe-owned fixed-capacity ledger, run the authorized verification, push the result, and return to independent Web audit. Do not install, release, or run a runtime capture.

## Corrective-4 authorization

- Audit finding to reproduce: FACT — `AudioPipe.schedule()` holds `stateLock` while `VoiceTimingLogger.recordContinuitySubmitted()` acquires the shared diagnostic lock and mutates the central dictionary ledger.
- Authorized result: remove that shared-lock/dynamic-aggregation edge from the submission critical path by recording the same submission timestamp, frame count, queue depth, 100 ms bucket, capture identity, and provisional-session evidence in the existing AudioPipe-owned fixed-capacity ledger, then merge submission and render evidence exactly once after safe detach.
- Preservation boundary: retain corrective-1/2/3 render, lifecycle, default-off, capture identity, late binding, session isolation, ordering, overflow, and `render_capacity_dropped` invariants. Do not redesign production audio, alter voice semantics, or add runtime capture.
- Verification boundary: add RED-first regression coverage for submission bucket/queue evidence, provisional and bound ordering, wrong/stale isolation, same-session submission-plus-render merge, disabled mode, and consecutive sessions; run focused diagnostics, affected AudioPipe/order/lifecycle tests, full Swift tests, release build, and diff check.

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
