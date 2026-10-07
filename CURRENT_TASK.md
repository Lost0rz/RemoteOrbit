# RemoteOrbit Current Task

## Current task — RO-INCIDENT-20261004-01 / PHYSICAL LEFT OPTION EVENT-PLANE VISIBILITY

- **Status:** ACTIVE / FRESH PHYSICAL-KEYBOARD OBSERVATION
- **Incident ID:** `RO-INCIDENT-20261004-01`
- **Candidate branch:** `codex/disabled-short-classifier-regression-fix`
- **Candidate HEAD:** `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`
- **Installed source HEAD:** must remain `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`
- **Installed executable SHA-256:** must remain `a033e86a92b02175a498bba3232c5ae8b72719caef781cb74c3187e8e64ed017`
- **Expected installed PID:** `79232` unless independently explained; restart remains forbidden.
- **Momentary configuration:** restored to `left_option`.
- **Evidence root:** `/private/tmp/remoteorbit-disabled-short-hardware-acceptance-20261007`
- **Source mutation:** FORBIDDEN
- **Settings mutation:** FORBIDDEN
- **Rebuild/reinstall/restart:** FORBIDDEN
- **Merge:** FORBIDDEN
- **Remote hardware use:** FORBIDDEN in this task
- **LONG/User B:** FORBIDDEN

## Accepted prior result

`RO-MAPPED-TRIGGER-DEPENDENCY-012` is accepted as:

`MAPPED_MODIFIER_DEPENDENCY_SUPPORTED`

Evidence:

```text
normal remote Left Option:
  Doubao Session OPEN
  MAPPED_TRIGGER_EVENT count = 0

control remote Left Control:
  valid short, 89.823 ms
  Doubao Session NO
  left_control defer_down -> pass observed
```

The control configuration was restored to Left Option and HID readback/verify matched `0x7000000E2`.

Do not repeat the Left Control experiment.

## Goal

Determine whether the current RemoteOrbit CGEvent filter can observe a **physical keyboard Left Option** transition at all.

This separates:

1. physical Left Option is visible to the filter but hidutil-mapped remote Left Option is not; versus
2. Left Option is not visible/matched by the current filter plane generally.

This task does not attempt a fix.

## Gate 0 — exact read-only readiness

1. `git fetch origin --prune`.
2. Verify live `origin/main` exactly equals the control HEAD containing this task.
3. Verify candidate remote exact HEAD `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`.
4. Read `AGENTS.md`, `CURRENT_STATUS.md`, and this task from live `origin/main`.
5. Verify installed runtime source/hash remain exact and no restart occurred.
6. Verify:
   - SHORT = Disabled;
   - effective momentary trigger = `left_option`;
   - persistent trigger = `left_option`;
   - HID mapping/readback target = `left_option` / `0x7000000E2` / MATCH;
   - active input method is visually confirmed Doubao if TIS remains unhealthy.
7. Verify diagnostics/voice log remain readable.
8. Do not touch the remote.

STOP for source/hash/control/runtime/config mismatch. Do not repair by mutation.

## Gate 1 — fresh append-only baseline

Create a new evidence subdirectory for this task.

Do not clear or rotate logs.

Record at minimum:

```text
baseline wall-clock timestamp
voice log path + byte size + record count + last seq/event
app log path + byte size/line count + last relevant timestamp
current PID/source HEAD/binary SHA
current momentary/HID mapping readback
```

Hash the baseline metadata.

After the baseline is sealed, return only:

`READY_FOR_PHYSICAL_LEFT_OPTION — tap the Mac physical Left Option exactly once; do not touch the remote.`

Then wait for the user.

## Gate 2 — exactly one physical keyboard Left Option tap

Starting with no visible Doubao Session open:

- user taps the **Mac physical Left Option exactly once** and releases normally;
- user does not touch the remote;
- user reports whether Doubao Session visibly opened.

Immediately analyze only records appended after the fresh baseline.

This is not a remote gesture sample. Do not require a `GESTURE_CLASSIFIED` record.

Record all post-baseline `MAPPED_TRIGGER_EVENT` records relevant to Left Option, including:

```text
count
event type
key
action
gate state
synthetic marker
gesture ID if any
CGEvent timestamp raw if present
observer uptime
```

Also record whether any remote raw HID microphone edge occurred; expected count is 0.

If the user accidentally touches the remote or multiple physical Left Option tap pairs cannot be isolated, mark:

`PHYSICAL_LEFT_OPTION_SAMPLE_INVALID`

and STOP without inference.

## Gate 3 — decision

### Case A — physical Left Option is observed

If the single physical Left Option tap yields one or more matching Left Option `MAPPED_TRIGGER_EVENT` records while remote raw HID microphone edges remain 0, return:

`PHYSICAL_LEFT_OPTION_VISIBLE_REMOTE_MAPPED_OPTION_NOT_VISIBLE`

Interpretation:

- the current filter can observe physical Left Option;
- the accepted remote Left Option sample opened Doubao without a corresponding mapped-trigger observation;
- the next investigation should focus on the hidutil-remapped remote Left Option delivery path / lower event plane before the current filter, not classifier/prewarm.

Do not edit code yet.

### Case B — physical Left Option is not observed

If Doubao reacts to the physical Left Option but the post-baseline logs contain no matching Left Option `MAPPED_TRIGGER_EVENT`, return:

`LEFT_OPTION_NOT_VISIBLE_AT_CURRENT_FILTER_PLANE`

Interpretation:

- the current filter/diagnostic plane does not observe Left Option reliably even from the physical keyboard;
- the next investigation should focus on CGEvent tap coverage/matching for Left Option before blaming hidutil-specific remote delivery.

Do not edit code yet.

### Case C — physical Left Option does not open Doubao

Record the unexpected user-visible result and return:

`PHYSICAL_LEFT_OPTION_TRIGGER_BASELINE_CHANGED`

STOP. Do not reinterpret previous remote evidence; the Doubao trigger environment has changed and must be reconciled first.

## Required report

```text
TASK_ID: RO-PHYSICAL-LEFT-OPTION-VISIBILITY-013
CONTROL_HEAD:
CANDIDATE_HEAD:
INSTALLED_PID:
INSTALLED_SOURCE_HEAD:
INSTALLED_SHA256:
SHORT:
MOMENTARY_EFFECTIVE:
PERSISTENT:
HID_MAPPING_TARGET:
INPUT_SOURCE_AUTHORITY:
FRESH_BASELINE_SEALED:
PHYSICAL_LEFT_OPTION_PERFORMED:
REMOTE_TOUCHED: NO
REMOTE_RAW_HID_MIC_EDGE_COUNT:
PHYSICAL_LEFT_OPTION_MAPPED_EVENT_COUNT:
PHYSICAL_LEFT_OPTION_MAPPED_EVENTS:
PHYSICAL_LEFT_OPTION_DOUBAO_OPEN:
APP_RESTARTED: NO
SETTINGS_CHANGED: NO
PRODUCT_SOURCE_CHANGED: NO
REBUILD_OR_REINSTALL: NO
MERGED: NO
LONG_PERFORMED: NO
FINAL_STATE:
```
