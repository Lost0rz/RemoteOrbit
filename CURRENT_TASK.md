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

Read-only reconcile the local-only runtime/observer capabilities and analyze the
already sealed fresh incident against the committed boundary map.

No new capture and no construction are authorized.
