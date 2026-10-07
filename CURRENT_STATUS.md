# CURRENT_STATUS

Last updated: 2026-10-07
State: ACTIVE INCIDENT — DISABLED-SHORT CLASSIFIER REGRESSION CONFIRMED / NARROW FIX CANDIDATE AUTHORIZED
Repository: `Lost0rz/RemoteOrbit`

This file is the authority for mutable current project state. Historical detail remains preserved in Git history.

## Control-plane integrity

- Control parent before this authorization: `31ccdc231efddde3b982f0121f476b317f087444`.
- Lane A governance: CLOSED.
- PR #18 boundary probes: MERGED + CLOSED.
- PR #19 DiagnosticAuthority: MERGED + CLOSED.
- PR #20 read-only Diagnostic CLI v1: MERGED + CLOSED.
- Prior B4 external event-plane task is PAUSED, not deleted. Resume B4 only if the minimal classifier candidate fails to remove the user-visible Disabled-SHORT symptom.

## Active incident

```text
INCIDENT_ID: RO-INCIDENT-20261004-01
USER_CONFIGURATION: microphone SHORT = Disabled; momentary trigger = Left Option; Doubao IME
USER_VISIBLE_SYMPTOM_A: a fast physical click can visibly open a Doubao Session even though SHORT is Disabled
USER_VISIBLE_SYMPTOM_B: a later LONG can speak, but release can close the visible Doubao Session
ROOT_CAUSE_FULL_EXTERNAL_CHAIN: NOT YET CLOSED
```

## Newly sealed runtime evidence

Existing sealed window:

```text
WINDOW: 2026-10-07 18:59:41–19:06:46 +08:00
SEQ: 4437–4779
GESTURE_COUNT: 16
BYPASS_TRUE_COUNT: 16
GESTURE_RESULT_HOLD_COUNT: 16
SESSION_MODE_IDLE_COUNT: 16
MAPPED_TRIGGER_EVENT_COUNT: 0
MAPPED_TRIGGER_MISMATCH_COUNT: 0
SYNTHETIC_TRIGGER_DOWN_COUNT: 0
SYNTHETIC_TRIGGER_UP_COUNT: 0
```

This proves that the current runtime is honoring the PR #14 Disabled-SHORT semantic: Disabled bypasses the 300 ms classifier and every press enters HOLD immediately. It does not by itself prove the exact external event that causes Doubao to show a Session.

## Historical regression attribution

Historical evidence establishes the following sequence:

1. PR #6 / commit `80ec3adfe065eac90547f7a76c58f0b510c639b9` restored the contract that Disabled SHORT remains inside the normal ~300 ms SHORT/LONG classifier.
2. That contract was selectively incorporated into the accepted PR #7 production corrective. Hardware acceptance recorded Disabled SHORT 20/20 without BLE/audio start and Disabled LONG 10/10 entering holding/BLE; the accepted production architecture retained physical/system-mapped Option as the normal owner.
3. PR #14 / commit `346b064de1c320c84706ecd590aa952cfe473da6`, merged as `924a8d3a26d213552fe9b42c9bb5e3bf31755a25`, explicitly reversed only the Disabled-SHORT classifier contract so `binding.isDisabled` bypasses classification and enters HOLD immediately.
4. Current main still contains that exact semantic and matching tests.

Classification:

```text
CONFIRMED_REGRESSION: Disabled SHORT classifier bypass introduced by PR #14
HIGH_CONFIDENCE_CAUSAL_CANDIDATE: immediate HOLD path is enabling the current Disabled-fast-click external Session symptom
UNCONFIRMED_REMAINING_LINK: exact external event/receiver mechanism that makes Doubao show Session OPEN
HARDWARE_OPTION_PRIMARY_ARCHITECTURE: PRESERVE
SYNTHETIC_OPTION_PRIMARY_REDESIGN: NOT AUTHORIZED
```

## Narrow construction authorization

A minimal behavior candidate is now authorized.

```text
AUTHORIZED_BRANCH: codex/disabled-short-classifier-regression-fix
PLANNED_WORKTREE: /private/tmp/remoteorbit-disabled-short-classifier-regression-fix
AUTHORIZED_PRODUCT_SOURCE: remote-orbit/Sources/RemoteOrbit/main.swift
AUTHORIZED_PRIMARY_TEST: remote-orbit/Tests/RemoteOrbitTests/DisabledShortClassifierTests.swift
HARDWARE_OPTION_MAPPING_CHANGES: FORBIDDEN
VOICEKEYFILTER_CHANGES: FORBIDDEN
HARDWAREOPTIONGATE_CHANGES: FORBIDDEN
BLE_AUDIO_PIPELINE_CHANGES: FORBIDDEN
PERSISTENT_SESSION_SEMANTICS_CHANGES: FORBIDDEN
SETTINGS_UI_CHANGES: FORBIDDEN
DIAGNOSTIC_ARCHITECTURE_EXPANSION: FORBIDDEN
```

Required behavior after the candidate:

```text
SHORT Disabled + release before 300 ms
→ remains inside classifier
→ classified SHORT
→ disabled short action produces no product action
→ returns idle
→ must not enter HOLD

SHORT Disabled + still held across 300 ms
→ classified HOLD
→ existing remote-microphone path starts
→ existing physical/system-mapped trigger architecture remains unchanged

voiceKeyDefault / Persistent SHORT
→ existing classifier and persistent semantics unchanged
```

The intended minimal source change is to restore Disabled SHORT to `bypassesShortClassification == false` using the current code shape, not to cherry-pick historical files wholesale.

## Validation gate

Before any installation or user reproduction, the candidate must pass:

1. focused RED proof against current PR #14 behavior;
2. minimal GREEN implementation;
3. focused Disabled-SHORT tests;
4. current persistent-session/voice-trigger focused tests sufficient to prove no semantic spillover;
5. full Swift test suite;
6. release build;
7. exact diff audit proving no hardware mapping, gate, BLE/audio, persistent-session or settings behavior changed.

After code/test/build validation, stop at:

```text
WAITING_FOR_INDEPENDENT_WEB_MINIMAL_FIX_AUDIT
```

Do not install or perform the user hardware acceptance until Web independently audits the branch and explicitly authorizes installation.

## Decision after candidate audit

If the candidate is accepted and later hardware acceptance shows Disabled fast click no longer opens Doubao Session while true LONG still works, the PR #14 classifier regression becomes the closed causal explanation for the user-visible entry symptom.

If the candidate passes code validation but the external Session still opens under Disabled fast click, retain the classifier correction if independently justified, mark the remaining external mechanism unresolved, and resume the paused B4 external event-plane investigation from preserved evidence rather than expanding diagnostics speculatively.
