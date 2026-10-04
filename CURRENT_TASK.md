# RemoteOrbit Current Task

## Task identity

- **Task:** INCIDENT MODE — MINIMUM BOUNDARY PROBE DELTA
- **Incident family:** PERSISTENT-LONG / EXTERNAL-IME PREMATURE SESSION STOP
- **Phase:** Step 6 — sealed capture causal review
- **Status:** ONE_BOUNDED_FRESH_CAPTURE_COMPLETED_NOT_REPRODUCED — WAITING_FOR_SEALED_CAPTURE_CAUSAL_REVIEW
- **Task authority:** this file
- **Product behavior changes:** FROZEN
- **Root cause:** UNKNOWN
- **Construction Gate:** BLOCKED
- **Prior Fresh Incident Gate:** PASS
- **Bounded Probe Capture:** CONSUMED (1/1; NOT_REPRODUCED)
- **Second capture authorization:** NO

## User authorization

The user explicitly authorized this transition on 2026-10-03 after the first
fresh incident was captured and sealed.

The user requires:

1. perform a diagnostic-gap audit before construction;
2. map the key state machines;
3. map cross-process and system boundaries;
4. inventory existing probes and missing probes;
5. prioritize cross-process / boundary observation points;
6. do not expand internal log volume merely because more logging is possible;
7. establish a repeatable diagnostic flow before any fix is considered.

## Authoritative fresh incident

Incident:

`fresh-incident-20261003T225236+0800-afudfY`

Runtime source marker:

`01eeddaecd0dff596b7e0fd31cd4b1862360bc9f`

Running executable SHA-256:

`df27b16ff41dcc35191c4699700cbbe522bfd576cbfba7c376712821c58388c2`

Target gesture:

`3F288F28-81AD-4CC3-96EA-E4B9665D2198`

Fresh Incident Gate is PASS. PRE_GATE_LEAK_HYPOTHESIS is INCONCLUSIVE.
ROOT CAUSE remains UNKNOWN.

## Detailed audit reference

Read:

`docs/incident-diagnostics/PERSISTENT_LONG_DIAGNOSTIC_ARCHITECTURE.md`

This reference contains the frozen remote state-machine map, boundary map, probe
inventory, probe priorities, and diagnostic decision flow.

It is evidence/design reference, not task authority. This file and
`CURRENT_STATUS.md` remain authoritative for mutable scope.

## Single objective

Implement and validate the **minimum boundary-observation delta** required to make
the next incident causally discriminating.

This task authorizes diagnostics/probe code only. It does not authorize a behavior
fix.

## Allowed actions

Only:

1. read the live control-plane files and the detailed audit reference;
2. read-only inspect remote source, commits, PR diffs and tests;
3. read-only inspect the local-only checkpoint
   `01eeddaecd0dff596b7e0fd31cd4b1862360bc9f`;
4. read-only inspect the existing Flight Recorder / target-text observer source and
   record exactly what each observer can and cannot prove;
5. read-only analyze the sealed fresh-incident evidence package;
6. classify every critical boundary as:
   - OBSERVED,
   - PARTIAL,
   - MISSING,
   - NOT RELEVANT TO THIS INCIDENT;
7. freeze a minimal P0/P1/P2 probe gap list;
8. update governance/audit documentation.

## Forbidden actions

- no product code edits;
- no new logging implementation;
- no new telemetry implementation;
- no new probe implementation;
- no rebuild/install/reinstall;
- no app restart for experimentation;
- no new reproduction attempt;
- no TCC/Input Monitoring/Accessibility mutation;
- no LaunchAgent/HAL/CoreAudio mutation;
- no timing/threshold/trigger behavior changes;
- no BLE/audio behavior changes;
- no PR merge/release;
- no opportunistic refactor or cleanup;
- no declaration of root cause from a static race alone.

## State-machine audit requirement

At minimum reconcile these distinct machines:

1. **Physical HID / device lifecycle**
   - connected / disconnected;
   - active usages;
   - reconnect-held state;
   - debounce / emitted edge.

2. **Voice gesture classifier**
   - idle → pending → holding → idle;
   - 300 ms classifier;
   - deferred repress and release/tail ownership.

3. **RemoteOrbit Persistent intent**
   - idle ↔ persistentOpen;
   - this is command-derived internal belief, not external IME ACK.

4. **Mapped-trigger ownership**
   - no owner;
   - active deferral;
   - suppressed/discard owner;
   - held hardware release;
   - synthetic owner.

5. **BLE / ATVV transport**
   - transport preparation;
   - mic-open request;
   - streaming;
   - audio stop/drain;
   - post-release close.

6. **Audio route / CoreAudio**
   - candidate prebuffer;
   - remote active;
   - queued/rendered drain;
   - default-input selection;
   - target consumer state is a separate boundary.

7. **Focus / target application**
   - target selection;
   - frontmost/focus request;
   - cross-process ACK where one exists;
   - WindowServer actual frontmost state.

8. **External Doubao/IME session**
   - actual OPEN/LISTENING/STOPPED state;
   - currently not proven by RemoteOrbit internal state alone.

## Boundary-first probe rule

Do not add another internal event merely because a state transition is available.

A new probe is justified only when it answers an unresolved boundary question that
existing evidence cannot answer.

Priority:

### P0

- external IME semantic session state;
- raw HID microphone transition → mapped CGEvent correlation;
- cross-process clock / runtime identity correlation.

### P1

- WindowServer/frontmost/focus transition;
- target-process CoreAudio consumption;
- ATVV boundary correlation improvements only if needed.

### P2

- PCM/internal queue detail; existing diagnostics are already dense.

## Existing diagnostic prototypes are not production facts

PR #16 is ABANDONED.

Its tested prototypes such as:

- `RAW_HID_MIC_STATE`;
- `HID_MIC_EDGE_EMITTED`;
- HID report sequence;
- input-source tagging;

may be used as design evidence when evaluating a minimal future probe, but must not
be treated as installed/runtime capability unless the local checkpoint proves they
exist there.

Likewise, the remote forensic branch `d0a1ab06...` is a retained diagnostic line,
not proof of the installed runtime's exact source.

## Local evidence handoff contract

The next action is a **local read-only evidence handoff**.

The local Agent must not repeat the remote architecture audit. It must fill the
remaining local-only evidence gaps.

### Required deliverables

#### A. Runtime checkpoint reconciliation

For `01eeddaecd0dff596b7e0fd31cd4b1862360bc9f`:

- prove the checkpoint exists locally;
- record worktree/repo path and commit identity;
- inspect only incident-relevant source;
- compare relevant capability against remote `main`, retained forensic branch and
  PR #16 diagnostic prototypes;
- identify whether these capabilities are present:
  - raw HID microphone transition capture;
  - HID report sequence;
  - mapped CGEvent observation and original timestamp;
  - gesture/source tagging;
  - persistent-session internal state;
  - external/target-text observation;
  - WindowServer/frontmost observation;
  - target-process CoreAudio consumption observation.

#### B. Existing observer capability table

For every local observer producing the sealed incident artifacts, record:

```text
OBSERVER_NAME:
SOURCE_PATH:
BINARY_PATH:
SOURCE_HEAD:
PROCESS_IDENTITY:
CLOCK_MODEL:
CORRELATION_KEYS:
BOUNDARIES_OBSERVED:
CAN_PROVE:
CANNOT_PROVE:
OBSERVER_EFFECT:
```

At minimum include Flight Recorder and Target Text Observer.

#### C. Evidence integrity

Recompute SHA-256 for the sealed fresh-incident package and compare with the recorded
hashes.

Any mismatch => `LOCAL_EVIDENCE_GATE: BLOCKED`.

#### D. Boundary matrix

Return B1-B9 exactly once:

```text
B1: OBSERVED / PARTIAL / MISSING / NOT_RELEVANT_TO_THIS_INCIDENT
...
B9: ...
```

Each classification must cite the concrete local evidence source that supports it.

#### E. Incident correlation

Produce one event-occurrence timeline for:

- external-session state evidence;
- raw HID / accepted edge;
- mapped CGEvent;
- gate ownership;
- classification;
- WindowServer/frontmost;
- ATVV;
- CoreAudio target-consumer evidence;
- user-visible stop anchor.

Do not use JSONL append order as causal ordering when event timestamps differ.

#### F. Construction readiness fields

Return:

```text
SPECIFIC_BROKEN_BOUNDARY:
BROKEN_CONTRACT:
FRESH_INCIDENT_DIRECT_SUPPORT:
ADJACENT_BOUNDARIES_RULED_ENOUGH:
PRE_FIX_FAILING_ACCEPTANCE:
MINIMAL_FIX_SCOPE:

LOCAL_EVIDENCE_GATE:
PASS / BLOCKED

CONSTRUCTION_GATE_RECOMMENDATION:
READY_FOR_REMOTE_REVIEW / BLOCKED
```

### Acceptance standard

`READY_FOR_REMOTE_REVIEW` is allowed only if all are true:

1. one specific B1-B9 boundary is identified;
2. one falsifiable broken contract is stated;
3. the sealed fresh incident directly demonstrates that break;
4. adjacent boundaries are observed/rule-outs enough that the proposed change is
   falsifiable;
5. a pre-fix acceptance is defined and can be shown failing for the same reason;
6. the minimal scope changes only that broken boundary.

Anything less remains `BLOCKED`.

### Repository update required from local Agent

After completing the read-only audit, update **both**
`CURRENT_STATUS.md` and `CURRENT_TASK.md` in the same commit.

The commit must record:

- checkpoint reconciliation;
- observer capability inventory summary;
- B1-B9 result;
- incident correlation result;
- unresolved gaps;
- `LOCAL_EVIDENCE_GATE`;
- `CONSTRUCTION_GATE_RECOMMENDATION`.

The local Agent must not declare `Construction Gate: PASS`.
Only set `READY_FOR_REMOTE_REVIEW` when the evidence standard above is fully met.

Push the control-plane branch fast-forward only. If the branch moved, stop, reread,
and reconcile before writing.

## Local evidence handoff result

The required local evidence package has been completed read-only.

### Final readiness fields

```text
SPECIFIC_BROKEN_BOUNDARY: NONE ESTABLISHED
BROKEN_CONTRACT: NONE PROVEN
FRESH_INCIDENT_DIRECT_SUPPORT: PARTIAL
ADJACENT_BOUNDARIES_RULED_ENOUGH: NO
PRE_FIX_FAILING_ACCEPTANCE: NONE ESTABLISHED
MINIMAL_FIX_SCOPE: NOT ESTABLISHED

LOCAL_EVIDENCE_GATE: PASS
CONSTRUCTION_GATE_RECOMMENDATION: BLOCKED
ROOT_CAUSE: UNKNOWN
```

The sealed incident evidence is intact, but preservation integrity is not causal
completeness.

### Pre-probe boundary baseline (historical; before PR #18 probe capture)

```text
B1: PARTIAL
B2: PARTIAL
B3: MISSING
B4: MISSING
B5: PARTIAL
B6: PARTIAL
B7: MISSING
B8: MISSING
B9: PARTIAL
```

### Local capability result

- `01eedda...` has mapped-CGEvent observation, source tagging and detailed
  RemoteOrbit internal state, but no HID report sequence, no original CGEvent
  timestamp, no external IME semantic session observer, no incident-correlated
  WindowServer observer and no target-process CoreAudio consumer observer.
- Flight Recorder is strong for RemoteOrbit-internal ordering but does not cross
  those external boundaries.
- The available Target Text Observer copy is historical, does not cover the fresh
  incident, and cannot prove Doubao semantic session state.
- No reliable wall-clock + monotonic + PID + shared gesture/session join spans all
  independent observers.

### Construction decision

This task does **not** satisfy the Construction Gate.

No behavior fix, product optimization, or probe implementation is authorized under
the current task.

## Step 5 implementation authority

### Active implementation authority

- Branch: `codex/persistent-long-boundary-probes-v1`
- Base: `main@7129ef72949eca956b1d0daddce707d5e417eeed`
- Scope: diagnostic boundary probes and focused tests only.
- PR: #18 OPEN + Draft.
- Product behavior fixes remain forbidden.

### Authorized implementation

Create one dedicated diagnostic branch from live `main`.

Implement only:

1. **B3 HID → mapped CGEvent correlation**
   - transition-only raw microphone HID record;
   - monotonically increasing HID report sequence;
   - accepted/suppressed microphone edge record carrying source sequence/time;
   - original `CGEvent.timestamp` on mapped-trigger records;
   - observer-time fields needed to compare those events;
   - input-source/gesture correlation where already available.

2. **B5/B9 external-session observation**
   - only if a read-only external/system API can observe a concrete external
     transition;
   - label proxy signals as proxy, never as semantic ACK;
   - if no reliable direct observer exists, do not invent one.

3. **B8 frontmost/application activation transition**
   - allowed only as a transition-only independent boundary observer if needed for
     incident discrimination.

### Required tests before implementation is test-ready

At minimum:

- raw microphone transition creates exactly one structured record per transition;
- stable HID state creates no duplicate transition records;
- raw report sequence is monotonic;
- mapped-trigger record retains original `CGEvent.timestamp`;
- synthetic/self-generated events remain distinguishable;
- diagnostic additions do not alter trigger/gate decision results;
- existing Persistent/VoiceKeyFilter tests remain semantically unchanged.

### Prohibited

- no trigger/gate behavior change;
- no Persistent open/close behavior change;
- no timing/threshold change;
- no audio/BLE behavior change;
- no replay/suppress ownership change;
- no production fix disguised as instrumentation;
- no new capture until Diagnostic Test Gate passes;
- no install/release.

### Diagnostic Test Gate

May become PASS only after:

1. focused tests are present and logically cover the new boundary fields;
2. branch diff is diagnostic/test-only;
3. no behavior contract changes are present;
4. B3 evidence is sufficient to decide pre-gate vs post-gate ordering on the next
   incident;
5. any external-session observer is honestly classified DIRECT / PROXY / MISSING.

A Diagnostic Test Gate PASS authorizes one bounded probe-enabled capture, not a
behavior fix.

## Remote implementation checkpoint

```text
PROBE_BRANCH: codex/persistent-long-boundary-probes-v1
PROBE_HEAD: 28824d9dc167f57e3163ef0844aec1b672717d8f
PROBE_PR: #18 OPEN + Draft

B3_PROBE_IMPLEMENTED: YES
B5_B9_DIRECT_SEMANTIC_PROBE_IMPLEMENTED: NO
B5_B9_REASON: no reliable direct external semantic API/ACK established

REMOTE_DIFF_SCOPE_AUDIT: PASS
REMOTE_BEHAVIOR_CHANGE_FOUND: NO

PROBE_IMPLEMENTATION_GATE: PASS
DIAGNOSTIC_TEST_GATE: PASS
NEW_CAPTURE_GATE: READY_FOR_REVIEW
CONSTRUCTION_GATE: BLOCKED
ROOT_CAUSE: UNKNOWN
```

Remote validation is limited to source/diff/test-definition audit because this
repository has no GitHub Actions workflow and remote GitHub cannot execute the
macOS Swift test suite.

## PR #18 observer-effect corrective revalidation — completed locally

The user-authorized authority fetch succeeded and exact remote heads matched:

```text
AUTHORITY_FETCH: PASS
AUTHORITY_GATE: PASS
MAIN_HEAD: 7129ef72949eca956b1d0daddce707d5e417eeed
CONTROL_HEAD_AT_VALIDATION: 9bbc52095194dd6d59321d128a3a7e724ae370d7
START_PROBE_HEAD: f3e852bb0d9d6358a62141dcb4f4e483257772d0
```

After revalidation, the corrective commit was pushed fast-forward to the authorized
probe branch and verified against GitHub:

```text
FINAL_PROBE_HEAD: 28824d9dc167f57e3163ef0844aec1b672717d8f
REMOTE_PROBE_HEAD: 28824d9dc167f57e3163ef0844aec1b672717d8f
PR_18_STATE: OPEN
PR_18_DRAFT: YES
```

```text
VALIDATION_WORKTREE: /Users/jack7788/Documents/Code/remoteorbit-pr18-observer-corrective
WORKTREE_HEAD: 28824d9dc167f57e3163ef0844aec1b672717d8f
WORKTREE_CLEAN: YES
```

Validation:

```text
HID_MONITOR_DIAGNOSTIC_TESTS: PASS (3)
VOICE_BOUNDARY_DIAGNOSTIC_TESTS: PASS (1)
VOICE_INPUT_SOURCE_TESTS: PASS (1)
VOICE_KEY_FILTER_REGRESSION: PASS (10)
VOICE_PRESS_REGRESSION: PASS (28)
PERSISTENT_REGRESSION: PASS (15)
FULL_SWIFT_TEST: PASS
TEST_TOTALS: 266 passed
FAILING_COUNT: 0
FULL_SWIFT_TEST_EXIT_CODE: 0
```

Timing-path and behavior audit:

```text
RAW_REPORT_TIMESTAMP_CAPTURE: reportObservedUptime at report callback entry
PRE_EDGE_DIAGNOSTIC_SERIALIZATION: NONE
PRE_EDGE_DIAGNOSTIC_ENQUEUE: NONE
EDGE_CALLBACK_ORDER: BASELINE_EQUIVALENT
SUPPRESSED_CALLBACK_ORDER: BASELINE_EQUIVALENT
HID_EDGE_TIMING_ANCHOR: BASELINE_EQUIVALENT
BEHAVIOR_DIFF_AUDIT: PASS
BEHAVIOR_CHANGE_FOUND: NO
```

The raw report record is constructed only after the behavior callbacks and still
carries the captured occurrence uptime and report sequence. The behavioral edge
sample remains at the baseline location and feeds the existing 180 ms debounce.
No changes were found to HardwareOptionGate ownership, Option suppression/replay,
Persistent open/close, the 300 ms classifier, BLE activate/stop, AudioPipe
routing/buffering, tail/drain, or synthetic-trigger ownership.

No install, fresh capture, incident reproduction, merge, release, or product behavior
change occurred. The corrective worktree is clean; the dirty primary checkout was
left untouched.

Current gates:

```text
CORRECTIVE_REVALIDATION: PASS
DIAGNOSTIC_TEST_GATE: PASS
INDEPENDENT_TIMING_PATH_REVIEW: PENDING
NEW_CAPTURE_GATE: READY_FOR_REVIEW
CONSTRUCTION_GATE: BLOCKED
ROOT_CAUSE: UNKNOWN
```

The earlier independent audit of `f3e852bb0d9d6358a62141dcb4f4e483257772d0`
identified pre-callback diagnostic work. This corrective moves the full raw-record
construction and edge logger calls behind the corresponding existing callbacks.
Independent review of the pushed `28824d9dc167f57e3163ef0844aec1b672717d8f`
remains the next gate. READY_FOR_REVIEW is not a fresh-capture result.

## Independent timing-path review — PASS

Probe HEAD:

`28824d9dc167f57e3163ef0844aec1b672717d8f`

Independent review confirms the diagnostic placement is sufficiently non-invasive
for one bounded incident capture:

```text
RAW_REPORT_TIMESTAMP_CAPTURE: PASS
PRE_EDGE_DIAGNOSTIC_SERIALIZATION: NONE
PRE_EDGE_DIAGNOSTIC_ENQUEUE: NONE
EDGE_CALLBACK_ORDER: BASELINE_EQUIVALENT
SUPPRESSED_CALLBACK_ORDER: BASELINE_EQUIVALENT
HID_EDGE_TIMING_ANCHOR: BASELINE_EQUIVALENT
MAPPED_TRIGGER_GATE_DECISION_BEFORE_LOGGING: YES
INDEPENDENT_TIMING_PATH_REVIEW: PASS
DIAGNOSTIC_TEST_GATE: PASS
```

### Fresh capture authorization — CONSUMED

At this transition, exactly one probe-enabled fresh capture was authorized; that authorization is now consumed.

Required discipline:

1. build/install only from exact probe HEAD
   `28824d9dc167f57e3163ef0844aec1b672717d8f`;
2. record build/runtime identity before reproduction;
3. use the existing incident capture/sealing process;
4. reproduce only the target incident family
   `PERSISTENT-LONG / EXTERNAL-IME PREMATURE SESSION STOP`;
5. perform one bounded reproduction attempt;
6. seal the resulting evidence package immediately;
7. do not modify product behavior, timing thresholds, trigger ownership, BLE/audio
   behavior, or diagnostics during the capture;
8. after capture, stop for causal review.

If the incident does not reproduce, record that result; do not broaden or repeat the
experiment without a new task transition.

Current gates after the one attempt:

```text
BOUNDED_CAPTURE_ATTEMPTS: 1
INCIDENT_RESULT: NOT_REPRODUCED
EVIDENCE_SEAL: PASS
SECOND_CAPTURE_AUTHORIZED: NO
NEW_CAPTURE_GATE: CONSUMED
CONSTRUCTION_GATE: BLOCKED
ROOT_CAUSE: UNKNOWN
```

## Completion gate

Step 4 is complete only when all are true:

1. the remote state-machine map is frozen;
2. the remote boundary map is frozen;
3. existing remote probe coverage is inventoried;
4. local-only source marker `01eedda...` is read-only reconciled;
5. existing Flight Recorder and target-text observer capabilities are explicitly
   inventoried;
6. each P0/P1 boundary is classified OBSERVED/PARTIAL/MISSING/NOT RELEVANT;
7. the sealed fresh incident is correlated as far as existing evidence permits;
8. any proposed new probe is the minimum boundary probe delta, not general logging;
9. ROOT CAUSE remains UNKNOWN unless direct causal evidence crosses the required
   boundary;
10. Construction Gate remains BLOCKED until a broken contract and pre-fix failing
    acceptance are proven.

## Stop conditions

Stop and return for review if:

- local-only source cannot be inspected without mutation;
- an existing observer's capability cannot be established;
- evidence hashes do not match the sealed incident package;
- a requested step would require a new reproduction or runtime mutation;
- analysis reaches a boundary that existing evidence cannot observe.

At that point report the exact missing boundary; do not compensate by adding broad
internal logging.

## Next authorized action

Perform read-only sealed-capture clock-basis reconciliation for the target LONG and
same-run mapped events. The single capture authorization is consumed. Do not
reproduce again. Construction remains blocked; root cause remains unknown. No
behavior fix, merge, or release is authorized.


## Bounded fresh capture completed — 2026-10-04

The only authorized attempt used PR #18 probe HEAD
`28824d9dc167f57e3163ef0844aec1b672717d8f` and exact runtime identity:
PID `25802`, `/Applications/RemoteOrbit.app/Contents/MacOS/RemoteOrbit`, version
`0.2.13` / Build `42`, runtime and build executable SHA-256
`2eeb2e6ac43bf92698a44be9a1297792e5bc35daadd9f8ded4e767a1b494df8e`.
`RUNTIME_IDENTITY_MATCH=YES`.

```text
BOUNDED_CAPTURE_ATTEMPTS: 1
INCIDENT_RESULT: NOT_REPRODUCED
USER_ACTION_TIME_REPORTED: approximately 11:03 local time (+0800)
EVIDENCE_SEAL: PASS
SECOND_CAPTURE_AUTHORIZED: NO
```

Sealed package:

`/Users/jack7788/Library/Logs/RemoteOrbit/incidents/fresh-incident-20261004T102216+0800-pr18-probe`

The package checksum verification passed. Current diagnostics and relevant unified
logs are included. Target Text Observer and both Flight Recorder files are marked
missing for this attempt because their source files predated the probe runtime.

Gesture correlation keeps the Persistent-open short
`9BB5AC9D-E1C3-40E9-80EC-0BDF5654E54C` separate from target LONG
`52AE0F3E-3273-482D-9E92-8092EABCF165`. The LONG raw report was sequence 3 at
approximately `11:03:02.7843 +0800`; the behavioral edge shared that sequence.
Voice press entry was `11:03:02.790974`, Option gate began at `11:03:02.792270`,
and the mapped event observer callback was `11:03:02.810047` with same-process
observer uptime 17.777 ms after gate begin. The event held original CG timestamp
`2251759486203 ns`, with `gate_state=deferring` and `action=defer_down`; subsequent
LONG handling suppressed the mapped trigger and recorded
`trigger_edge_emitted=false`. The original CG timestamp clock cannot be directly
placed on the ProcessInfo uptime basis from available evidence. Thus callback-level
pre-gate leakage is ruled out for this attempt; original event-time ordering is not
established globally.

```text
GESTURE_CLASSIFIED_TIME: 11:03:03.100882 +0800 — hold
ATVV_MIC_OPEN_TX_TIME: 11:03:03.102411 +0800
ATVV_AUDIO_STOP_RX_TIME: 11:03:09.399792 +0800
ATVV_MIC_CLOSE_TX_TIME: 11:03:10.453279 +0800
TRANSPORT_STOP_TIME: approximately 11:03:11 +0800 — BLE disconnect/HID-only restore log at second resolution
PERSISTENT_SEGMENT_COMPLETE: 11:03:09.776384 +0800 — session_remains_open=true
```

```text
B1: PARTIAL
B2: PARTIAL
B3: PARTIAL — correlated records exist; original CG cross-clock ordering unresolved
B4: PARTIAL — internal decision observed; no external acceptance acknowledgement
B5: PARTIAL — Persistent intent observed; no external semantic acknowledgement
B6: PARTIAL
B7: MISSING
B8: MISSING
B9: PARTIAL — user observation plus AVFoundation/CoreAudio proxy only
```

The user observed normal single-click start and normal Persistent LONG input, with
no premature external IME/session stop. RemoteOrbit's persistent segment completed
at `11:03:09.776384 +0800` with `session_remains_open=true`. A Doubao
AVFoundation/CoreAudio stop proxy appears at `11:03:18.069–.099 +0800`; this does
not establish semantic external session state or a premature failure.

```text
SPECIFIC_BROKEN_BOUNDARY: NONE ESTABLISHED
BROKEN_CONTRACT: NONE PROVEN
FRESH_INCIDENT_DIRECT_SUPPORT: NO — target failure did not reproduce
PRE_FIX_FAILING_ACCEPTANCE: NONE ESTABLISHED
MINIMAL_FIX_SCOPE: NOT ESTABLISHED
DIAGNOSTIC_TEST_GATE: PASS
NEW_CAPTURE_GATE: CONSUMED
CONSTRUCTION_GATE: BLOCKED
ROOT_CAUSE: UNKNOWN
NEXT_ACTION: SEALED_CAPTURE_CLOCK_BASIS_RECONCILIATION
```

This is a normal control-like capture, not evidence that the earlier failure is
fixed. No second reproduction, code change, merge, or release is authorized.


## Sealed capture clock-basis reconciliation

No new capture is authorized.

Before adding probes, use the already sealed PR #18 capture to determine whether the
original mapped `CGEvent.timestamp` can be placed on the same within-run startup
time scale as RemoteOrbit monotonic uptime.

For the target LONG and several other mapped events from the same run, extract:

```text
cg_event_uptime_seconds
observer_uptime
OPTION_GATE_BEGIN uptime
VOICE_PRESS_ENTRY uptime
```

Calculate per mapped event:

```text
delivery_latency = observer_uptime - cg_event_uptime_seconds
original_event_vs_gate = cg_event_uptime_seconds - option_gate_begin_uptime
callback_vs_gate = observer_uptime - option_gate_begin_uptime
```

Decision:

- if the values are on the same numeric scale and delivery latency is plausible and
  consistent, B3 original-event ordering may be established for this run;
- if there is a large or inconsistent offset, keep B3 PARTIAL and define the
  minimum clock-calibration delta;
- do not use wall-clock or JSONL append order for this decision.

After this read-only calculation, update B3 and the pre-gate leak finding. Do not
authorize another reproduction, construction, merge, or release.

