# CURRENT_STATUS

Last updated: 2026-10-07
State: ACTIVE INCIDENT — MATCHED-ENDPOINT CAUSAL MODEL REQUIRED
Repository: `Lost0rz/RemoteOrbit`

This file is the authority for mutable current project state. Historical detail remains preserved in Git history.

## Control-plane integrity

- Previous control HEAD: `03d4de274c311fc61eadfda70448baa0e0993e17`.
- Candidate branch remains `codex/disabled-short-classifier-regression-fix` at exact HEAD `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`.
- Installed candidate remains PID `79232`, source HEAD `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`, executable SHA-256 `a033e86a92b02175a498bba3232c5ae8b72719caef781cb74c3187e8e64ed017` unless a later task records otherwise.
- Candidate remains unmerged. User B / LONG remains forbidden.

## Valid matched-endpoint fresh User A

The normal production pair was aligned at both ends:

```text
RemoteOrbit momentary trigger: left_option
Doubao shortcut: Left Option
```

Fresh User A produced exactly one remote gesture:

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

Accepted conclusion remains:

`CLASSIFIER_FIXED_EXTERNAL_MECHANISM_REMAINS`

The PR #14 Disabled-SHORT immediate-HOLD regression is real and corrected by the candidate, but a valid matched Left Option/Left Option fast SHORT still opens the visible Doubao Session. The complete mechanism is therefore not explained by the classifier regression alone.

## Retraction of RO-MAPPED-TRIGGER-DEPENDENCY-012 inference

The Left Control discriminator changed only the RemoteOrbit side:

```text
RemoteOrbit momentary trigger: left_control
Doubao shortcut: remained Left Option
```

Observed control sample:

```text
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
left_control mapped events: defer_down -> pass
```

This sample is real and remains preserved, but its previous causal interpretation is INVALID because the receiver shortcut was not changed to Left Control. A RemoteOrbit Left Control mapping could not be expected to activate a Doubao receiver still configured for Left Option.

Therefore the previous conclusion:

`MAPPED_MODIFIER_DEPENDENCY_SUPPORTED`

is RETRACTED and must not be used for further causal reasoning.

## Cancelled follow-up

`RO-PHYSICAL-LEFT-OPTION-VISIBILITY-013` is cancelled before execution. Physical Left Option visibility may still be useful later for observability work, but it does not answer the primary causal question created by the two-ended shortcut contract.

## Correct causal model

The external trigger is a two-ended contract:

```text
RemoteOrbit mapped trigger key
        must match
Doubao configured voice shortcut key
```

A valid modifier comparison must keep the endpoint contract matched on both sides.

Current evidence therefore supports only:

1. with the matched pair Left Option / Left Option, a valid fast SHORT still opens Doubao despite classifier short, no HOLD, no replay, and no synthetic trigger;
2. the unmatched Left Control / Left Option control cannot discriminate whether the issue is Left Option-specific, generic to matched system-mapped trigger delivery, or caused by some other pre-classification mechanism;
3. exact event-plane/root cause remains UNKNOWN.

## Next candidate discriminator — NOT YET AUTHORIZED

The clean comparison is a matched-pair control:

```text
Baseline pair:
  RemoteOrbit = Left Option
  Doubao shortcut = Left Option

Control pair:
  RemoteOrbit = Left Control
  Doubao shortcut = Left Control
```

Before any execution, the user must approve this bounded hardware/configuration spike because it temporarily changes the Doubao shortcut as well as RemoteOrbit's momentary trigger. The experiment must restore both ends afterward.

If approved, the control must first prove physical Left Control now opens Doubao under the changed Doubao shortcut, then perform exactly one fresh remote fast click with RemoteOrbit also mapped to Left Control.

Decision intent:

- matched Left Control / Left Control also opens Doubao on remote fast SHORT => problem is not Left Option-specific; prioritize generic pre-classification/system-mapped trigger timing/ownership;
- physical Left Control opens Doubao but matched remote Left Control fast SHORT does not => strong evidence of a Left Option-specific or delivery-path asymmetry;
- invalid receiver shortcut/control setup => no inference.

No product source change, rebuild, reinstall, restart, LONG, merge, or new probe is authorized yet.
