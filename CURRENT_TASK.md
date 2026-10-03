# RemoteOrbit Current Task

## Task identity

- **Task:** INCIDENT MODE — DIAGNOSTIC GAP AUDIT
- **Incident family:** PERSISTENT-LONG / EXTERNAL-IME PREMATURE SESSION STOP
- **Phase:** Step 4 — probe/state-machine/boundary audit and forensic readiness
- **Status:** ACTIVE
- **Task authority:** this file
- **Product development:** FROZEN
- **Root cause:** UNKNOWN
- **Construction Gate:** BLOCKED
- **Fresh Incident Gate:** PASS

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

Determine whether the sealed fresh incident can be causally narrowed using the
already-existing evidence system, and identify the **minimum boundary probe delta**
only if an essential boundary is still unobservable.

This is an audit/design task, not probe implementation and not bug fixing.

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

### Boundary result

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

Local evidence handoff is COMPLETE.

Stop product work here. A new explicit task is required before implementing any
probe or performing another capture.

The next task, if authorized, should be limited to designing and implementing the
minimum boundary-observation delta for the unresolved B3/B4/B5/B7/B8/B9 questions,
with priority on external IME semantic session state and HID→mapped-CGEvent
correlation. It must not expand general internal logging.
