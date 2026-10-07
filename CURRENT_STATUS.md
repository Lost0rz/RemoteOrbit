# CURRENT_STATUS

Last updated: 2026-10-07
State: ACTIVE INCIDENT — DISABLED-SHORT CANDIDATE IN CONTROLLED HARDWARE ACCEPTANCE
Repository: `Lost0rz/RemoteOrbit`

This file is the authority for mutable current project state. Historical detail remains preserved in Git history.

## Control-plane integrity

- Prior control HEAD: `3c35a8eebe300b1064adb73842fd499f46c4b46c`.
- Prior B4 external event-plane investigation remains PAUSED, not deleted.
- Lane A governance: CLOSED.
- PR #18 boundary probes: MERGED + CLOSED.
- PR #19 DiagnosticAuthority: MERGED + CLOSED.
- PR #20 read-only Diagnostic CLI v1: MERGED + CLOSED.

## Active incident

```text
INCIDENT_ID: RO-INCIDENT-20261004-01
USER_CONFIGURATION: microphone SHORT = Disabled; momentary trigger = Left Option; Doubao IME
SYMPTOM_A: fast physical click can visibly open Doubao Session although SHORT is Disabled
SYMPTOM_B: later LONG can speak, but release can close that visible Session
FULL_EXTERNAL_CAUSAL_CHAIN: NOT YET CLOSED
```

## Confirmed regression and accepted candidate

Historical and current evidence establish:

1. PR #6 / commit `80ec3adfe065eac90547f7a76c58f0b510c639b9` restored Disabled SHORT to the normal ~300 ms classifier.
2. Accepted PR #7 retained that semantic together with physical/system-mapped Option as the production trigger owner.
3. PR #14 / commit `346b064de1c320c84706ecd590aa952cfe473da6`, merged as `924a8d3a26d213552fe9b42c9bb5e3bf31755a25`, reversed only the Disabled-SHORT classifier contract so Disabled bypassed classification and entered HOLD immediately.
4. Sealed 2026-10-07 runtime evidence showed 16/16 presses with `bypasses_short_classification=true`, 16/16 classified HOLD, and internal session mode idle.
5. Candidate branch restores only that classifier boundary.

Accepted candidate:

```text
AUTHORIZED_BRANCH: codex/disabled-short-classifier-regression-fix
CANDIDATE_HEAD: 172427957fd18a2b5827edd1cb1c4bddb6a5b7db
BASE_CONTROL_HEAD: 3c35a8eebe300b1064adb73842fd499f46c4b46c
PRODUCT_DIFF: main.swift classifier helper only; Disabled no longer bypasses classifier
HARDWARE_OPTION_MAPPING_CHANGED: NO
VOICEKEYFILTER_CHANGED: NO
HARDWAREOPTIONGATE_CHANGED: NO
BLE_AUDIO_CHANGED: NO
PERSISTENT_SESSION_SEMANTICS_CHANGED: NO
TIMING_THRESHOLD_CHANGED: NO
```

Independent Web audit of exact remote commits found:

```text
INITIAL_CANDIDATE_HEAD: 4d37284707c741d28f9a4745a03fbf36f918ed8a
TEST_ONLY_CORRECTIVE_HEAD: 172427957fd18a2b5827edd1cb1c4bddb6a5b7db
TEST_ONLY_CORRECTIVE_PRODUCT_SOURCE_CHANGE: NONE
HARDWARE_PATH_QUICK_RELEASE_TEST: gate_begin=1; gate_cancel=1; short_replay=0; hold=0; remote_route=0; synthetic_edges=0
FOCUSED_DISABLED_TESTS: 4/4 PASS
FOCUSED_PERSISTENT_TRIGGER_TESTS: 97/97 PASS
FULL_SWIFT_TESTS: 292/292 PASS
SELF_TESTS: 3/3 PASS
RELEASE_BUILD: PASS
DIFF_CHECK: PASS
```

## Controlled installation authorization

The exact candidate HEAD `172427957fd18a2b5827edd1cb1c4bddb6a5b7db` is authorized for one hardware acceptance cycle.

Allowed:

- build/package the exact candidate branch HEAD;
- preserve current installed-app identity and current diagnostic evidence before replacement;
- gracefully terminate only RemoteOrbit;
- replace only `/Applications/RemoteOrbit.app` with the exact candidate build;
- relaunch RemoteOrbit;
- verify source marker, executable hash, version/build, PID, code identity, settings preservation, and diagnostic readiness;
- perform the exact user hardware acceptance in `CURRENT_TASK.md`.

Forbidden:

- merge candidate to main before hardware acceptance;
- source edits or additional diagnostics;
- driver/CoreAudio/TCC/Input Monitoring/Accessibility changes;
- settings reset or trigger-key changes;
- hidutil/HardwareOptionGate/VoiceKeyFilter mutation;
- deletion/truncation of prior evidence;
- broad exploratory reproduction.

## Acceptance interpretation

If Disabled fast clicks are now classified SHORT and do not open Doubao Session, while true LONG still works after the existing threshold, the PR #14 classifier regression is accepted as the causal explanation for **SYMPTOM_A**.

Do not automatically claim the historical genuine-persistent external-close sample is solved. `SYMPTOM_B` is closed as downstream of the fake-open state only for the current Disabled configuration if the acceptance sequence confirms it; any correctly-entered persistent-session closure remains a separate preserved issue.

If a valid Disabled fast click still opens Doubao Session, stop without expanding the patch and resume the paused B4 external event-plane investigation.
