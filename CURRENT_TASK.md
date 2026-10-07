# RemoteOrbit Current Task

## Current task — RO-INCIDENT-20261004-01 / CROSS-RECEIVER SESSION OWNERSHIP

- **Status:** ACTIVE / FRESH READ-ONLY CAPTURE REQUIRED
- **Task ID:** `RO-CROSS-RECEIVER-SESSION-OWNERSHIP-015`
- **Incident ID:** `RO-INCIDENT-20261004-01`
- **Candidate branch:** `codex/disabled-short-classifier-regression-fix`
- **Candidate HEAD:** `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`
- **Installed source HEAD:** must remain `172427957fd18a2b5827edd1cb1c4bddb6a5b7db` unless independently changed and reported.
- **Installed executable SHA-256:** expected `a033e86a92b02175a498bba3232c5ae8b72719caef781cb74c3187e8e64ed017` unless independently changed and reported.
- **Source mutation:** FORBIDDEN
- **New probes:** FORBIDDEN
- **Rebuild/reinstall:** FORBIDDEN
- **Merge:** FORBIDDEN

## Closed prior scope

The single-input-method Doubao dual-mode shortcut collision is considered resolved by separating Doubao's click/toggle and hold-to-talk shortcuts. Do not continue the prior Left Option visibility or unmatched-key experiments unless that single-input symptom returns.

The independent PR #14 classifier regression remains real; the current candidate still fixes it by restoring normal short/long classification.

## New scenario

The user is testing two different input receivers:

```text
Receiver A / Doubao persistent shortcut = Left Option
Receiver B / another input method shortcut = Right Option

SHORT intended -> Left Option / Receiver A
LONG intended  -> Right Option / Receiver B
```

User reports the two voice dialogs still interfere.

## Source-model fact

Current RemoteOrbit state machine assumes a persistent Session has one receiver owner. If a new press starts while `voiceSessionMode == persistentOpen`, `VoicePressCoordinator` selects `remoteSegmentTriggerPolicy = audioOnly`. On LONG confirmation it attempts to suppress the mapped momentary hardware trigger rather than hand ownership to a second receiver.

Therefore the present architecture supports:

```text
SHORT opens persistent receiver A
LONG while A open -> audio-only continuation into A
```

It does not explicitly support:

```text
SHORT opens receiver A
LONG while A open -> close/suspend A and activate independent receiver B
```

## Goal

Use existing diagnostics to determine which of these actually happens in the reported conflict:

1. current state machine remains `persistent_open/audioOnly` and Receiver B is not actually triggered — then the issue is a product-semantics/receiver-ownership mismatch;
2. current state machine is `persistent_open/audioOnly` but a Right Option reaches Receiver B anyway — then there is a suppression/trigger-leak bug;
3. the SHORT never establishes or retains `persistent_open` internally — then session state drift is the first bug.

Do not design or implement a handoff fix before this distinction is proven.

## Gate 0 — exact readiness

1. `git fetch origin --prune`.
2. Read live `AGENTS.md`, `CURRENT_STATUS.md`, and this task from `origin/main`.
3. Verify candidate/runtime identity and current trigger configuration; report any drift, but do not restart or reinstall to force a match.
4. Record the two receiver shortcut assignments exactly as currently configured.
5. Verify existing voice/app diagnostics are readable.
6. Confirm no visible voice Session/dialog is open before the fresh sequence.

No source edits.

## Gate 1 — fresh append-only baseline

Create a fresh evidence subdirectory under the existing incident evidence root.

Do not clear or rotate logs.

Record:

```text
wall-clock baseline
voice log path/size/record count/last seq
app log path/size/line count/last relevant timestamp
runtime PID/source HEAD/binary SHA
RemoteOrbit persistent trigger
RemoteOrbit momentary trigger
Receiver A shortcut
Receiver B shortcut
current internal session mode if observable
```

Seal/hash baseline metadata.

Then return only:

`READY_FOR_CROSS_RECEIVER_SHORT — perform exactly one SHORT that opens Receiver A; do not LONG yet.`

## Gate 2 — establish Receiver A ownership

User performs exactly one SHORT intended to open Receiver A.

Capture only post-baseline records and verify:

```text
classification = short
RemoteOrbit internal session_mode after accepted toggle = persistent_open
persistent owner key = expected Left Option (or actual configured key)
Receiver A visibly open = YES
Receiver B visibly open = NO
```

If internal `persistent_open` is not established, return:

`PERSISTENT_OWNER_STATE_NOT_ESTABLISHED`

STOP before LONG.

If Receiver B is already open, sample is invalid for this task.

If valid, seal a second append-only boundary and return only:

`READY_FOR_CROSS_RECEIVER_LONG — with Receiver A still open, perform exactly one LONG intended for Receiver B; release once; do not repeat.`

## Gate 3 — one LONG while Receiver A remains open

User performs exactly one deliberate LONG while Receiver A is still visibly open.

User reports:

```text
Receiver A after LONG: open / closed / changed
Receiver B during LONG: opened / did not open
After release: which dialogs remain visible
Which receiver appears to own dictation/output
```

Analyze only records after the second boundary.

Extract at minimum:

```text
GESTURE_ID
duration
GESTURE_CLASSIFIED
session_mode at begin/classification/release
remoteSegmentTriggerPolicy
PERSISTENT_SEGMENT_BEGIN count/fields
persistent owner key
momentary configured key
OPTION_GATE begin/suppress/cancel/reset/replay events
hardware-trigger suppression outcome
MAPPED_TRIGGER_EVENT count/actions for right_option
synthetic trigger down/up for right_option
AUDIO_START/AUDIO_FIRST/AUDIO_STOP
frontmost/input-source transitions already provided by existing diagnostics
```

Do not add new probes.

## Decision

### Case A — architecture behaves as designed

If:

```text
session_mode = persistent_open
policy = audioOnly
Right Option mapped/synthetic trigger reaching Receiver B = NO
Receiver B visibly does not open
```

return:

`CROSS_RECEIVER_HANDOFF_NOT_MODELED`

Interpretation: current product intentionally keeps Receiver A as owner. If product requirement is LONG -> independent Receiver B while A is open, that requires a new explicit receiver-handoff design rather than a bug fix in the current same-owner persistent model.

### Case B — suppression/trigger leakage

If:

```text
session_mode = persistent_open
policy = audioOnly
but Right Option reaches Receiver B or Receiver B visibly opens
```

return:

`AUDIO_ONLY_MOMENTARY_SUPPRESSION_BROKEN`

Preserve exact trigger/gate ordering. Do not fix yet.

### Case C — ownership state drift

If Receiver A visibly opens after SHORT but RemoteOrbit does not retain `persistent_open`, return:

`VISIBLE_PERSISTENT_INTERNAL_OWNERSHIP_DRIFT`

This becomes the first causal problem to isolate.

## Required report

```text
TASK_ID: RO-CROSS-RECEIVER-SESSION-OWNERSHIP-015
CONTROL_HEAD:
CANDIDATE_HEAD:
INSTALLED_PID:
INSTALLED_SOURCE_HEAD:
INSTALLED_SHA256:

RECEIVER_A:
RECEIVER_A_SHORTCUT:
RECEIVER_B:
RECEIVER_B_SHORTCUT:
REMOTE_PERSISTENT_TRIGGER:
REMOTE_MOMENTARY_TRIGGER:

FRESH_BASELINE_SEALED:
SHORT_PERFORMED:
SHORT_GESTURE_ID:
SHORT_CLASSIFICATION:
SHORT_INTERNAL_SESSION_MODE_AFTER:
SHORT_PERSISTENT_OWNER_KEY:
RECEIVER_A_OPEN_AFTER_SHORT:
RECEIVER_B_OPEN_AFTER_SHORT:
SECOND_BOUNDARY_SEALED:

LONG_PERFORMED:
LONG_GESTURE_ID:
LONG_DURATION_MS:
LONG_CLASSIFICATION:
LONG_SESSION_MODE:
LONG_TRIGGER_POLICY:
PERSISTENT_SEGMENT_BEGIN:
PERSISTENT_OWNER_KEY:
MOMENTARY_CONFIGURED_KEY:
HARDWARE_TRIGGER_SUPPRESSION:
RIGHT_OPTION_MAPPED_TRIGGER_EVENTS:
RIGHT_OPTION_SYNTHETIC_TRIGGER_EVENTS:
AUDIO_EVENTS:
RECEIVER_A_AFTER_LONG:
RECEIVER_B_DURING_LONG:
VISIBLE_DIALOGS_AFTER_RELEASE:
USER_OBSERVED_OWNER:

PRODUCT_SOURCE_CHANGED: NO
NEW_PROBES_ADDED: NO
REBUILD_OR_REINSTALL: NO
MERGED: NO

FINAL_STATE:
```
