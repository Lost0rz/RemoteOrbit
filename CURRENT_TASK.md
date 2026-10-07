# RemoteOrbit Current Task

## Current task — RO-INCIDENT-20261004-01 / MATCHED-ENDPOINT CONTROL DESIGN HOLD

- **Status:** HOLD / USER APPROVAL REQUIRED BEFORE MATCHED-PAIR SPIKE
- **Incident ID:** `RO-INCIDENT-20261004-01`
- **Candidate branch:** `codex/disabled-short-classifier-regression-fix`
- **Candidate HEAD:** `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`
- **Installed source HEAD:** must remain `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`
- **Installed executable SHA-256:** must remain `a033e86a92b02175a498bba3232c5ae8b72719caef781cb74c3187e8e64ed017`
- **Expected installed PID:** `79232` unless independently explained; restart remains forbidden.
- **Source mutation:** FORBIDDEN
- **Rebuild/reinstall/restart:** FORBIDDEN
- **Merge:** FORBIDDEN
- **LONG/User B:** FORBIDDEN

## Retraction

`RO-MAPPED-TRIGGER-DEPENDENCY-012` produced a real Left Control sample, but its causal conclusion is invalid because only the RemoteOrbit endpoint was changed.

The actual receiver contract is two-ended:

```text
RemoteOrbit mapped key == Doubao configured voice shortcut
```

The control used:

```text
RemoteOrbit = Left Control
Doubao = Left Option
```

Therefore `CONTROL_DOUBAO_SESSION_OPEN=NO` was expected from a shortcut mismatch and cannot support `MAPPED_MODIFIER_DEPENDENCY_SUPPORTED`.

`MAPPED_MODIFIER_DEPENDENCY_SUPPORTED` is RETRACTED.

`RO-PHYSICAL-LEFT-OPTION-VISIBILITY-013` is CANCELLED before execution because it does not answer the primary two-ended causal question.

## Surviving accepted evidence

The valid production-aligned fresh A remains accepted:

```text
RemoteOrbit = Left Option
Doubao shortcut = Left Option
GESTURE_ID = 66EAAC65-0704-482C-B01B-4F89F3DE0E19
RAW_HID_DOWN_UP_MS = 210.171
bypasses_short_classification = false
classification = short
session_mode = idle
HOLD = 0
gate begin/cancel = 1/1
gate short replay = 0
synthetic trigger down/up = 0
MAPPED_TRIGGER_EVENT count = 0
Doubao Session = OPEN
```

Decision remains:

`CLASSIFIER_FIXED_EXTERNAL_MECHANISM_REMAINS`

## Proposed next spike — not authorized yet

Question:

> When both ends are changed together to a matched Left Control / Left Control shortcut pair, does one valid remote fast SHORT still open Doubao?

This is the minimum valid comparison against the production matched Left Option / Left Option pair.

If the user approves, a later control-plane task may authorize exactly this bounded sequence:

1. Freshly verify candidate/runtime/config and no open Doubao Session.
2. User changes **Doubao voice shortcut** from Left Option to Left Control using Doubao's normal UI.
3. Before touching RemoteOrbit, user physically taps Left Control once and confirms Doubao Session opens. This proves the receiver endpoint is actually listening to Left Control.
4. User changes **RemoteOrbit momentary trigger** from Left Option to Left Control using RemoteOrbit's normal UI.
5. Read-only verify effective HID mapping/filter target = Left Control.
6. Seal a fresh append-only baseline.
7. User performs exactly one remote fast click/release; no LONG/repeat.
8. Capture the same classifier/gate/mapped/synthetic evidence and user-visible Doubao Session state.
9. Restore RemoteOrbit momentary trigger to Left Option.
10. Restore Doubao shortcut to Left Option.
11. Verify physical Left Option again activates Doubao after restoration.

Decision intent:

```text
Matched Left Control / Left Control + valid remote fast SHORT => Doubao OPEN
    => generic matched system-mapped trigger can leak/activate before or despite SHORT cancellation;
       Left Option-specific explanation becomes less likely.

Matched Left Control / Left Control + physical Left Control opens Doubao
but valid remote fast SHORT => Doubao NO
    => strong evidence of Left Option-specific or mapped-delivery asymmetry;
       investigate delivery/event-plane differences next.
```

No execution is authorized until the user approves this matched-endpoint spike.

## Current executor instruction

If local AI fetches this task now, it must return only:

`HOLD_FOR_USER_APPROVAL_MATCHED_ENDPOINT_SPIKE`

Do not change either application's shortcut, do not touch the remote, and do not perform additional diagnostics.
