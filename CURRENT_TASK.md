# RemoteOrbit Current Task

## RO-AUDIO-CONTINUITY-DIAGNOSTIC-049 — Resolve sustained PCM supply-deficit boundary

Status: `ACTIVE / REMOTE_DIAGNOSTIC_IMPLEMENTATION`
TASK_CLASS: `DIAGNOSTIC / OBSERVABILITY`
Repository: `Lost0rz/RemoteOrbit`
Start control parent: `41156e6989cceebac44e6f04e07083add0b4dbe9`
Control authority: `main`
Authorized implementation branch: `codex/audio-continuity-diagnostic-049`

## Objective

Add the minimum observation-only evidence needed to distinguish the remaining causes of the confirmed audio-continuity failure without changing user-visible voice behavior or audio transport semantics.

The next safe corrective decision depends on distinguishing:

1. sustained/episodic upstream decoded-supply deficit or source-clock mismatch; from
2. local BLE delegate / `handleAudio` service latency large enough to delay notification processing.

## Existing accepted evidence

The 2026-11-03 runtime log and current `main` source establish the following for the inspected sessions:

- decoded PCM duration is materially below elapsed 16 kHz expectation;
- AudioPipe active-remote underrun follows the supply deficit;
- decode rejects and zero-sample decodes are not observed in the affected samples;
- AudioPipe ring overflow drops are zero;
- `remotePrebufferLimit = 8000` samples (500 ms at 16 kHz), so prebuffer capacity itself is not the observed first-syllable limit;
- the current 45 ms playout reserve is startup-only and the repository tests explicitly show that startup reserve does not cure sustained deficit.

ROOT_CAUSE_STATUS: `UNKNOWN`

## Authorized scope

### Probe A — BLE audio-handler latency

Add bounded per-session accounting around the production BLE audio callback/handler path. Emit a session summary sufficient to determine typical and worst service time, including at least:

- sample count;
- p50 / p95 / p99 service duration (or a deterministic equivalent percentile summary);
- maximum service duration;
- counts above 5 ms, 10 ms and 15 ms.

Do not log every packet.

### Probe B — decoded supply-rate windows

Add low-overhead approximately one-second windows on the same stream, reporting enough evidence to distinguish sustained clock-rate deficit from isolated stalls. Each emitted window must include at least:

- window elapsed time;
- decoded sample count;
- effective decoded samples/second;
- notification count;
- maximum notification gap in the window;
- AudioPipe queued-output depth at the start and end of the window when available without changing audio behavior.

The probe must not invent packet-loss counts when the protocol does not expose a physical packet sequence.

### Verification

- add focused deterministic tests for the accounting logic;
- run the relevant focused tests;
- run routine repository CI / full Swift tests as required by the existing workflow;
- perform an exact-diff read-only audit before claiming machine completion.

## Non-goals / forbidden changes

Do **not** change:

- ADPCM decode semantics or ATVV frame size;
- playout reserve value/algorithm;
- prebuffer capacity/behavior;
- resampling ratio or add adaptive clock recovery;
- packet-loss concealment;
- AUDIO_STOP drain or post-release grace;
- keepalive behavior;
- HID/Option gesture lifecycle;
- app/driver packaging or release version;
- installed runtime, CoreAudio, TCC, default audio devices or user configuration.

Do not merge a speculative corrective fix into this task.

## Execution / side-effect authority

The user explicitly authorized direct remote repository handling for this bounded diagnostic change on 2026-11-03.

Authorized repository side effects:

- update this control transition on `main` as one atomic control commit;
- create and push `codex/audio-continuity-diagnostic-049`;
- modify only diagnostic/accounting source and focused tests needed for Probe A/B;
- open/update a Draft PR for review and CI.

No local runtime mutation is authorized or required for the remote implementation phase.

## Acceptance / STOP

Machine implementation is complete only when:

1. Probe A and Probe B are present and observation-only;
2. focused tests pass;
3. routine CI/full Swift test evidence is green for the exact branch head, or any infrastructure-only blocker is reported distinctly;
4. exact diff confirms no product-audio behavior change outside the diagnostic boundary.

Then STOP at:

`WAITING_FOR_FRESH_HARDWARE_CAPTURE`

Final root-cause classification and any corrective audio change require a fresh RC003 capture from the instrumented build and a subsequent governed decision.

DOCUMENT_ALIGNMENT: `TASK_049_ACTIVE`
