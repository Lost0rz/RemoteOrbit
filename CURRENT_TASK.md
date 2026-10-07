# RemoteOrbit Current Task

## Current task — RO-INCIDENT-20261004-01 / DUAL-MODE SHORTCUT COLLISION VALIDATION

- **Status:** HOLD / USER APPROVAL REQUIRED BEFORE SPLIT-KEY ACCEPTANCE
- **Incident ID:** `RO-INCIDENT-20261004-01`
- **Candidate branch:** `codex/disabled-short-classifier-regression-fix`
- **Candidate HEAD:** `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`
- **Installed source HEAD:** must remain `172427957fd18a2b5827edd1cb1c4bddb6a5b7db` unless a later authorized task records otherwise.
- **Installed executable SHA-256:** must remain `a033e86a92b02175a498bba3232c5ae8b72719caef781cb74c3187e8e64ed017` unless a later authorized task records otherwise.
- **Source mutation:** FORBIDDEN until acceptance result.
- **Merge:** FORBIDDEN until acceptance result.

## Corrected receiver model

Doubao has two distinct voice-input shortcut modes:

```text
A. click/toggle Session — click once to start, click again to stop
B. hold-to-talk — hold while speaking, release to stop
```

These must be treated as two separate semantic endpoints.

RemoteOrbit has corresponding trigger roles:

```text
Persistent Trigger -> Doubao click/toggle Session shortcut
Momentary Trigger  -> Doubao hold-to-talk shortcut
```

## Root-cause candidate

The problematic configuration assigned **Left Option to both Doubao modes**. A fast remote tap could therefore generate a brief Left Option that Doubao legitimately interpreted as its click/toggle Session shortcut, even though RemoteOrbit later classified the physical gesture as SHORT and never promoted it to LONG.

Accepted prior evidence:

```text
remote fast tap = 210.171 ms
bypasses_short_classification = false
classification = short
session_mode = idle
HOLD = 0
gate begin/cancel = 1/1
gate short replay = 0
synthetic trigger down/up = 0
Doubao Session = OPEN
```

User-observed corrective configuration:

```text
Doubao click/toggle Session = Left Control
Doubao hold-to-talk = Left Option
```

Under this split, the user reports the quick remote tap no longer enters the unwanted click/toggle Session state.

Current classification:

`HIGH-CONFIDENCE ROOT CAUSE CANDIDATE: DUAL-MODE SHORTCUT COLLISION`

## Retractions

- `MAPPED_MODIFIER_DEPENDENCY_SUPPORTED` is RETRACTED.
- The prior Left Control sample changed only RemoteOrbit while Doubao still listened to Left Option; it cannot support modifier-specific causality.
- `RO-PHYSICAL-LEFT-OPTION-VISIBILITY-013` is CANCELLED.
- Do not perform further event-plane visibility work unless split-key acceptance fails.

## Proposed bounded acceptance — not yet authorized

Question:

> With Doubao's two modes intentionally separated, does RemoteOrbit now produce the intended short/long behavior without cross-triggering the wrong Doubao mode?

Target configuration:

```text
Doubao click/toggle Session = Left Control
Doubao hold-to-talk = Left Option

RemoteOrbit Persistent Trigger = Left Control
RemoteOrbit Momentary Trigger = Left Option
```

The acceptance should be performed in two stages.

### Stage A — incident-specific Disabled-SHORT validation

Keep the current incident candidate and SHORT business action disabled.

1. Verify the two Doubao shortcuts are split exactly as above.
2. Verify RemoteOrbit persistent/momentary trigger configuration matches the intended roles above.
3. Seal a fresh append-only evidence baseline.
4. Perform exactly one remote fast click/release `<300 ms`.
5. Expected:
   - classification = short;
   - HOLD = 0;
   - no persistent click/toggle Session opens;
   - no long-path trigger ownership remains.
6. Perform exactly one deliberate LONG only if Stage A passes and a later task explicitly authorizes it.

Stage A success would confirm that the unwanted Session-open symptom disappears when the two Doubao semantic shortcuts are separated.

### Stage B — final intended UX acceptance

Only after Stage A and after explicitly restoring/enabling the intended persistent SHORT behavior:

```text
SHORT -> persistent toggle via Left Control
LONG while persistent closed -> hold-to-talk via Left Option
LONG while persistent open -> audio-only; release leaves persistent Session open
final SHORT -> close persistent Session
```

This stage is not authorized by the current HOLD task.

## Separate classifier regression

The PR #14 classifier bypass remains an independently real code regression. The current candidate's `bypassesShortClassification = false` behavior is still required and must be judged separately from the Doubao shortcut configuration collision.

Do not merge or discard the candidate solely on the basis of the shortcut-collision finding.

## Current executor instruction

If local AI fetches this task now, it must return only:

`HOLD_FOR_USER_APPROVAL_SPLIT_KEY_ACCEPTANCE`

Do not change source, do not merge, and do not perform additional hardware tests until the user authorizes the bounded split-key acceptance.
