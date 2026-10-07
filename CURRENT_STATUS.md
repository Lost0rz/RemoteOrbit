# CURRENT_STATUS

Last updated: 2026-10-07
State: ACTIVE INCIDENT — LEFT OPTION EVENT-PLANE VISIBILITY ISOLATION
Repository: `Lost0rz/RemoteOrbit`

This file is the authority for mutable current project state. Historical detail remains preserved in Git history.

## Control-plane integrity

- Previous control HEAD: `e3ab93bea3a561daf044ea24e31a411f5e462680`.
- Candidate branch remains `codex/disabled-short-classifier-regression-fix` at exact HEAD `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`.
- Installed candidate remains PID `79232`, source HEAD `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`, executable SHA-256 `a033e86a92b02175a498bba3232c5ae8b72719caef781cb74c3187e8e64ed017` unless a later task records otherwise.
- Candidate remains unmerged. User B / LONG remains forbidden.

## Accepted classifier result

Fresh User A with the normal Left Option mapping was a valid short gesture:

```text
GESTURE_ID: 66EAAC65-0704-482C-B01B-4F89F3DE0E19
RAW_HID_DOWN_UP_MS: 210.171
BYPASSES_SHORT_CLASSIFICATION: false
CLASSIFICATION: short
SESSION_MODE: idle
GATE_BEGIN/CANCEL: 1/1
GATE_SHORT_REPLAY: 0
HOLD_PROMOTION: 0
SYNTHETIC_TRIGGER_DOWN_UP: 0
MAPPED_TRIGGER_EVENT_COUNT: 0
USER_VISIBLE_DOUBAO_SESSION_OPEN: YES
```

Accepted conclusion: `CLASSIFIER_FIXED_EXTERNAL_MECHANISM_REMAINS`.

## Accepted mapped-modifier discriminator

The configuration-only Left Control control is valid and accepted:

```text
LEFT_CONTROL_KEYBOARD_NEGATIVE_CONTROL: PASS
MOMENTARY_CONTROL: left_control
HID_MAPPING_CONTROL: left_control / 0x7000000E0 / MATCH
CONTROL_GESTURE_ID: 30EFEA60-0465-4719-88A9-C2F09D61223E
CONTROL_DURATION_MS: 89.823
CONTROL_BYPASS: false
CONTROL_CLASSIFICATION: short
CONTROL_SESSION_MODE: idle
CONTROL_HOLD_PROMOTION: 0
CONTROL_GATE_BEGIN/CANCEL: 1/1
CONTROL_GATE_SHORT_REPLAY: 0
CONTROL_SYNTHETIC_TRIGGER_DOWN_UP: 0
CONTROL_DOUBAO_SESSION_OPEN: NO
```

The post-baseline window recorded the control gesture's mapped Left Control edges:

```text
left_control flags_changed defer_down gate=deferring
left_control flags_changed pass gate=none
```

Later unrelated `left_command pass` events are not attributed to the control gesture.

The original momentary configuration was restored to Left Option and HID readback/verify again matched `0x7000000E2` without app restart.

Accepted conclusion: `MAPPED_MODIFIER_DEPENDENCY_SUPPORTED`.

This is stronger than the earlier classifier result: changing only the mapped modifier from Left Option to Left Control removed the visible Doubao Session opening while classifier, pending transport/prewarm, candidate binary, input method authority, and remote hardware were held constant.

Do not overstate this as proof of the exact event plane.

## Event-plane asymmetry now under test

The key asymmetry is:

```text
remote -> Left Option: Doubao OPEN, MAPPED_TRIGGER_EVENT count 0
remote -> Left Control: Doubao NO OPEN, mapped defer_down/pass observed
```

Source audit shows the current filter matching is generic across configured trigger keys: it matches the configured key code and tests that key's modifier flag; there is no obvious product branch that intentionally treats Left Option and Left Control differently at this decision point.

The next minimum discriminator is read-only with respect to product configuration and source: establish a fresh log baseline, then observe exactly one **physical keyboard Left Option tap** while the momentary mapping is restored to Left Option and no remote is touched.

Decision purpose:

- physical Left Option produces `MAPPED_TRIGGER_EVENT` while remote-mapped Left Option did not => current filter can observe physical Left Option, strongly localizing the gap to the hidutil-mapped remote Left Option delivery path / lower event plane;
- physical Left Option also produces no `MAPPED_TRIGGER_EVENT` => the gap is broader to Left Option observation/matching at the current CGEvent filter plane, not yet specifically the remote hidutil delivery.

No new probe, source change, rebuild, reinstall, restart, or merge is authorized for this discriminator.

## Input-source authority

HIToolbox selected-source evidence included Doubao. Realtime TIS returned `com.apple.keylayout.ABC` while its input-source service connection was invalid. For the bounded incident experiment, the user's visual menu-bar confirmation of Doubao remains the accepted active-input-source authority while TIS is unhealthy.
