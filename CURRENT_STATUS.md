# CURRENT_STATUS

Last updated: 2026-10-05
State: ACTIVE INCIDENT — P0-A EXTERNAL IME OBSERVER REQUIRED / DIAGNOSTIC CONSTRUCTION AUTHORIZED / LOCAL GATE 0 NETWORK BLOCKED / PRODUCT CONSTRUCTION BLOCKED
Repository: `Lost0rz/RemoteOrbit`

This file is the authority for mutable current project state. Historical detail remains preserved in Git history.

## Control-plane integrity

- Commit `b43a0eb8c9fa21bb869ea1d9177ad96acd8f699d` updated `CURRENT_STATUS.md` without the matching `CURRENT_TASK.md` transition and is therefore a non-authoritative partial transition under `AGENTS.md`.
- Commit `6561d8ac14b3de9478f414719877d853e86e434a` atomically updated STATUS + TASK and is the authoritative P0-A authorization baseline.

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

## Local Gate 0 network blocker

The owning Mac cannot currently satisfy repository freshness requirements because GitHub hostname resolution is intermittent.

Accepted network facts:

```text
SYSTEM_RESOLVER_GITHUB: intermittent / currently failing
PYTHON_GETADDRINFO_GITHUB: intermittent / currently failing
CURL_GITHUB: previously HTTP/2 200, later Could not resolve host
CURL_API_GITHUB: previously HTTP/2 200, later Could not resolve host
GIT_LS_REMOTE: failed on github.com name resolution
PROXY_ENV: none
SYSTEM_PROXY: none
GIT_PROXY_OR_URL_REWRITE: none found
CURL_WRAPPER: none; /usr/bin/curl
NETWORK_PATH_SPLIT: NOT CONFIRMED
```

The strongest supported explanation is intermittent DNS/resolver behavior, not a proven curl-vs-Git proxy split. `scutil --dns` showed tunnel and physical interfaces with different resolver configuration, but no specific resolver has yet been proven causal.

Local construction MUST remain stopped at Gate 0 until a successful live `git fetch origin --prune` verifies both `origin/main` and the authorized branch. Cached refs must not substitute for remote freshness.

## Independent audit conclusion

The current evidence is sufficient to authorize **diagnostic construction only** for a minimal P0-A external IME semantic-session observer feasibility/probe task. Product behavior repair remains blocked.

The task must first identify and verify a genuine external-origin semantic signal. If no such signal is available from supported passive OS/AX/process/unified-log surfaces, the probe must fail closed as `UNOBSERVABLE`; it must not infer IME state from focus, text change, RemoteOrbit state, trigger intent, or audio lifecycle.

Required probe contract:

- external to RemoteOrbit persistent-session state;
- read-only with respect to IME and target application;
- transition-only;
- records only externally supported `OPEN/LISTENING`, `STOPPED/CLOSED`, `UNKNOWN/ERROR/UNOBSERVABLE` transitions;
- wall clock plus a declared monotonic clock suitable for correlation;
- observer PID/executable identity;
- external IME process/bundle/PID or other verified stable target identity;
- explicit run/correlation identifier;
- stores no plaintext text and no deterministic text-derived hashes;
- no HID/BLE/PCM/AudioPipe expansion;
- no RemoteOrbit product behavior change.

```text
AUTHORIZED_DIAGNOSTIC_BRANCH: codex/p0a-external-ime-observer-minimal
ALLOWED_NEXT_WORK_AFTER_GATE0: P0-A SIGNAL FEASIBILITY + MINIMAL DIAGNOSTIC PROBE ONLY
LOCAL_GATE_0: BLOCKED_BY_INTERMITTENT_GITHUB_DNS
PRODUCT_BEHAVIOR_CHANGE: FORBIDDEN
ROOT_CAUSE: UNKNOWN
PRODUCT_CONSTRUCTION_GATE: BLOCKED
```
