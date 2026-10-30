# RemoteOrbit Current Task

## RO-VOICE-PIPELINE-SIMPLIFICATION-042 — Gate D Small Measured Jitter Reserve

Status: `WAITING_FOR_INDEPENDENT_WEB_AUDIT`

Repository: `Lost0rz/RemoteOrbit`

Active branch: `codex/voice-pipeline-simplification-042`

Frozen evidence baseline: `ac3132986197bfee4440bb8f388e3d2e5f478f03`

Accepted semantic heads:

- Gate A: `50b1d9efabe15f04d5479b39af227d0e6f43a4e3`
- Gate B: `ae0bf10874d34ce556b4b73a506b22f6a9a1a412`
- Gate C: `9abdebc21a1e03c79ab0ac960bf2d9902c24b1d5`

## Objective

Continue the accepted single-path voice architecture by adding one small, explicit, measurable playout-start reserve that can absorb short BLE arrival jitter while preserving Gate A/B/C semantics and keeping permanent upstream delivery deficit a separate problem.

The user-facing product contract remains:

```text
VOICE DOWN
→ trigger + remote voice opening
→ BLE/ATVV decode
→ Gate C PCM ring
→ bounded Gate D startup reserve
→ CoreAudio playout

VOICE UP
→ BLE/audio-stop tail completes
→ queued output drains fully
→ same trigger UP
```

## Prior accepted gates

### Gate A — CLOSED / PASS

Single direct voice-session path; no primary SHORT/LONG/DOUBLE/Persistent/Receiver-A-B mode; one captured VoiceInputProfile/trigger owns the complete session; tail release remains downstream of BLE/audio/output drain.

### Gate B — CLOSED / PASS

Long-lived strict-READY ATVV transport on dedicated BLE queue; healthy transport reuse across sessions; stale/reset state rejected; Gate A tail/admission ordering preserved.

### Gate C — CLOSED / PASS

Accepted head: `9abdebc21a1e03c79ab0ac960bf2d9902c24b1d5`.

- preallocated 96,000-frame structural PCM ring;
- direct ring-to-`AudioBufferList` realtime render;
- no producer `stateLock` in CoreAudio callback;
- no dynamic PCM queue growth/compaction in render;
- bounded atomic realtime diagnostics/mailbox;
- explicit underflow/overflow policy;
- normal tail retained, new session/reset clears stale PCM;
- output drain requires actual ring empty;
- no jitter/startup reserve was introduced in Gate C.

Independent Web `CODE_DIFF` audit accepted Gate C source semantics. Installed/hardware/Air natural-use acceptance remains pending and is not implied by this source acceptance.

## Gate D — Small measured jitter reserve — LOCAL IMPLEMENTATION COMPLETE

### Goal

Add the smallest practical startup playout reserve needed to absorb short BLE arrival jitter without hiding or reclassifying permanent upstream delivery deficit.

Gate D is latency/jitter policy only. It must not redesign the Gate C ring, BLE transport, ATVV protocol, trigger/session ownership, or tail shutdown.

### Required model

Per new remote voice stream:

```text
OPENING / remote active
→ PCM begins entering Gate C ring immediately
→ playout waits only until the selected reserve threshold is reached
→ playout starts once
→ after start, render consumes normally at CoreAudio rate
→ no automatic rebuffer/re-arm during the same stream
```

Tail behavior:

```text
remote route inactive / draining
→ reserve gate is permanently bypassed for that stream
→ every queued tail frame remains renderable
→ output drain completes only when actual ring is empty
```

### Candidate reserve values

The authorized evidence range is:

- `0 ms` control;
- `45 ms`;
- `75 ms`;
- `100 ms`.

No Gate D implementation/default above 100 ms is authorized.

The executor must implement the reserve as one explicit, testable configuration/constant seam and compare these candidates with deterministic arrival-pattern tests. A bounded default may be selected only from this set and must be justified by the recorded synthetic/evidence comparison, not by guesswork.

The current project evidence motivating the range is short arrival jitter commonly in the tens of milliseconds, with observed material gaps extending into roughly the 30–80 ms range. This reserve is not expected to repair sustained/missing-delivery deficit.

### Authorized work

1. Add one explicit per-stream playout-start state such as `waitingForReserve → started` around the accepted Gate C consumer path.
2. Convert the selected reserve milliseconds to output frames at the existing 48 kHz output rate.
3. While remote is active and playout has not started, output silence without consuming queued remote PCM until the threshold is reached.
4. Once threshold is reached, start consuming immediately and never re-arm the reserve during that stream.
5. If the stream enters tail/draining before threshold is reached, bypass the threshold and drain all queued PCM; do not strand short utterances.
6. Reset the reserve state only at a truthful new-session/reset boundary.
7. Add truthful diagnostics for configured reserve, actual playout-start queue depth, and reserve wait duration using existing diagnostic authority; do not add a second always-on authority/ring.
8. Keep the selected reserve/default centralized and easily auditable.
9. Preserve the accepted Gate C fixed-capacity ring and realtime constraints.

### Realtime requirements

The CoreAudio callback must remain within Gate C realtime constraints. Gate D reserve checks may use only fixed scalar/atomic state and queue-depth reads. Do not add:

- ordinary blocking locks;
- allocation;
- dynamic collections;
- string/JSON/log formatting;
- file I/O;
- main-thread dispatch/waits.

### Required evidence tests

At minimum provide deterministic tests for:

1. `0 ms` control begins consuming the first available PCM immediately.
2. `45/75/100 ms` candidates do not consume before their threshold and start exactly once when threshold is reached.
3. After playout starts, a later queue dip/underflow does not re-arm or pause into a second reserve cycle.
4. A short utterance released before reserve threshold bypasses the gate during drain and renders all queued tail PCM.
5. Tail/output-drain completion remains based on actual ring empty, not reserve state.
6. New session resets the reserve state; stale previous-session state cannot carry forward.
7. Existing underflow/overflow accounting remains truthful after playout start.
8. Candidate simulation with representative burst/gap patterns records underflow counts/frames and added startup latency for `0/45/75/100 ms` so the chosen default is evidence-backed.
9. Permanent supply deficit test demonstrates the reserve delays but does not falsely claim to repair sustained deficit.
10. Gate A tail, Gate B BLE/READY, Gate C ring/realtime, ATVV, and 041 diagnostic/export regressions remain green.

### Default-selection rule

Select the smallest candidate from `45/75/100 ms` that materially reduces the authorized synthetic short-jitter underflow scenario without requiring rebuffering and without exceeding 100 ms startup latency. Keep `0 ms` as the control path in tests.

If the evidence does not clearly distinguish a smallest useful candidate, do not invent a default. Stop at the audit boundary with the comparison results and report the unresolved selection.

### Gate D executor result

The implementation uses one `AudioPipePlayoutReserve` seam around the accepted
Gate C ring consumer. The candidate thresholds are exactly `0`, `2,160`,
`3,600`, and `4,800` frames at 48 kHz. The selected default is `45 ms` and
`SELECTION_AMBIGUOUS=NO`: in the deterministic short-jitter simulation the
control recorded `3/1,440` active underrun callbacks/frames, while 45/75/100
ms each recorded `0/0`; 45 ms was the smallest positive candidate and 75/100
ms added latency without further reduction. Startup latency/start depth were
`0/480`, `40/4,080`, `40/4,080`, and `60/5,280` ms/frames for
`0/45/75/100 ms`; tail bypass and dropped/stranded PCM were zero for every
candidate.

The sustained-deficit control recorded `6` active underrun callbacks and
`1,440` active underrun frames for every candidate, proving the finite reserve
does not repair permanent supply deficit. Reserve wait is intentional silence:
it consumes no PCM and does not count active underrun, starvation, front-edge,
rendered PCM, or first-render markers. Tail bypass, actual-ring-empty drain,
no-rearm, and new-session reset are covered by focused tests. The existing
diagnostic authority exposes candidate/configured frames, start depth, wait
duration, start reason, and selected default.

### Semantics that must remain unchanged

- Gate A voice key/profile/trigger ownership;
- Gate B BLE queue, strict READY, connection reuse, reconnect/keepalive/discovery/subscription;
- ATVV v0.4/v1.0 commands/framing/capabilities/codec/ADPCM/AUDIO_SYNC/sample-rate selection;
- Gate C ring capacity and overflow policy;
- gain/limiter/resampling;
- remote candidate/prebuffer semantics except the minimum Gate D playout-start gate;
- physical-UP post-release grace and 350 ms AUDIO_STOP drain;
- output-drain and trigger-UP ordering;
- virtual audio driver format/behavior.

### Forbidden in Gate D

Do NOT:

- increase or reinterpret the 96,000-frame structural ring capacity as a jitter target;
- add adaptive/dynamic jitter estimation;
- rebuffer/re-arm after playout has started;
- time-stretch, resample-rate-shift, duplicate, synthesize, or conceal missing PCM;
- claim permanent BLE delivery deficit is fixed by reserve;
- change BLE/ATVV lifecycle or protocol;
- change Gate A/B/C state ownership;
- change Gate E start/tail trigger policy;
- package/install/replace the app, reload CoreAudio, mutate TCC, or change Air runtime;
- merge, tag, release, or mutate historical 039/040/041 branches;
- begin Gate E automatically.

If the implementation appears to require upstream transport changes or adaptive rebuffering, STOP and report the dependency.

## Verification

Run at minimum:

- new Gate D reserve/candidate tests;
- Gate C ring/AudioPipe realtime tests;
- AudioPipe diagnostics/measurement tests;
- VoicePipelineSimplification / VoiceBoundaryOrdering / VoiceTriggerRuntime;
- BLEBridge strict READY / transport tests;
- PostReleaseCaptureGrace;
- ATVV tests;
- relevant 041 continuity/DiagnosticHardening/DiagnosticExporter suites;
- full Swift tests;
- arm64 Release build;
- x86_64 Release build;
- protocol self-tests;
- `git diff --check`.

Final diff must prove no Gate E, BLE/ATVV, driver/runtime/install/TCC, or unrelated product behavior leaked into Gate D.

## Completion / stop state

Gate D implementation and verification are complete:

- update `CURRENT_STATUS.md` and `CURRENT_TASK.md` together;
- commit all authorized Gate D changes;
- push only `codex/voice-pipeline-simplification-042` and verify exact remote identity;
- stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`;
- do not begin Gate E automatically;
- do not merge, tag, release, install, mutate TCC, or change Air runtime.
