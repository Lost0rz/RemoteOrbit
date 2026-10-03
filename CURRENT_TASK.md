# RemoteOrbit Current Task

## Task identity

- **Task:** INCIDENT MODE — FRESH INCIDENT CAPTURE
- **Incident family:** PERSISTENT-LONG / EXTERNAL-IME PREMATURE SESSION STOP
- **Phase:** fresh incident acquisition only
- **Status:** ACTIVE
- **Task authority:** this file
- **Product development:** FROZEN
- **Root cause:** UNKNOWN

## User authorization

The user explicitly authorized this incident-mode transition on 2026-10-03.

The user explicitly requires:

1. formally define the current problem as an incident;
2. keep root cause UNKNOWN;
3. prohibit opportunistic behavior fixes;
4. allow only the smallest verifiable next action;
5. obtain one fresh incident before any further diagnosis or repair work.

## Incident statement

RemoteOrbit has an unresolved incident in which the external IME / voice collection
session can stop unexpectedly around a Persistent LONG interaction before the
intended LONG-classified transaction has been conclusively established.

This task does **not** authorize deciding why that happens.

## Root-cause rule

`ROOT CAUSE = UNKNOWN`

Historical observations and source-level race possibilities are evidence/hypotheses,
not root cause.

Specifically, do not declare any of the following causal without fresh direct
evidence:

- pre-classification trigger leakage;
- Option/F5 ordering;
- WindowServer focus switching;
- BLE/audio transport;
- Doubao/external-IME behavior;
- a timing race inferred only from code.

## Single allowed objective

Obtain and preserve **one fresh incident**.

The incident must occur after this task transition and must be captured without
changing code, diagnostics, permissions, drivers, runtime configuration, packaging,
or installed behavior.

## Allowed actions

Only these actions are authorized:

1. read `AGENTS.md`, `CURRENT_STATUS.md`, and this file;
2. read-only verify canonical repo/control branch state;
3. read-only verify the exact installed/running RemoteOrbit identity needed to bind
   the incident to a runtime;
4. use the already-retained Flight Recorder/evidence worktree and already-existing
   diagnostics/logs **as-is**;
5. start one bounded normal reproduction/capture session;
6. stop at the first fresh failure;
7. preserve the incident window and record its exact identifier/timestamps;
8. perform read-only extraction/summarization of the evidence needed to establish
   event ordering;
9. update `CURRENT_STATUS.md` with the fresh incident reference after capture.

## Forbidden actions

Until the fresh-incident gate is satisfied:

- no product code edits;
- no bug fix;
- no "small obvious fix";
- no refactor or cleanup while investigating;
- no new logging/telemetry/probes/instrumentation;
- no changing existing log verbosity;
- no threshold/timing changes;
- no Option/F5 trigger-path changes;
- no persistent/momentary behavior changes;
- no BLE/audio buffering/playout/decoder changes;
- no build/rebuild merely for this capture;
- no install/reinstall/replace app;
- no TCC/Input Monitoring/Accessibility mutation;
- no LaunchAgent mutation;
- no HAL/driver/CoreAudio mutation;
- no restart/recovery action used as a diagnostic experiment unless the incident
  capture procedure itself already requires it and CURRENT_STATUS says so;
- no branch/worktree cleanup;
- no PR merge/release;
- no adjacent-issue investigation.

If a tempting fix appears while reading evidence, record it only as
`HYPOTHESIS / NOT AUTHORIZED`.

## Remote audit closure for local evidence acquisition

The remote read-only audit is sufficient to define the next **fresh incident**
capture, but not sufficient to authorize construction.

### Verified boundary

The current code contains a statically possible ordering window in which a
hidutil-translated mapped trigger can reach the event tap before the HIDMonitor
callback has armed the gesture's option gate. Existing tests do not cover that
cross-layer race.

This is not a proven incident occurrence and not root cause.

### Single hypothesis to test first

`HYPOTHESIS: PRE-GATE MAPPED-TRIGGER LEAKAGE`

Do not branch into focus, BLE/audio, WindowServer, or external-IME explanations
unless the fresh incident evidence rejects or fails to establish this first-layer
boundary.

### Local evidence prerequisites

Before reproducing:

- bind the running runtime read-only using installed app path, PID, executable path,
  executable hash, version/build, and any available diagnostic source-head marker;
- identify the current existing diagnostic JSONL/evidence locations;
- make no product/runtime/configuration/permission changes.

Version/build alone is insufficient because both `main` and the retained forensic
branch use 0.2.13 / Build 42 in source.

### Decision rule for the first hypothesis

- **SUPPORTS HYPOTHESIS:** an unowned mapped trigger is logged as pass-through before
  `OPTION_GATE_BEGIN` in the same fresh incident window as the actual target stop.
- **DOES NOT SUPPORT HYPOTHESIS:** the gate is already active before the mapped edge
  and all relevant mapped events are captured/deferred/suppressed while the target
  stop still occurs.
- **INCONCLUSIVE:** mapped-trigger evidence is absent or cannot be correlated to the
  target stop.
- In all three cases, **ROOT CAUSE remains UNKNOWN** until the returned evidence is
  reviewed under a new explicit authorization.

### Preservation rule

`voice-diagnostic-current.jsonl` is truncated at RemoteOrbit launch. After the first
qualifying incident, copy/preserve the current diagnostic evidence before any
restart/relaunch.

### Stop conditions

Stop immediately and return for review when:

1. the first qualifying fresh incident is observed and preserved;
2. the single bounded normal capture ends without reproducing the target symptom;
3. runtime identity cannot be established;
4. any prohibited mutation occurs;
5. evidence cannot be preserved without risk of overwrite.

**CONSTRUCTION GATE remains BLOCKED.**

## Fresh-incident acceptance gate

A capture is accepted as a fresh incident only when all are true:

1. **Freshness**
   - occurred after this task became ACTIVE.

2. **Runtime identity**
   - installed app identity/version/build/executable path and running process identity
     are recorded read-only;
   - if identity cannot be proven, the capture is not authoritative.

3. **No mutation**
   - no code/runtime/diagnostic/configuration/permission mutation occurred between
     identity verification and incident.

4. **User-visible failure**
   - the external IME / collection session actually exhibits the target premature
     stop symptom.

5. **Ordering evidence**
   - existing evidence is sufficient to place, at minimum:
     - physical press/release or equivalent input boundary;
     - LONG/SHORT classification boundary when available;
     - RemoteOrbit voice/session lifecycle boundary;
     - observed external-session stop;
     - any already-existing trigger/focus/audio markers relevant to the same window.

6. **Preservation**
   - incident ID or unique timestamp window is recorded;
   - source log/evidence paths are preserved;
   - no evidence is overwritten for convenience.

## Bounded-capture rule

Run one bounded normal capture session.

- Stop immediately after the first qualifying fresh incident.
- If the target failure does not reproduce, report:
  `NO_FRESH_INCIDENT`
- Do not alter the system to increase reproduction probability.
- Do not start a second experimental variant under this task.

## Output required after capture

Return exactly these decision fields:

```text
REMOTEORBIT INCIDENT MODE — FRESH CAPTURE RESULT

CONTROL_HEAD:
RUNTIME_IDENTITY:
INCIDENT_ID:
INCIDENT_TIMESTAMP:
FRESH_INCIDENT: YES / NO

TARGET_SYMPTOM_OBSERVED:
PHYSICAL_INPUT_BOUNDARY:
CLASSIFICATION_BOUNDARY:
REMOTEORBIT_SESSION_BOUNDARY:
EXTERNAL_SESSION_STOP:
TRIGGER_MARKERS:
FOCUS/WINDOW_MARKERS:
AUDIO/BLE_MARKERS:

MUTATION_DURING_CAPTURE:
NO

ROOT_CAUSE:
UNKNOWN

FACTS:
...

INFERENCES:
...

HYPOTHESES:
...

UNKNOWNS:
...

EVIDENCE_PATHS:
...

FRESH_INCIDENT_GATE:
PASS / NO_FRESH_INCIDENT / BLOCKED

NEXT_ACTION_AUTHORIZED:
NONE — RETURN FOR REVIEW
```

Do not propose or implement a fix in this output.

## Completion gate

This task ends when either:

### A. Fresh incident captured
A qualifying fresh incident is preserved and reported with
`FRESH_INCIDENT_GATE: PASS`.

or:

### B. No fresh incident
The bounded normal capture session completes without reproducing the target symptom,
reported as `NO_FRESH_INCIDENT`.

In either case:

- stop;
- do not advance to diagnosis/fix automatically;
- do not modify product behavior;
- wait for a new explicit task after review.

## Next authorized step

Run only the minimal fresh-incident capture described above.

Nothing else is authorized.
