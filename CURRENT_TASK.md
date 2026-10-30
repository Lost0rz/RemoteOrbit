# RemoteOrbit Current Task

## RO-VOICE-PIPELINE-SIMPLIFICATION-042 — Gate E End-to-End Voice Boundary Hardening

Status: `READY_FOR_LOCAL_GATE_E`

Repository: `Lost0rz/RemoteOrbit`

Active branch: `codex/voice-pipeline-simplification-042`

Frozen evidence baseline: `ac3132986197bfee4440bb8f388e3d2e5f478f03`

Accepted semantic heads:

- Gate A: `50b1d9efabe15f04d5479b39af227d0e6f43a4e3`
- Gate B: `ae0bf10874d34ce556b4b73a506b22f6a9a1a412`
- Gate C: `9abdebc21a1e03c79ab0ac960bf2d9902c24b1d5`
- Gate D: `9cdbf6f5190d9ed453d7f15cf2e8192973cc62ad`

## Objective

Close the remaining source-level start/end boundary risks in the accepted single-path voice architecture without redesigning Gate A-D.

Gate E is the final source construction gate for 042. It owns end-to-end ordering, failure-safe retirement, and truthful boundary evidence only.

## Accepted product contract

```text
VOICE DOWN
→ capture one VoiceInputProfile / trigger identity
→ receiver trigger DOWN is not gated on PCM or reserve
→ request the remote voice stream through strict READY ATVV transport
→ AUDIO_START / decode / PCM submission
→ Gate D reserve waits up to the accepted fixed startup threshold
→ actual PCM playout

VOICE UP
→ session enters DRAINING
→ existing BLE post-release / AUDIO_STOP retirement completes
→ remote route becomes inactive
→ Gate D reserve bypasses if the stream is still waiting
→ Gate C ring renders every queued tail frame
→ actual ring empty / output drain completion
→ release the same captured trigger
→ IDLE
```

## Prior gates — CLOSED / PASS

### Gate A

- direct voice-key session path;
- no production SHORT/LONG/DOUBLE/Persistent/Receiver-A-B mode;
- one captured VoiceInputProfile/trigger owns DOWN through UP;
- trigger UP remains downstream of audio/output retirement.

### Gate B

- long-lived strict-READY ATVV transport;
- dedicated BLE serial ownership queue;
- healthy READY reuse;
- stale/reset transport facts rejected;
- existing post-release and AUDIO_STOP retirement preserved.

### Gate C

- 96,000-frame preallocated PCM ring;
- realtime CoreAudio consumer with no producer `stateLock`;
- bounded overflow/underflow evidence;
- actual-ring-empty output drain;
- normal tail retained, new-session reset clears stale PCM.

### Gate D

Accepted head: `9cdbf6f5190d9ed453d7f15cf2e8192973cc62ad`.

- fixed one-shot startup reserve;
- default `45 ms / 2,160 frames` at 48 kHz;
- reserve silence is intentional and excluded from underrun/first-render evidence;
- no rebuffer/re-arm after STARTED;
- queued short-tail bypasses reserve and remains drainable;
- activation publication order is reset-before-realtime-active;
- decision/reset lifecycle gate prevents stale render decisions from publishing after new-session reset;
- realtime decision path never waits/spins/locks.

Installed/hardware/Air natural-use acceptance is still pending and is not implied by the source audits above.

## Gate E — AUTHORIZED

### 1. Start boundary

The production primary voice path must not reintroduce any classifier or first-PCM gate.

For a normal strict-READY transport, physical VOICE DOWN must initiate the same session's trigger/voice opening immediately through the existing Gate A/B ownership path.

Required properties:

- no 300 ms or equivalent gesture hold delay;
- no wait for `AUDIO_START`, first decode, first PCM submission, reserve threshold, or first render before the receiver trigger DOWN becomes owned/emitted;
- `MIC_OPEN` remains per-session and uses Gate B strict READY;
- trigger identity is captured once and remains stable until final UP;
- Gate D's 45 ms reserve delays playout only; it must not delay trigger ownership or `MIC_OPEN` eligibility;
- diagnostics distinguish physical DOWN, trigger DOWN request/emission, MIC_OPEN request, AUDIO_START, first decoded/submitted PCM, reserve start, and first actual render without inventing causal claims.

Do not add a new artificial start delay to make ordering easier.

### 2. End boundary

Physical VOICE UP must begin retirement but must never release the captured trigger before all accepted downstream tail work is complete.

Required ordering:

```text
PHYSICAL UP
→ DRAINING
→ existing BLE stop/post-release/AUDIO_STOP retirement
→ transport stream retirement observed
→ remote AudioPipe route inactive
→ queued tail remains renderable
→ reserve tail-bypass if threshold was never reached
→ actual Gate C ring empty
→ output drain completion
→ captured trigger UP request/emission
→ session IDLE
```

No fixed sleep may replace actual ring-empty drain ownership.

Existing bounded BLE safety/grace mechanisms may remain unchanged unless a focused Gate E test proves a source-order defect. Do not tune their durations merely as cleanup.

### 3. Failure-safe retirement

Cover the lifecycle cases that can otherwise leave a trigger/session stuck:

- physical UP before `AUDIO_START`;
- stream opens but no PCM arrives;
- disconnect/transport loss during OPENING;
- disconnect/transport loss during STREAMING;
- transport stops while reserve still WAITING;
- explicit failed/opening session cleanup;
- app-side output route unavailable/failure where existing seams permit deterministic coverage.

The exact failure path may differ from normal drain, but it must end deterministically with one trigger release at most, no stuck DOWN ownership, no stale profile/trigger/session state, and no PCM from the failed session leaking into a later session.

Do not fabricate missing remote audio during failure cleanup.

### 4. Rapid consecutive sessions

A later VOICE DOWN must not cross ownership with the prior session's BLE/output drain.

Required:

- prior trigger UP belongs only to prior captured trigger/profile;
- next session cannot inherit prior reserve/ring/diagnostic state;
- a press arriving before prior retirement follows the existing deterministic admission/defer/reject contract;
- once prior retirement is complete, the next session can start normally on the retained Gate B READY transport.

Do not add a second persistent queue of arbitrary future voice presses.

### 5. Boundary evidence

Preserve the existing 041 diagnostic authority and adapt only what is necessary to prove current architecture truthfully.

At minimum keep/verify ordered evidence for:

```text
PHYSICAL_DOWN
TRIGGER_DOWN_REQUESTED / EMITTED (or truthful existing equivalents)
MIC_OPEN_REQUEST
AUDIO_START
FIRST_DECODED_PCM
FIRST_SUBMITTED_PCM
RESERVE_START / TAIL_BYPASS
FIRST_ACTUAL_RENDERED_PCM
PHYSICAL_UP
AUDIO_STOP / transport retirement
QUEUE_EMPTY
DRAIN_FINISH
TRIGGER_UP_REQUESTED / EMITTED
```

Do not treat Gate D reserve silence as rendered PCM or underrun.
Do not add a second diagnostic authority/ring.

### 6. Preserve accepted architecture

Gate E must not change unless a source-order defect makes a minimal adaptation strictly necessary:

- Gate A VoiceInputProfile/menu semantics;
- primary direct voice-key contract;
- Gate B dedicated BLE queue;
- strict READY facts/evaluator;
- healthy transport reuse/reconnect/discovery/notify/capability semantics;
- ATVV command/framing/version/codec/ADPCM/AUDIO_SYNC/sample-rate behavior;
- Gate C 96,000-frame ring/capacity/overflow policy;
- CoreAudio realtime constraints;
- gain/limiter/resampler;
- Gate D candidate set/default 45 ms;
- Gate D no-rearm policy;
- existing post-release grace / AUDIO_STOP tail retirement;
- virtual driver format/behavior.

## Forbidden in Gate E

Do NOT:

- restore SHORT/LONG/Persistent/Receiver-A-B voice modes;
- gate trigger DOWN on first PCM/render;
- add adaptive jitter/rebuffering;
- alter the 45 ms reserve without new explicit authority;
- add PLC/time-stretch/sample duplication/rate shifting;
- change BLE/ATVV protocol or transport architecture for speculative cleanup;
- increase/reinterpret Gate C ring capacity;
- redesign driver/runtime/install/TCC;
- package/install/replace the app or mutate Air runtime;
- merge/tag/release;
- mutate historical 039/040/041 branches;
- create Gate F automatically.

If a real blocker requires a material Gate A-D redesign, STOP and report the dependency rather than expanding Gate E.

## Required verification

### Start tests

1. physical DOWN enters the direct opening path with no classifier delay;
2. trigger DOWN is not gated on AUDIO_START/PCM/reserve/first render;
3. strict READY allows per-session MIC_OPEN without reconnect/discovery on healthy reuse;
4. Gate D reserve still starts only playout, not trigger/MIC ownership;
5. one captured trigger/profile remains stable through the session.

### End tests

6. physical UP enters DRAINING and does not emit trigger UP immediately;
7. transport retirement precedes route deactivation/output drain;
8. short utterance below reserve threshold tail-bypasses and fully drains;
9. queued PCM after route deactivation remains renderable;
10. trigger UP happens only after actual ring empty/output drain;
11. trigger UP emits at most once.

### Failure tests

12. UP before AUDIO_START retires safely;
13. no-PCM opening retires safely;
14. transport loss during OPENING releases ownership deterministically;
15. transport loss during STREAMING retires without stale session ownership;
16. failed session cannot leak reserve/ring/profile/trigger state into the next session.

### Rapid-session tests

17. next press cannot cross the prior output-drain ownership barrier;
18. after retirement, a next session starts cleanly using healthy READY reuse;
19. delayed old callbacks cannot release or mutate the new session.

### Diagnostics/regressions

20. boundary event ordering remains truthful;
21. reserve silence remains excluded from first-render/underrun;
22. Gate A tail tests pass;
23. Gate B strict READY/transport tests pass;
24. Gate C realtime/ring/drain tests pass;
25. Gate D reserve/lifecycle tests pass;
26. ATVV protocol tests pass;
27. 041 continuity/DiagnosticHardening/DiagnosticExporter tests remain truthful;
28. full Swift tests pass;
29. arm64 Release build passes;
30. x86_64 Release build passes;
31. protocol self-tests pass;
32. `git diff --check` passes.

## Completion / stop state

After Gate E implementation and verification:

- update `CURRENT_STATUS.md` and `CURRENT_TASK.md` together;
- commit only authorized Gate E work;
- push only `codex/voice-pipeline-simplification-042` and verify exact local/remote identity;
- stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`;
- do not merge/tag/release/package/install/mutate TCC/change Air runtime;
- do not create or begin another gate automatically.
