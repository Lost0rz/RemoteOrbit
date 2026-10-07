# RemoteOrbit Current Task

## Current task — RO-INCIDENT-20261004-01 / DISABLED-SHORT CANDIDATE CONTROLLED HARDWARE ACCEPTANCE

- **Status:** ACTIVE / EXACT-CANDIDATE INSTALL + MINIMAL HARDWARE ACCEPTANCE AUTHORIZED
- **Incident ID:** `RO-INCIDENT-20261004-01`
- **Candidate branch:** `codex/disabled-short-classifier-regression-fix`
- **Candidate HEAD:** `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`
- **Candidate worktree:** `/private/tmp/remoteorbit-disabled-short-classifier-regression-fix`
- **Merge:** FORBIDDEN before acceptance
- **Source mutation:** FORBIDDEN
- **Runtime replacement:** AUTHORIZED only for exact candidate app
- **Hardware reproduction:** AUTHORIZED only for the sequence below

## Objective

Test one causal question:

> Does restoring Disabled SHORT to the existing ~300 ms classifier eliminate the user-visible fast-click Doubao Session OPEN while preserving true LONG remote voice?

Do not use this acceptance to redesign the trigger path or investigate unrelated persistent-session behavior.

## Accepted code evidence

Independent Web audit accepted candidate `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`:

```text
PRODUCT_CHANGE: AppController.bypassesShortClassification(for:) returns false
HOLD_THRESHOLD: unchanged at existing 0.30 s
HARDWARE_OPTION_MAPPING_CHANGED: NO
VOICEKEYFILTER_CHANGED: NO
HARDWAREOPTIONGATE_CHANGED: NO
BLE_AUDIO_CHANGED: NO
PERSISTENT_SESSION_SEMANTICS_CHANGED: NO
```

Test evidence:

```text
DISABLED_TESTS: 4/4 PASS
PERSISTENT_TRIGGER_TESTS: 97/97 PASS
FULL_SWIFT_TESTS: 292/292 PASS
SELF_TESTS: 3/3 PASS
RELEASE_BUILD: PASS
HARDWARE_QUICK_RELEASE_TEST:
  uses_hardware_option=true
  gate_begin=1
  gate_cancel=1
  gate_short_replay=0
  hold=0
  remote_route=0
  synthetic_edges=0
```

## Gate 0 — exact authority

1. `git fetch origin --prune`.
2. Print and verify live `origin/main` equals the control HEAD containing this task.
3. Print and verify `origin/codex/disabled-short-classifier-regression-fix` exactly equals `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`.
4. Verify canonical remote is `Lost0rz/RemoteOrbit`.
5. Candidate worktree must be clean at exact candidate HEAD.
6. Read `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md` from live `origin/main` before runtime mutation.
7. Do not rebase, merge, cherry-pick, amend, or edit the candidate.

Any mismatch => STOP.

## Gate 1 — preserve current runtime evidence

Before replacing the app:

- record current RemoteOrbit PID, executable path, app version/build, `RemoteOrbitDiagnosticSourceHead`, executable SHA-256 and code-sign identity;
- preserve/hash the current relevant voice diagnostic log and diagnostic journal without truncating or deleting them;
- record current microphone SHORT binding and momentary/persistent trigger-key settings read-only;
- require microphone SHORT remains Disabled and trigger keys remain the user's current Left Option configuration;
- do not reset defaults or alter input method settings.

## Gate 2 — exact candidate build/install

From the clean candidate worktree at exact HEAD `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`:

1. build/package using the repository's normal app packaging path;
2. verify the staged app source marker equals the candidate HEAD exactly;
3. record staged executable SHA-256 and app version/build;
4. gracefully terminate the currently running RemoteOrbit only;
5. replace only `/Applications/RemoteOrbit.app`;
6. do **not** replace/restart the audio driver, CoreAudio, LaunchAgent, TCC, Accessibility or Input Monitoring state;
7. launch the installed candidate normally;
8. verify installed source marker equals candidate HEAD, new PID exists, executable SHA-256 matches staged candidate, version/build and code identity are recorded;
9. confirm the user's SHORT Disabled and Left Option trigger configuration was preserved;
10. run existing read-only diagnostics readiness checks where available (`diagnostics status/verify/query`) without changing runtime state.

If exact identity cannot be proven => STOP before hardware interaction.

## Gate 3 — minimal user hardware acceptance

Do not automate or synthesize the physical remote interaction. Ask the user to perform the following, one step at a time, after install identity is reported ready.

### A. Disabled fast click

Starting with no visible Doubao Session open:

1. User performs one normal fast physical click/release of the remote voice key.
2. User reports whether a Doubao Session visibly opens.
3. Executor captures the exact matching gesture/log window.

Valid A sample requires logs to show the gesture released before the existing hold threshold and was classified SHORT. If the user's press crosses the threshold, classify the sample INVALID_FOR_A and repeat only once.

Expected candidate evidence:

```text
bypasses_short_classification=false
GESTURE_CLASSIFIED=short
session_mode=idle
no HOLD promotion
hardware gate begins then cancels
no short replay of mapped trigger
no synthetic trigger edge
USER_VISIBLE_DOUBAO_SESSION_OPEN=NO
```

If a valid A sample still opens Doubao Session => **STOP immediately**. Do not perform LONG and do not edit code. Final classification: classifier correction valid by contract, external opening mechanism unresolved; resume B4 later.

### B. Disabled true LONG

Only if A passes:

1. User presses and holds the physical voice key clearly beyond 300 ms.
2. User speaks a short phrase after the voice HUD/remote voice path becomes active.
3. User releases the key.
4. User reports whether remote speech input worked normally.

Expected evidence:

```text
bypasses_short_classification=false
initial state=pending
GESTURE_CLASSIFIED=hold after threshold
HOLD/remote route starts once
physical/system-mapped trigger architecture remains in use
speech input works
release completes normal momentary lifecycle
```

For this Disabled configuration, no persistent Session is expected to remain open after the true LONG. This task does not test the separate correctly-entered Persistent Session closure issue.

## Gate 4 — evidence seal and stop

After A and, if allowed, B:

- seal/hash the exact candidate runtime log window;
- record gesture IDs, timestamps, classifier outcomes, gate result, mapped/synthetic trigger observations, runtime identity, and the user's visible result;
- do not merge candidate;
- do not start new diagnostics or fixes;
- leave installed candidate in place unless a safety/runtime failure requires restoring the preserved previous app.

## Decision states

### ACCEPTED_CAUSAL_FIX

Use only if:

```text
A_VALID_SHORT_SAMPLE: YES
A_CLASSIFIED_SHORT: YES
A_DOUBAO_SESSION_OPEN: NO
B_TRUE_LONG_SAMPLE: YES
B_CLASSIFIED_HOLD: YES
B_REMOTE_SPEECH_WORKS: YES
```

Then report that PR #14 Disabled-classifier regression is causally accepted for the current Disabled fast-click Session-open symptom. Do not claim resolution of any separately proven correctly-entered Persistent Session external-close behavior.

### CLASSIFIER_FIXED_EXTERNAL_MECHANISM_REMAINS

Use if a valid A sample is classified SHORT under the candidate but Doubao Session still opens. Stop and preserve evidence; B4 becomes the next investigation.

### CANDIDATE_REGRESSION

Use if A no longer opens Session but a valid true LONG no longer works as expected. Stop; do not merge.

## Required report

```text
TASK_ID: RO-DISABLED-SHORT-HARDWARE-ACCEPTANCE-002
CONTROL_HEAD:
CANDIDATE_HEAD: 172427957fd18a2b5827edd1cb1c4bddb6a5b7db
CANDIDATE_REMOTE_MATCH:
WORKTREE_CLEAN:

PREVIOUS_RUNTIME_PID:
PREVIOUS_RUNTIME_SOURCE_HEAD:
PREVIOUS_RUNTIME_SHA256:
EVIDENCE_PRESERVED:

INSTALLED_RUNTIME_PID:
INSTALLED_SOURCE_HEAD:
INSTALLED_SHA256:
STAGED_INSTALLED_MATCH:
SETTINGS_PRESERVED:
DIAGNOSTIC_READINESS:

A_SAMPLE_VALID:
A_GESTURE_ID:
A_DURATION_MS:
A_BYPASS:
A_CLASSIFICATION:
A_GATE_RESULT:
A_MAPPED_TRIGGER:
A_SYNTHETIC_TRIGGER:
A_DOUBAO_SESSION_OPEN:

B_PERFORMED:
B_GESTURE_ID:
B_DURATION_MS:
B_CLASSIFICATION:
B_REMOTE_ROUTE:
B_SPEECH_WORKED:
B_RELEASE_RESULT:

PRODUCT_SOURCE_CHANGED_DURING_ACCEPTANCE: NO
MERGED: NO
EVIDENCE_HASHES:
FINAL_STATE:
```
