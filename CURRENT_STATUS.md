# CURRENT_STATUS

Last updated: 2026-10-05
State: ACTIVE INCIDENT — P0-A EXTERNAL IME OBSERVER REQUIRED / DIAGNOSTIC CONSTRUCTION AUTHORIZED / PRODUCT CONSTRUCTION BLOCKED
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
INTENDED_REPRO_BINDING: CONFIRMED
BOUND_SHORT_GESTURE_ID: 9D7DDD10-95CD-4494-A73C-C09923D6A6D4
BOUND_LONG_GESTURE_ID: 05DE2189-B9AA-4B05-9385-46CD3667E3D5
ROOT_CAUSE: UNKNOWN
PRODUCT_CONSTRUCTION_GATE: BLOCKED
```

Correlated internal facts:

```text
SHORT_INTERNAL: idle -> persistent_open
LONG_CLASSIFICATION: hold (313 ms)
REMOTE_SEGMENT_POLICY: audio_only
PERSISTENT_MODE_BEFORE_LONG: persistent_open
PERSISTENT_MODE_AFTER_LONG: persistent_open
MAPPED_TRIGGER_DURING_LONG: none correlated
SHORT_REPLAY_DURING_LONG: none observed
PERSISTENT_TOGGLE_DURING_LONG: none observed
PERSISTENT_SEGMENT_COMPLETE: session_remains_open=true
USER_VISIBLE_EXTERNAL_RESULT: session exited
```

## Boundary disposition

- B1: OBSERVED.
- B2: OBSERVED.
- B3: OBSERVED; bound LONG has no correlated mapped trigger and `trigger_edge_emitted=false`.
- B4: UNKNOWN; no external IME trigger-receipt acknowledgement.
- B5 internal: OBSERVED / preserved; RemoteOrbit remains `persistent_open`.
- B5 external: BROKEN; user-confirmed external session exit while internal state remains open.
- B6: OBSERVED.
- B7: UNKNOWN; no target-process audio-consumption proof.
- B8: UNKNOWN for gesture interval.
- B9: BROKEN at user-visible semantic level; no machine-readable external semantic session timestamp.

## P0-A existing observer audit

The existing local `RemoteOrbit P1A5 Observer.app` is **not sufficient** for P0-A.

Accepted local audit facts:

```text
OBSERVER_BUNDLE_ID: com.lost0rz.RemoteOrbit.P1A5Observer
OBSERVER_SHA256: d71af5e7d51e935b4cf62516283a44167457cf1d71139236f47d99c87ec43e26
EXISTING_OBSERVER_P0A_SUFFICIENT: NO
OBSERVES_IME_SESSION_OPEN: NO
OBSERVES_IME_SESSION_CLOSE: NO
OBSERVES_VOICE_LISTENING_STATE: NO
SOURCE_PROVENANCE: candidate source found, exact binary-to-source mapping unverified
SOURCE_TREE_STATE: untracked candidate source
```

The observer reads generic frontmost/focused-element AX state and text-derived length/hash data. It does not observe an external-origin Doubao session state machine. Existing JSONL `persistent_session_*` fields are RemoteOrbit internal state, not external IME truth. The source app also lacks a verified monotonic timestamp contract; legacy JSONL monotonic/uptime field provenance is unverified.

## Independent audit conclusion

The current evidence is sufficient to authorize **diagnostic probe construction only** for one minimal P0-A external IME semantic-session observer. Product behavior repair remains blocked.

Required probe contract:

- external to RemoteOrbit persistent-session state;
- read-only with respect to IME and target application;
- transition-only;
- records only externally supported `OPEN/LISTENING`, `STOPPED/CLOSED`, `UNKNOWN/ERROR` transitions;
- wall clock plus a declared monotonic clock suitable for correlation;
- observer PID/executable identity;
- external IME process/bundle/PID or other verified stable target identity;
- explicit run/correlation identifier;
- stores no plaintext text and no deterministic text-derived hashes unless strictly required by the external signal contract;
- never infers IME semantic state from focus changes, target text changes, RemoteOrbit internal mode, trigger intent, or audio lifecycle alone;
- if no verified external semantic signal is technically available, the implementation must fail closed as `UNOBSERVABLE` rather than fabricate state.

```text
ALLOWED_NEXT_WORK: P0-A MINIMAL DIAGNOSTIC PROBE CONSTRUCTION ONLY
PRODUCT_BEHAVIOR_CHANGE: FORBIDDEN
ROOT_CAUSE: UNKNOWN
PRODUCT_CONSTRUCTION_GATE: BLOCKED
```
