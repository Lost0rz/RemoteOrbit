# Task 038-B Audio Continuity Closeout

Date: 2026-10-28

Task: `RO-RUNTIME-RELIABILITY-038`

Slice: `038-B — Audio Continuity Evidence`

PR: `#24 — [038-B] Add opt-in audio continuity correlation evidence`

## Executive summary

038-B did **not** establish a single corrective root cause for the observed voice-continuity weakness.

It did establish a trustworthy evidence path across the runtime audio chain and materially narrow the remaining problem space.

Final root-cause status:

`NARROWED_NOT_ESTABLISHED`

The phase therefore closes as a diagnostic/observability milestone, not as an audio-quality fix.

## What was delivered

The diagnostic chain correlates:

`BLE notification cadence -> decode -> PCM submission -> AudioPipe queue/render -> underrun`

using stable session identity, the existing monotonic clock, and 100 ms buckets.

The capability is opt-in through:

`REMOTE_ORBIT_CONTINUITY_EVIDENCE=1`

Default production behavior remains unchanged when the diagnostic mode is disabled.

Before runtime evidence was trusted, four observer/correlation problems in the probe were corrected:

1. Render-side continuity observation no longer enters the shared central diagnostic lock/dictionary while `AudioPipe.stateLock` is held.
2. Diagnostic lifecycle begin/end no longer scan/reset the full fixed-capacity ledger under the real-time audio state lock.
3. `AUDIO_START` may establish a stable provisional capture identity before the later HID gesture/session exists; the later session binds the exact capture once.
4. PCM submission evidence is recorded in the AudioPipe-owned fixed-capacity ledger instead of calling the shared central logger from `AudioPipe.schedule()` under `stateLock`.

The semantic source/test delivery head is:

`652ea306dc4a22ee3c489b254d87becc6f9a4ed0`

The independent Web CODE_DIFF audit passed at:

`6b5fde0b767933a89b8b7643dabe473e46040df8`

## Runtime provenance

Frozen evidence runtime:

- app: `/Applications/RemoteOrbit.app`
- bundle: `com.lost0rz.RemoteOrbit`
- version/build: `0.2.14 (43)`
- executable SHA-256: `926d5ddf4b8796303ec07fe051b1da36cd539fc045973bb8bb24c0bea9a588fc`
- diagnostic environment: `REMOTE_ORBIT_CONTINUITY_EVIDENCE=1`
- process: PID `21428`
- evidence window: `2026-10-28 19:19:13.941–19:58:44.510 +0800`

Frozen data set:

- 10 usable natural LONG sessions;
- one historical PID-18405 session excluded;
- all usable sessions had exact session joins across timing, BLE/decode, submission/render, and continuity records;
- all usable sessions had `render_capacity_dropped=0`.

## Key findings

### Decoder and overflow

Across the 10 usable sessions:

- decoder rejects: `0`;
- zero-sample decodes: `0`;
- overflow dropped frames: `0`.

Verdict:

- `DECODER_REJECTION_CAUSAL_STATUS = DOWNGRADED`
- `OVERFLOW_CAUSAL_STATUS = DOWNGRADED`

These layers are not supported as primary explanations for the observed active-stream starvation in this evidence set.

### Active vs boundary underrun

Active-stream starvation is real:

- 48 active underrun buckets;
- 4/10 sessions contained strict active-stream underrun;
- 15,808 active unfilled frames were observed.

Startup/prestable starvation was not observed.

Tail/teardown was a separate dominant population:

- approximately 89.2% of all unfilled frames occurred at/after `AUDIO_STOP`.

This is an important classification result: total underrun must not be treated as equivalent to active-speech continuity failure.

### BLE cadence

Active bucket populations:

- underrun buckets: `48`;
- non-underrun controls: `343`;
- total active buckets: `391`.

BLE gap >20 ms:

- underrun: `19/48 = 39.58%`;
- control: `33/343 = 9.62%`;
- risk ratio: `4.11`.

BLE gap >30 ms:

- underrun: `7/48 = 14.58%`;
- control: `6/343 = 1.75%`;
- risk ratio: `8.34`.

Lag analysis:

- lag -2: no consistent upstream relationship;
- lag -1: BLE precedence not consistent;
- lag 0: BLE gap enrichment peaks with underrun;
- lag +1: no repeated downstream relationship.

Verdict:

`BLE_CADENCE_CAUSAL_STATUS = SUPPORTED_AS_RECURRING_CONTRIBUTOR`

This is an association/contributor verdict, not an exclusive root-cause verdict.

### PCM aggregate supply

`submitted < requested`:

- underrun: `33/48 = 68.75%`;
- control: `204/343 = 59.48%`;
- risk ratio: `1.16`.

The enrichment is much weaker than the BLE-gap enrichment and lagged precedence is not consistent.

Verdict:

`PCM_SUPPLY_TO_UNDERRUN_CAUSAL_STATUS = DOWNGRADED_FROM_SUPPORTED`

Aggregate PCM supply deficit alone does not explain the active starvation population.

## Remaining unknown

The largest unresolved technical boundary is event ordering **inside the 100 ms bucket**.

A bucket can contain:

1. render demand while the queue is empty;
2. a resulting underrun;
3. later BLE/decode/PCM arrival;
4. an end-of-bucket aggregate in which submitted frames appear sufficient.

Therefore:

`submitted >= requested`

within the same 100 ms bucket does not prove PCM was available before the render callback that starved.

A future explicitly authorized diagnostic investigation would need to discriminate, at finer temporal resolution:

`BLE packet arrival -> decoded PCM availability -> submission -> instantaneous queue depth -> render callback`

This is the remaining boundary between a late-upstream-arrival explanation and a distinct AudioPipe queue/render scheduling explanation.

## Human/output boundary

038-B did not independently capture:

- target-input-method waveform/audio reception;
- human normal-vs-weak session labels;
- final dictated text omission.

Therefore:

- `NORMAL_VS_WEAK_COMPARISON = UNKNOWN`
- `FINAL_TEXT_OMISSION_STATUS = UNKNOWN`

038-F was not started.

## Final causal classification

- Decoder rejection: `DOWNGRADED`
- Overflow: `DOWNGRADED`
- BLE cadence: `SUPPORTED_AS_RECURRING_CONTRIBUTOR`
- Aggregate PCM supply: `DOWNGRADED_FROM_SUPPORTED`
- Active-stream underrun: `FACT`
- Final text omission: `UNKNOWN`
- Root cause: `NARROWED_NOT_ESTABLISHED`

## Phase lessons

### 1. Probe health and product health are different claims

The first healthy diagnostic session established that the evidence chain itself worked. It simultaneously showed active underrun. A probe can PASS while the product path is unhealthy.

### 2. A failure population needs a control population

Looking only at underrun buckets initially overstated PCM-supply causality. Adding the 343 normal active buckets showed that supply deficit was common even outside underrun buckets, while BLE-gap enrichment was much stronger.

### 3. Boundary populations must be separated

Startup, active stream, tail/teardown, and idle callbacks have different meanings. Tail/teardown accounted for most total unfilled frames and would have distorted any aggregate underrun conclusion.

### 4. Bucket totals do not prove ordering

A 100 ms aggregate can hide an early starvation followed by later supply. Same-bucket sufficiency must not be converted into a claim that AudioPipe had data at the exact render deadline.

### 5. Diagnostic code can create the problem it measures

The initial continuity probe introduced shared-lock/dictionary work on real-time-sensitive paths. Observer-effect auditing was required before runtime conclusions were trustworthy.

### 6. Runtime identity and OS permissions are evidence dependencies

The Bluetooth authorization incident showed that HID health, app display name, LaunchServices registration, and CoreBluetooth authorization are separate facts. Runtime provenance must be explicit.

### 7. A recurring contributor is not a root cause

BLE cadence is now evidence-backed as a recurring contributor. That does not justify arbitrary BLE timing changes or imply that AudioPipe timing is healthy.

## Closeout decision

038-B is considered evidence-complete for its authorized objective.

No production corrective is authorized by this document.

If the continuity problem is reopened, the smallest justified next diagnostic question is the finer-grained ordering between BLE arrival, PCM availability, AudioPipe queue depth, and render demand.

Any such probe or corrective requires a new governance transition.
