# CURRENT_STATUS

Last updated: 2026-10-05
State: ACTIVE INCIDENT — EXTERNAL IME SESSION EXIT CONFIRMED / PRODUCT CONSTRUCTION BLOCKED
Repository: `Lost0rz/RemoteOrbit`

This file is the authority for mutable current project state. Historical detail remains preserved in Git history.

## Foundation

- Lane A governance: CLOSED.
- PR #18 boundary probes: MERGED + CLOSED.
- PR #19 DiagnosticAuthority: MERGED + CLOSED.
- PR #20 read-only Diagnostic CLI v1: MERGED + CLOSED.
- Product fix construction: BLOCKED.

## Installed diagnostic runtime

```text
APP: /Applications/RemoteOrbit.app
VERSION: 0.2.13
BUILD: 42
SOURCE_HEAD: 77812cb1ccab051aca0e7d79b82f2db309074775
EXECUTABLE_SHA256: ae07ea884a87a3ac94f0774faa69f921db475985cfd07ecab7ee7a215a9c8924
CLI: READY
```

Validation: 292/292 Swift tests PASS; release build/package/diff check PASS; installed CLI help/status/verify/query PASS. Driver, CoreAudio, TCC and settings were preserved during the controlled app replacement.

## Active incident

```text
INCIDENT_ID: RO-INCIDENT-20261004-01
EXPECTED: SHORT opens persistent session; LONG while open is audio-only and must leave it open.
OBSERVED: user confirmed the external Doubao IME session exits after LONG.
ROOT_CAUSE: UNKNOWN
PRODUCT_CONSTRUCTION_GATE: BLOCKED
```

Strongest correlated candidate:

```text
SHORT_GESTURE_ID: 9D7DDD10-95CD-4494-A73C-C09923D6A6D4
LONG_GESTURE_ID: 05DE2189-B9AA-4B05-9385-46CD3667E3D5
SHORT_INTERNAL: idle -> persistent_open
LONG_CLASSIFICATION: hold (313 ms)
REMOTE_SEGMENT_POLICY: audio_only
PERSISTENT_MODE_BEFORE_LONG: persistent_open
PERSISTENT_MODE_AFTER_LONG: persistent_open
MAPPED_TRIGGER_DURING_LONG: none correlated
SHORT_REPLAY_DURING_LONG: none observed
PERSISTENT_TOGGLE_DURING_LONG: none observed
USER_VISIBLE_EXTERNAL_RESULT: session exited
```

The capture window contained additional gestures, so those UUIDs are the strongest local match rather than independently user-bound identifiers. The user-visible exit for the intended controlled reproduction is confirmed.

## Boundary disposition

- B1: OBSERVED for strongest candidate.
- B2: OBSERVED.
- B3: OBSERVED; candidate LONG has no correlated mapped trigger and `trigger_edge_emitted=false`.
- B4: UNKNOWN; no external IME trigger-receipt acknowledgement.
- B5 internal: OBSERVED / healthy for candidate; RemoteOrbit remains `persistent_open`.
- B5 external: BROKEN at user-visible semantic level; external session exited.
- B6: OBSERVED.
- B7: UNKNOWN; no target-process audio-consumption proof.
- B8: UNKNOWN for gesture interval.
- B9: BROKEN at user-visible level; no machine-readable external semantic observer.

## Current conclusion

Evidence does not support LONG-as-SHORT misclassification, a RemoteOrbit persistent toggle during LONG, or a correlated mapped-trigger replay as the direct close mechanism. The failure is localized to the handoff between RemoteOrbit's preserved internal persistent-open state and the external IME/session semantics, but the exact mechanism remains unknown.

Only minimal diagnostic gap closure at B4/B5-external/B9 is authorized next. No threshold, gate, trigger, BLE/audio, or persistent-session behavior change is authorized.

```text
ALLOWED_NEXT_WORK: MINIMAL DIAGNOSTIC BOUNDARY-GAP CLOSURE ONLY
ROOT_CAUSE: UNKNOWN
PRODUCT_CONSTRUCTION_GATE: BLOCKED
```
