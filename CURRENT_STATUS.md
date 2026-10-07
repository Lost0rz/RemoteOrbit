# CURRENT_STATUS

Last updated: 2026-10-07
State: ACTIVE INCIDENT — DUAL-MODE SHORTCUT COLLISION IDENTIFIED / SPLIT-KEY ACCEPTANCE REQUIRED
Repository: `Lost0rz/RemoteOrbit`

This file is the authority for mutable current project state. Historical detail remains preserved in Git history.

## Control-plane integrity

- Previous control HEAD: `798c7e71cf08d434b23d1e058f5019a3f1c9d661`.
- Candidate branch remains `codex/disabled-short-classifier-regression-fix` at exact HEAD `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`.
- Installed candidate remains PID `79232`, source HEAD `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`, executable SHA-256 `a033e86a92b02175a498bba3232c5ae8b72719caef781cb74c3187e8e64ed017` unless a later task records otherwise.
- Candidate remains unmerged.

## Newly established external semantic model

The user identified that Doubao exposes two independent voice-input shortcut modes:

1. **Click/toggle Session** — press once to start a persistent Session, press again to stop.
2. **Hold-to-talk** — hold the shortcut while speaking, release to stop.

These are separate receiver semantics and may be assigned different keys.

RemoteOrbit likewise has separate trigger roles:

```text
RemoteOrbit Persistent Trigger  <-> Doubao click/toggle Session shortcut
RemoteOrbit Momentary Trigger   <-> Doubao hold-to-talk shortcut
```

## Configuration collision that explains the symptom

The problematic environment had both Doubao modes assigned to **Left Option**. RemoteOrbit's persistent and momentary trigger roles were also using Left Option in the incident environment.

Therefore a fast remote voice-key tap could briefly present Left Option to the system/receiver even though RemoteOrbit later classified the physical gesture as SHORT and did not promote it to LONG. Doubao could interpret that brief Left Option as its click/toggle Session shortcut and open a persistent Session.

This directly explains the observed matched production sample:

```text
RemoteOrbit momentary = Left Option
Doubao click/toggle = Left Option
Doubao hold-to-talk = Left Option

remote fast click = 210.171 ms
bypasses_short_classification = false
classification = short
session_mode = idle
HOLD = 0
gate begin/cancel = 1/1
gate short replay = 0
synthetic trigger down/up = 0
Doubao Session = OPEN
```

The visible Session opening therefore no longer needs to be explained as a mysterious LONG promotion. It is consistent with a **receiver-side shortcut semantic collision**: the same Left Option edge is valid input for both Doubao modes.

## User-observed split-key behavior

The user reports that when Doubao is configured instead as:

```text
Doubao click/toggle Session = Left Control
Doubao hold-to-talk = Left Option
```

a quick remote click no longer enters the unwanted click/toggle Session state.

This is strong causal evidence for the shortcut-collision model. One bounded split-key acceptance is still required before declaring the incident fully closed.

## Separate code regression remains real

The PR #14 Disabled-SHORT classifier bypass was independently proven to be a real regression. The candidate correctly restores normal short/long classification:

```text
bypassesShortClassification = false
```

That code regression and the Doubao dual-mode shortcut collision are separate issues:

1. **Code regression:** Disabled SHORT incorrectly bypassed classification into HOLD. Candidate fixes this.
2. **Configuration/semantic collision:** Doubao click/toggle and hold-to-talk were both bound to Left Option, so a brief Left Option could start the click/toggle Session even without a LONG classification.

Do not discard the classifier candidate because the external symptom also had a configuration cause.

## Retractions / cancelled paths

- `MAPPED_MODIFIER_DEPENDENCY_SUPPORTED` remains RETRACTED. The prior Left Control experiment changed only the RemoteOrbit side while Doubao still listened to Left Option.
- `RO-PHYSICAL-LEFT-OPTION-VISIBILITY-013` remains CANCELLED. Event-plane visibility is not the primary causal question now.
- Do not perform additional Left Option visibility or unmatched-key experiments unless the split-key acceptance fails.

## Target split-key contract

For the intended product semantics, use distinct receiver shortcuts and matching RemoteOrbit roles:

```text
Doubao click/toggle Session = Left Control
RemoteOrbit Persistent Trigger = Left Control

Doubao hold-to-talk = Left Option
RemoteOrbit Momentary Trigger = Left Option
```

The current Disabled-SHORT incident test may keep the short business action disabled while validating that a fast remote click no longer opens Doubao. Final product acceptance can then restore the intended persistent SHORT behavior separately.

## Current causal classification

`HIGH-CONFIDENCE ROOT CAUSE CANDIDATE: DUAL-MODE SHORTCUT COLLISION`

Expected mechanism:

```text
remote physical tap
-> system-mapped Left Option edge
-> Doubao sees Left Option
-> because click/toggle mode also owns Left Option, Doubao opens persistent Session
-> RemoteOrbit later resolves gesture as SHORT and cancels its own long-path ownership
```

The classifier result does not undo a receiver action that already occurred on the same shortcut edge.

No product source change beyond the existing classifier candidate is authorized before split-key acceptance.
