# Task 043 Receiver Readiness Stability Corrective

Date: 2026-10-31
Task: `RO-IME-READINESS-PROMPT-SYNC-043`
Status: `DESIGN_ACCEPTED / IMPLEMENTATION_AUTHORIZED`

## Incident basis

The merged 0.2.15 runtime exposed a severe memory/CPU regression in the Task 043 receiver-readiness observer. Frozen host evidence from PID 14011 established:

- physical footprint about 6.0 GB;
- default malloc zone about 6.4 GB with about 127.55 million allocations;
- `Malloc Small` about 5.2 GB and `Malloc Large` about 0.8 GB;
- 5-second sample: the `voice-receiver-readiness` queue was active in 1848/1848 samples;
- 877 samples were inside `AudioObjectAddPropertyListenerBlock` from `installProcessListeners`;
- 816 samples were inside `AudioObjectRemovePropertyListenerBlock` from `removeProcessListeners`;
- Core Audio's `HALC_ShellObject_Listener Queue` was also active in 1848/1848 samples, dominated by `PropertiesChanged` / `HasListener`;
- CPU stayed roughly 100-170% during the capture and the app became unresponsive.

This establishes a listener-refresh/callback-amplification failure in `VoiceReceiverReadinessObserver`. The icon, log volume, and AudioPipe buffering are not supported as the source of the 6 GB growth.

Apple's Core Audio contract is material here: `AudioObjectAddPropertyListenerBlock` copies and retains the listener block and retains the dispatch queue until a matching remove call succeeds. A design that repeatedly rebuilds a large listener graph on property notifications therefore has unnecessary lifetime and amplification risk.

## Design question

How should RemoteOrbit obtain sufficiently fresh external-receiver readiness for the HUD while remaining safe as a long-lived background process?

## Selected architecture

Replace the persistent Core Audio process-listener graph with a **session-scoped snapshot sampler**.

Readiness is advisory UI truth, not transport or admission authority. RemoteOrbit therefore does not need permanent process-level listeners while idle.

### Ownership

`AppController`
- owns whether readiness sampling is active based on the existing voice state;
- does not use readiness to admit/reject/delay voice input.

`VoiceReceiverReadinessMonitor`
- owns one private serial queue;
- owns at most one `DispatchSourceTimer` while relevant voice states are active;
- publishes readiness state changes;
- contains no Core Audio property-listener registrations.

`CoreAudioVoiceReceiverProbe`
- performs one synchronous, read-only snapshot query;
- has no timers, callbacks, retained process objects, or listener lifecycle;
- can be replaced by a deterministic fake in tests.

`VoiceHUDProjection`
- remains presentation-only and retains the accepted semantics: local audio without confirmed receiver is non-green; only a fresh positive receiver sample is green.

## Lifecycle

Sampling is active only while receiver truth can affect the current HUD:

- activate on `.opening`, `.pending`, `.holding`, `.streaming`;
- deactivate on `.draining` and `.idle`.

Activation:

1. increment a generation token;
2. perform one immediate sample;
3. start one timer on the monitor queue;
4. sample at a nominal 100 ms cadence with reasonable timer leeway.

Deactivation:

1. increment the generation token so stale work cannot publish;
2. cancel and nil the timer;
3. clear cached target-device identity if required by implementation safety;
4. publish a conservative non-listening state for the inactive monitor.

There must never be more than one live timer and one executing sample. The timer handler samples directly on the monitor's serial queue; it must not enqueue another refresh back onto the same queue. If defensive single-flight state is used, excess ticks coalesce into at most one future sample rather than an unbounded queue.

## Snapshot algorithm

The probe uses only synchronous `AudioObjectGetPropertyData*` reads.

Per sample:

1. resolve/cache `RemoteOrbit Mic 2ch` device ID for the active generation;
2. read `kAudioHardwarePropertyProcessObjectList`;
3. for each process object:
   - read PID;
   - skip RemoteOrbit's own PID immediately;
   - read `kAudioProcessPropertyIsRunningInput`;
   - if false, skip device membership reads;
   - if true, read input-scoped `kAudioProcessPropertyDevices`;
   - only if the target device is present, optionally read bundle ID and return `.listening`;
4. if no fully-read process positively matches, return `.inactive`.

Failure semantics are fail-closed:

- top-level process-list/device-resolution failure -> `.unsupported` / non-green;
- an individual process object disappearing or becoming unreadable during enumeration -> skip that object for the current tick; it may create a one-tick false negative but never a false green;
- target-device membership read failure for a candidate -> that candidate does not count as listening;
- bundle ID failure does not invalidate a positive match because bundle ID is diagnostic metadata, not truth authority.

## Explicit structural invariants

The production readiness path must satisfy all of these:

- zero calls to `AudioObjectAddPropertyListenerBlock`;
- zero calls to `AudioObjectRemovePropertyListenerBlock`;
- zero permanent Core Audio process listeners;
- idle timer count = 0;
- active timer count <= 1;
- outstanding readiness sample count <= 1;
- no callback can recursively schedule a graph rebuild;
- no unbounded arrays, dictionaries, work-item queues, or retained process snapshots;
- readiness cannot modify BLE, AudioPipe, HID ownership, trigger timing, cooldown/retry behavior, or Task 042 transport semantics.

## Why not retain an incremental persistent listener registry

A correctly diffed listener registry could avoid the specific full-rebuild storm, but it still creates permanent lifetime coupling to dynamic Core Audio process objects and requires exact add/remove pairing for every process and property. That complexity is unnecessary because readiness only matters during a short user interaction and does not control audio transport.

Session-scoped snapshot sampling has a smaller failure surface:

- no listener lifetime to reconcile;
- no callback amplification path;
- no idle Core Audio background work;
- bounded staleness (nominally <= one sample interval);
- deterministic fail-closed behavior;
- simpler stress testing and resource accounting.

The earlier Task 043 prohibition against polling is superseded by this design. That prohibition applied to an unproven timer workaround. The current design is an evidence-driven replacement of the faulty long-lived listener architecture and is explicitly bounded to active HUD sessions.

## Verification requirements

### Deterministic source tests

Add tests for:

- active lifecycle creates at most one timer;
- repeated activate calls are idempotent;
- deactivate cancels sampling and stale generations cannot publish;
- 100,000 synthetic timer ticks / lifecycle operations do not create queued work proportional to tick count;
- self PID is excluded;
- inactive processes avoid device-membership reads;
- positive match requires running input plus target device;
- per-object read failure fails closed without poisoning later ticks;
- top-level query failure becomes non-green;
- HUD semantics remain unchanged.

Add a source guard/test proving the readiness implementation contains no Core Audio property-listener registration/removal path.

### Regression verification

Preserve and rerun:

- Task 043 readiness/HUD tests;
- Task 042 voice pipeline/BLE/AudioPipe regression suites;
- full Swift tests;
- arm64 and x86_64 Release builds;
- protocol self-tests;
- `git diff --check`.

### Runtime soak after independent source audit

A new App candidate must not be considered accepted until host soak proves bounded behavior.

Required runtime checks after a clean restart:

1. idle period: readiness sampler stopped, no readiness queue CPU activity, RSS reaches a plateau rather than monotonic growth;
2. repeated normal voice interactions: green readiness still follows real external input consumption;
3. rapid/repeated interactions including the already-accepted IME post-processing edge;
4. memory sampling throughout the run;
5. start/end `vmmap -summary` and a short `/usr/bin/sample` capture.

Acceptance characteristics:

- no `AudioObjectAddPropertyListenerBlock` / `AudioObjectRemovePropertyListenerBlock` readiness stack activity;
- readiness queue is idle outside active voice interactions;
- no sustained high CPU from readiness observation;
- no monotonic multi-hundred-MB/GB memory growth;
- post-warmup RSS remains bounded (end-of-soak should remain within a conservative tens-of-MB band of the stabilized baseline, not scale with interaction count);
- Task 042 behavior remains unchanged.

## Non-goals

Do not use this corrective to:

- solve the accepted rapid-double-press / Doubao post-processing limitation;
- add cooldown/retry/replay;
- gate or delay voice admission on receiver readiness;
- alter BLEBridge, AudioPipe, ATVV, HID ownership, driver, TCC, or CoreAudio configuration;
- add a permanent memory watchdog as a substitute for fixing ownership;
- publish/tag/release before source audit and runtime soak complete.

## Consequences

Receiver-green indication may lag the true external receiver by up to roughly one sampling interval. This is acceptable because the state is advisory UI feedback and the design prioritizes bounded long-term resource behavior over sub-frame notification latency.

## Reversibility

The monitor/probe split keeps the Core Audio snapshot logic isolated. A future event-driven implementation can replace the monitor only if it proves a strictly bounded listener lifecycle and passes the same soak/resource invariants.

TASK_RECONCILIATION_REQUIRED: YES
REASON: The previous active task explicitly forbade new receiver behavior/polling; the established runtime regression requires replacing the listener architecture with session-scoped sampling under the same Task 043 corrective purpose.
