# RemoteOrbit Current Task

## RO-DIAGNOSTIC-HARDENING-041 — One-shot Incident Evidence Closure

Status: `AUTHORIZED / READY_FOR_LOCAL_IMPLEMENTATION`

Repository: `Lost0rz/RemoteOrbit`

Active branch: `codex/diagnostic-hardening-041`

## Objective

Perform one final, production-safe diagnostic-hardening pass that closes the remaining known evidence gaps for:

1. voice attempts that disappear before waveform/audio start;
2. user-reported start/mid-stream text omission where the audio/transport layer must be classified without capturing dictated text;
3. BLE cadence versus PCM/render starvation ordering;
4. RemoteOrbit output versus virtual-input/consumer-boundary ambiguity;
5. debug-recording persistence failures.

Completion means a single bounded diagnostic archive from a natural incident can identify the last successful stage and the relevant failure boundary without requiring another round of probe additions.

This task is diagnostics only. It must not change product voice behavior to make incidents disappear.

## Integration prerequisite

041 is based on the audited 039 observability branch at `0db5861f6df2cad0e1c8e8ecd6d8b56c86de49d4`.

Before new 041 code, integrate only the following 040 semantic commits, in this order, resolving conflicts while preserving both 039 observability and 040 semantics:

- `c3b8c74ee933f666bcc9688be9554d9b79416993`
- `9669420ecfd65034ebeb61ade08386dd0ca20659`
- `21255f34c963aff7fe53f97bb64526fb9b000581`

Do not cherry-pick or merge 040 control-plane commits. Re-run the relevant 039 + 040 focused suites immediately after integration before adding new diagnostics.

## Reuse, do not duplicate

The following already exist and must be extended only where a concrete missing fact requires it:

- DiagnosticAuthority / bounded JSONL journal;
- DiagnosticExporter and manifest/checksum archive;
- approved application-log collection, including `.json/.jsonl` in the RemoteOrbit logs directory;
- LongTermIncidentCoordinator;
- FixedCapacityObservationTrace with front/recent/incident windows;
- BLE arrival, decode complete, PCM submitted, render, queue starvation and lifecycle timing points;
- main-queue lag measurement and anomaly triggers;
- raw HID microphone-state / edge diagnostics;
- structured recording lifecycle and recording failure events after 040 integration.

No second diagnostic authority, second high-resolution ring, or duplicate raw-HID logger is authorized.

## Authorized closure package

### A. Unified `voice_attempt_id`

Create one bounded attempt identity at the earliest accepted physical microphone attempt and carry/bind it across the complete start path, including raw HID/edge, mapping, gesture, transport prewarm/connect/readiness, hold confirmation, mic-open request/write, AUDIO_START, AUDIO_FIRST, route/output lifecycle, release, AUDIO_STOP/drain and completion.

If an existing transport/capture generation precedes later gesture/session identity, bind rather than reset it. Preserve the existing first-writer-wins incident generation semantics.

Attempt correlation must not change routing, timing, suppression or gesture behavior.

### B. Stage-aware Voice Start Watchdog

Do not use a naive 250 ms AUDIO_START deadline from raw HID down because LONG classification itself is 300 ms.

Required semantics:

- while the physical microphone key remains down, an early pre-classification check may verify only HID → mapping → gesture/pending → transport-prewarm progress;
- after `HOLD_CONFIRMED` / voice-input activation, arm the actual voice-start watchdog;
- emit a bounded `VOICE_START_STALL` when start progress exceeds the audited normal envelope;
- emit `VOICE_START_FAILURE` if AUDIO_START/AUDIO_FIRST still does not arrive by the hard failure deadline;
- the event/snapshot must report `voice_attempt_id`, last successful stage, elapsed time and bounded scalar state for HID, mapping, gesture, Option gate, BLE/ATVV, mic-open, audio-start/first, AudioPipe/output readiness and queue depth;
- watchdogs diagnose only. They must never retry micOpen, restart BLE/HID, alter timing, or synthesize input.

Thresholds must be justified from existing timing evidence and tests; retain the 300 ms product gesture threshold unchanged.

### C. Low-rate runtime health

Add a bounded structured health snapshot at low cadence (target 30 s while idle) plus immediate state-transition/failure evidence where already safe.

At minimum expose stable scalar health for:

- HID manager running/device active and last report/microphone-transition age;
- mapping enabled/verified;
- gesture and physical voice-key state;
- BLE peripheral/transport/ATVV/mic-open/drain state;
- AudioPipe remote-active/output-ready/queue state;
- diagnostic drop counts.

Do not dump raw reports or verbose payloads in the heartbeat.

### D. Existing high-resolution trace refinement

Extend the existing `FixedCapacityObservationTrace`; do not create another ring.

Add only missing scalar attribution needed to prove ordering, such as stable sequence/stream identity and any missing distinction required to tell BLE arrival → decode → PCM submit → render request/fill/underrun ordering.

Requirements remain:

- preallocated/fixed-capacity storage;
- no JSON encoding, formatting, print, disk I/O, dictionary allocation or blocking diagnostic lock on CoreAudio hot paths;
- detached/off-path serialization only;
- dropped/overwritten evidence visible.

### E. Underrun episodes and lifecycle attribution

Build bounded underrun episodes from the existing render evidence rather than relying only on cumulative totals.

Each episode should preserve, where available:

- begin/end and duration;
- missing frames;
- queue depth before/minimum;
- time since previous BLE arrival and PCM submit;
- next BLE/PCM arrival after the episode;
- lifecycle phase: startup, active, post-stop/tail, idle or local microphone.

Session summary must distinguish active/mid-stream underrun from startup and post-stop drain so tail activity cannot inflate active-failure conclusions.

### F. Output / consumer boundary

Record the safest available read-only boundary facts:

- first/last nonzero RemoteOrbit output timing;
- output device identity/readiness;
- selected system input UID/identity at relevant start/failure snapshots.

A driver-level consumer/read callback probe is authorized only if an existing read-only seam can expose it without changing driver/audio semantics or introducing real-time risk. If that cannot be proven, do not modify the driver; record consumer evidence as `unavailable` and preserve the boundary as UNKNOWN.

### G. Diagnostic archive completeness

Do not redesign `DiagnosticExporter`. Verify and harden the existing archive so one export explicitly receipts the presence/status/bounding of the evidence required by this task, including:

- `RemoteOrbit.log`;
- `voice-diagnostic-current.jsonl`;
- DiagnosticAuthority journal/session events;
- frozen high-resolution incident trace / session summaries;
- runtime app/build/source/process identity;
- diagnostic environment flags;
- Input Monitoring and Accessibility permission state;
- RemoteOrbit virtual-mic identity/readiness;
- selected system input identity when safely available;
- receiver evidence;
- manifest plus SHA-256 checksums.

If a source is unavailable, the manifest must say so explicitly rather than silently omit it. Existing bounded-size and recency-retention policy remains authoritative.

### H. Failure classification summaries

Add bounded structured incident summaries sufficient to classify at least:

- start-path failure (`VOICE_START_FAILURE`);
- audio-continuity failure/anomaly (`AUDIO_CONTINUITY_FAILURE` or equivalent stable contract);
- output-boundary failure/anomaly (`OUTPUT_CONSUMER_FAILURE` or equivalent), while allowing `consumer evidence unavailable` instead of inventing proof.

The classification names may follow repository conventions, but they must map to the evidence layer and never promote UNKNOWN to FACT.

### I. Diagnostic noise / observer-effect hardening

Reduce obvious diagnostic noise without changing product behavior:

- idle audio-meter logging should be low-rate (target ~30 s), active voice may remain around 1 s, and material state changes/failures remain immediate;
- normal `VoiceDiagnosticLogger` persistence may use bounded batching/periodic flush only if crash durability is preserved with immediate flush at incident/failure, session completion and app shutdown boundaries;
- do not weaken the DiagnosticAuthority durability contract merely to reduce writes.

Any change here requires observer-effect/regression tests and must remain diagnostics-only.

## Privacy and evidence boundary

- No dictated-text capture.
- No raw IME text/value harvesting.
- No automatic audio recording enablement or recording export.
- No automatic upload.
- No unbounded raw HID/audio payload persistence.
- Diagnostic archives may identify process/device/runtime state, but must not include secrets or unnecessary user content.

Because dictated text is intentionally not captured, a diagnostic archive can prove or exclude transport/audio/output defects for a user-reported omission, but it must not claim that the final text itself was missing unless separately supplied by the user. Preserve that distinction explicitly.

## Forbidden product corrections

Do not, in this task:

- enlarge BLE/audio buffers as a fix;
- change decoder/ADPCM semantics;
- change codec/sample rate/gain;
- change AudioPipe queue size/playout policy;
- retry micOpen automatically;
- restart BLE/HID automatically;
- change the 300 ms gesture threshold or post-release timing;
- change Option/Control gate behavior;
- change persistent SHORT/LONG semantics;
- change input-method behavior;
- make debug recording default-on.

If implementation appears to require one of these changes, STOP and report the evidence gap instead.

## Verification gates

At minimum:

1. 040 semantic integration passes focused tests before new work;
2. attempt correlation covers normal start, pre-gesture/prewarm ordering, failure and next-attempt reset;
3. watchdog tests prove no false AUDIO_START failure before LONG classification and no retry/restart side effects;
4. health snapshot cadence/state-change behavior is bounded;
5. high-resolution trace remains allocation/I/O-free at the hot-path boundary and preserves ordering/drop visibility;
6. underrun episode tests prove startup/active/tail separation;
7. output-boundary tests distinguish known output state from unavailable consumer evidence;
8. exporter test proves every required evidence source is present or explicitly receipted unavailable/bounded;
9. privacy tests prove no dictated text/audio payload/raw filesystem path leaks into structured diagnostic events;
10. diagnostic noise/flush tests preserve incident durability;
11. full Swift tests pass;
12. release build, x86 build where required by the established candidate flow, protocol self-tests and `git diff --check` pass;
13. observer-effect review confirms no new hot-path disk/JSON/formatting/blocking diagnostic work;
14. package a new owner-validation candidate only after independent Web audit; do not install it in this implementation task.

## Completion / stop state

Local implementation stops at:

`WAITING_FOR_INDEPENDENT_WEB_AUDIT`

No merge, tag, public release, Air install, driver install, TCC change, or automatic runtime mutation is authorized.

After independent audit passes, a separate packaging/install gate may create one unified observation candidate. The intended end state is that no further always-on probe expansion occurs unless a fresh natural incident demonstrates a concrete missing evidence boundary.
