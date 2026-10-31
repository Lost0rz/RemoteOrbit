# RemoteOrbit Current Task

## RO-IME-READINESS-PROMPT-SYNC-043 — Receiver Readiness Stability Corrective

Status: `MEMORY_STABILITY_CORRECTIVE_AUTHORIZED`

Repository: `Lost0rz/RemoteOrbit`
Control authority: `main`
Implementation branch: `codex/ime-readiness-stability-043`
Merged product baseline: `8b76ee336d36e9dd58d072bd5ab1dae208b3a77f`
Control parent before this reconciliation: `5144678bb529a2128e53f4eb285d752cdf45473a`
Corrective design authority: `docs/design/2026-10-31-043-receiver-readiness-stability-corrective.md`

## Objective

Replace the faulty persistent Core Audio process-listener readiness observer with a bounded, long-lived-safe receiver-readiness architecture while preserving all accepted Task 042 voice behavior and the accepted Task 043 HUD semantics.

This remains Task 043. It is a corrective to the same receiver-readiness feature, not a successor task.

## Established incident

Human runtime acceptance is blocked by the 0.2.15 candidate's memory/CPU failure. PID 14011 evidence established a listener-refresh/callback-amplification storm:

- about 6.0 GB physical footprint;
- about 127.55 million allocations in the default malloc zone;
- readiness queue continuously active in the sample window;
- dominant stacks repeatedly removing and adding Core Audio property-listener blocks;
- simultaneous Core Audio HAL property/listener saturation;
- high CPU and eventual app/input unresponsiveness.

The current full listener-graph rebuild on process property callbacks is not acceptable for a permanent background service.

## Required architecture

Implement the corrective design exactly at the ownership level, not as a throttle around the old listener graph.

### 1. Remove the production readiness listener graph

The Task 043 readiness implementation must contain no production calls to:

- `AudioObjectAddPropertyListenerBlock`;
- `AudioObjectRemovePropertyListenerBlock`.

Delete the system-process listener lifecycle, per-process listener registrations, listener-registration arrays/dictionaries, and callback-driven `refreshProcessObjects()` graph rebuild path from the readiness component.

Do not leave the old listener model dormant behind a flag.

### 2. Split monitor lifecycle from Core Audio snapshot reads

Use a small testable separation equivalent to:

- `CoreAudioVoiceReceiverProbe`: one synchronous read-only readiness sample;
- `VoiceReceiverReadinessMonitor`: lifecycle/timer/state publication.

Exact names may vary if existing naming is clearer, but ownership must remain separated enough to unit-test scheduling without live Core Audio.

### 3. Session-scoped bounded sampling

Sampling is active only when the current voice/HUD state can use receiver truth:

- active: `.opening`, `.pending`, `.holding`, `.streaming`;
- inactive: `.draining`, `.idle`.

On activation:

- start a new generation;
- sample immediately;
- maintain at most one `DispatchSourceTimer` on one private serial queue;
- nominal interval: 100 ms, with reasonable timer leeway.

On deactivation:

- invalidate the generation;
- cancel/nil the timer;
- ensure stale work cannot publish;
- leave a conservative non-listening state.

The timer handler must execute the sample directly on the monitor queue. It must not recursively enqueue another refresh to the same queue. No event can create an unbounded work-item backlog.

### 4. Probe algorithm

Each sample is read-only and synchronous:

1. resolve/cache `RemoteOrbit Mic 2ch` for the active generation;
2. read `kAudioHardwarePropertyProcessObjectList`;
3. per process object, read PID and skip the RemoteOrbit PID immediately;
4. read `kAudioProcessPropertyIsRunningInput`;
5. only for running-input processes, read input-scoped `kAudioProcessPropertyDevices`;
6. only for a positive target-device match, read bundle ID if desired for diagnostics;
7. publish `.listening` only from a fully positive sample.

Fail closed:

- top-level process-list/device-resolution failure -> `.unsupported` / non-green;
- individual object disappears/read fails -> skip it for this tick;
- candidate device-membership read fails -> candidate does not count as listening;
- bundle ID is optional metadata and must not decide readiness truth.

### 5. HUD semantics stay frozen

Preserve the accepted projection:

- opening/pending -> `等待输入法` / non-green;
- local audio ready without confirmed external receiver -> `音频已就绪` / non-green;
- fresh external receiver match -> `正在语音中` / green;
- draining -> existing draining/pending presentation.

Receiver readiness remains advisory. It must not admit, reject, delay, retry, replay, or otherwise control the voice path.

## Resource invariants

Production code and tests must establish:

- Core Audio property listener count in readiness path = 0;
- idle readiness timer count = 0;
- active timer count <= 1;
- concurrently executing readiness samples <= 1;
- queued deferred readiness refreshes <= 1 (prefer 0; timer-source coalescing/direct execution);
- no retained per-process snapshots between ticks;
- no unbounded listener/work-item/dictionary growth tied to interaction count.

## Required tests

Add deterministic seams/fakes and prove at minimum:

1. activation performs immediate sample and creates at most one timer;
2. repeated activation is idempotent;
3. deactivate cancels sampling;
4. stale generation cannot publish after deactivate/reactivate;
5. large synthetic tick/lifecycle stress (target at least 100,000 operations) leaves bounded scheduler state rather than N queued work items;
6. own PID excluded;
7. `runningInput == false` avoids device-membership read;
8. positive listening requires target input device membership;
9. per-object read failures are fail-closed and later ticks recover;
10. top-level query failure is non-green;
11. HUD projection semantics remain unchanged;
12. source guard proves no readiness path references `AudioObjectAddPropertyListenerBlock` or `AudioObjectRemovePropertyListenerBlock`.

## Regression verification

Run current Task 043 focused tests and the Task 042 regression suites, then:

- full Swift tests;
- arm64 Release;
- x86_64 Release;
- protocol self-tests;
- `git diff --check`.

Explicitly confirm no product diff in:

- `BLEBridge.swift`;
- `AudioPipe.swift`;
- ATVV;
- HID ownership/timing;
- Task 042 pending-repress/transport ownership;
- driver/TCC/CoreAudio configuration.

`main.swift` may change only to activate/deactivate the readiness monitor from existing voice-state ownership and to remove the always-on listener observer lifecycle.

## Runtime verification sequencing

This implementation card stops after source/regression verification and remote delivery at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`.

Do not package/install a new candidate before independent Web source audit.

After that audit passes, a separate runtime card will require a clean restart and memory/CPU soak proving:

- zero readiness add/remove-listener stacks;
- readiness queue idle outside active voice interaction;
- no sustained readiness CPU saturation;
- no monotonic memory growth with interaction count;
- post-warmup RSS remains within a conservative tens-of-MB band rather than scaling toward hundreds of MB/GB;
- actual Doubao listening still turns the HUD green and stop returns it non-green.

## Accepted limitation unchanged

Do not attempt to fix the accepted rapid-double-press edge while the prior Doubao session is still post-processing. No cooldown/retry/replay/state-machine change is authorized for that behavior.

## Boundaries

Not authorized:

- incremental/persistent Core Audio process-listener registry as an alternative implementation;
- throttling/debouncing the old listener graph and calling it fixed;
- background readiness polling while voice/HUD is inactive;
- receiver readiness as voice admission/timing authority;
- BLEBridge/AudioPipe/ATVV/HID corrective changes;
- driver reinstall/reload, TCC reset, CoreAudio restart;
- tag/release/DMG publication;
- permanent memory watchdog as a substitute for bounded ownership.

## Delivery

Use one clean worktree/branch for `codex/ime-readiness-stability-043` from the reconciled main control head. Preserve any unique local work.

If implementation and verification succeed:

1. update `CURRENT_STATUS.md` and `CURRENT_TASK.md` together on the corrective branch;
2. commit and push the existing corrective branch;
3. verify local/remote equality and clean worktree;
4. stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`.

Do not merge to `main` yet.
