# RemoteOrbit Current Task

## Current task — RO-INCIDENT-20261004-01 / EXTERNAL IME BOUNDARY GAP CLOSURE

- **Status:** ACTIVE / DIAGNOSTIC-ONLY
- **Incident ID:** `RO-INCIDENT-20261004-01`
- **Installed runtime source:** `77812cb1ccab051aca0e7d79b82f2db309074775`
- **Product Construction Gate:** BLOCKED
- **Source/product behavior mutation:** FORBIDDEN
- **Release/install/runtime replacement:** NOT AUTHORIZED

## Confirmed contract failure

Expected:
- SHORT from idle opens persistent IME session.
- LONG while persistent-open is `audio_only`.
- LONG must not replay/toggle the persistent trigger.
- persistent session remains open after LONG.

Confirmed by user on the exact-main diagnostic runtime:
- SHORT opened the session.
- LONG was performed.
- external Doubao IME session exited.

Strongest local candidate shows:

```text
LONG_CLASSIFICATION: hold (313 ms)
REMOTE_SEGMENT_POLICY: audio_only
PERSISTENT_MODE_BEFORE_LONG: persistent_open
PERSISTENT_MODE_AFTER_LONG: persistent_open
MAPPED_TRIGGER_DURING_LONG: none correlated
SHORT_REPLAY_DURING_LONG: none observed
PERSISTENT_TOGGLE_DURING_LONG: none observed
```

The gesture UUIDs are not yet independently bound to the user's intended reproduction because extra gestures were present in the capture window.

## Objective

Close only the remaining evidence gap between the internally preserved `persistent_open` state and the externally observed IME-session exit.

Priority boundaries:

1. **B4** — determine whether any trigger/event was actually delivered to or acknowledged by the external IME during LONG.
2. **B5 external** — obtain an independently time-correlated observation of the external session state transition.
3. **B9** — capture the user-visible/semantic session result in a machine-correlatable way.
4. Correlate any external exit with existing ATVV/BLE/audio lifecycle events without assuming causality.

## Allowed

- read-only analysis of the sealed exact-main reproduction;
- one minimal, non-product diagnostic capture if existing evidence cannot close B4/B5/B9;
- passive OS/unified-log/observer capture that does not change RemoteOrbit behavior;
- correlation documentation and focused diagnostic-only tests if a diagnostic probe is added under a separately authorized branch.

## Forbidden

- no SHORT/LONG threshold change;
- no trigger/gate ownership change;
- no persistent-session semantic change;
- no BLE/audio behavior fix;
- no driver/CoreAudio/TCC/settings mutation;
- no restart/reinstall unless separately authorized;
- no speculative product fix.

## Construction gate

Do not open product construction until all are available:

```text
SPECIFIC_BROKEN_BOUNDARY:
BROKEN_CONTRACT:
FRESH_INCIDENT_DIRECT_SUPPORT:
ADJACENT_BOUNDARIES_RULED_ENOUGH:
PRE_FIX_FAILING_ACCEPTANCE:
MINIMAL_FIX_SCOPE:
```

Any UNKNOWN/PARTIAL keeps:

```text
ROOT_CAUSE: UNKNOWN
PRODUCT_CONSTRUCTION_GATE: BLOCKED
```

## Next local action

First perform a read-only re-correlation of the sealed exact-main reproduction using the user's confirmed result `SESSION_EXITED`. Attempt to bind the intended user sequence to the strongest candidate gesture pair using action timestamps, agent prompt/response timing, and log ordering. Do not ask the user to repeat the gesture unless that re-correlation still cannot bind a single sequence.

If the existing sealed evidence still cannot distinguish B4/B5/B9, stop at `PROBE_GAP_EXTERNAL_IME_BOUNDARY` and return the smallest passive capture needed next. Do not fix.
