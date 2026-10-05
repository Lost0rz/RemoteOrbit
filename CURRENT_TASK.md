# RemoteOrbit Current Task

## Current task — RO-INCIDENT-20261004-01 / P0-A EXTERNAL IME SEMANTIC OBSERVER

- **Status:** AUTHORIZED / DIAGNOSTIC CONSTRUCTION ONLY
- **Incident ID:** `RO-INCIDENT-20261004-01`
- **Control-plane base before authorization:** `b43a0eb8c9fa21bb869ea1d9177ad96acd8f699d`
- **Authorized branch:** `codex/p0a-external-ime-observer-minimal`
- **Installed runtime source:** `77812cb1ccab051aca0e7d79b82f2db309074775`
- **Product Construction Gate:** BLOCKED
- **Product behavior mutation:** FORBIDDEN
- **Release/install/runtime replacement:** NOT AUTHORIZED
- **User reproduction:** NOT AUTHORIZED until probe audit passes

## Accepted evidence

The exact-main controlled reproduction is uniquely bound:

```text
SHORT_GESTURE_ID: 9D7DDD10-95CD-4494-A73C-C09923D6A6D4
LONG_GESTURE_ID: 05DE2189-B9AA-4B05-9385-46CD3667E3D5
LONG_CLASSIFICATION: hold (313 ms)
REMOTE_SEGMENT_POLICY: audio_only
PERSISTENT_MODE_BEFORE_LONG: persistent_open
PERSISTENT_MODE_AFTER_LONG: persistent_open
MAPPED_TRIGGER_DURING_LONG: none correlated
SHORT_REPLAY_DURING_LONG: none observed
PERSISTENT_TOGGLE_DURING_LONG: none observed
PERSISTENT_SEGMENT_COMPLETE: session_remains_open=true
USER_VISIBLE_EXTERNAL_RESULT: SESSION_EXITED
```

Therefore `INTERNAL_STATE_EXTERNAL_STATE_DIVERGENCE = YES`. The first confirmed broken boundary is the external B5 semantic state boundary. The exit mechanism remains UNKNOWN.

## Existing-observer audit

The local `RemoteOrbit P1A5 Observer.app` is not sufficient for P0-A:

- it observes generic `NSWorkspace`/Accessibility focus and focused-element value changes;
- it does not observe Doubao IME session OPEN/LISTENING or STOPPED/CLOSED;
- legacy `persistent_session_*` fields reflect RemoteOrbit internal state, not external truth;
- its source provenance is not bound to the installed binary;
- its source lacks a verified monotonic clock contract;
- it reads text values and persists deterministic hashes/lengths, which are unnecessary for the P0-A contract.

## Objective

Build the smallest diagnostic-only capability that can machine-observe the external IME semantic transition relevant to this incident.

The task has two gates:

### Gate 1 — external signal feasibility

Before writing a semantic observer, identify a passive external-origin signal that genuinely represents Doubao voice-session state.

Allowed read-only surfaces include, when available and privacy-safe:

- Doubao/IME process and accessibility state;
- OS/unified-log state exposed by the IME or relevant system service;
- process/window/UI attributes that directly encode voice-session/listening state;
- other passive system APIs that do not mutate the IME or target application.

A signal is valid only if its semantics can be demonstrated as external session state, rather than inferred from:

- RemoteOrbit `persistent_open`;
- trigger send/success intent;
- focus changes alone;
- text/value changes alone;
- audio/BLE/ATVV lifecycle alone;
- file-write ordering.

If no verified external semantic signal is available, STOP with:

```text
P0A_SIGNAL_FEASIBILITY: UNOBSERVABLE
NEW_PROBE_IMPLEMENTED: NO
PRODUCT_CONSTRUCTION_GATE: BLOCKED
```

Do not manufacture a proxy state.

### Gate 2 — minimal transition-only probe

Only if Gate 1 identifies a verified external-origin signal, implement a standalone diagnostic observer on the authorized branch.

Required output contract:

```text
run_id
observer_pid
observer_executable_sha256
wall_clock
monotonic_timestamp
monotonic_clock_domain
target_pid
target_bundle_id
external_signal_source
external_session_state = OPEN | LISTENING | STOPPED | CLOSED | UNKNOWN | ERROR
transition_reason_or_signal
```

Requirements:

- read-only toward Doubao/IME and target application;
- transition-only output, not polling-volume logging;
- no plaintext text content;
- no deterministic text-derived hashes;
- explicit `UNKNOWN/ERROR/UNOBSERVABLE` fail-closed semantics;
- declared wall-clock and monotonic clock domains;
- stable observer and target identity;
- no dependency on RemoteOrbit internal state to determine the external state;
- no event injection, focus change, IME control, settings change, or accessibility mutation.

## Scope

Allowed source changes are limited to the standalone P0-A diagnostic helper, its focused tests, minimal build wiring needed to compile/run that helper, and diagnostic documentation required to state its schema and limitations.

Do not modify:

- SHORT/LONG classifier;
- `VoicePressCoordinator` behavior;
- `HardwareOptionGate` behavior;
- mapped trigger behavior;
- BLE/ATVV behavior;
- `AudioPipe` behavior;
- persistent-session semantics;
- app install/release behavior;
- driver/CoreAudio/TCC/settings.

Do not migrate unrelated producers into `DiagnosticAuthority` in this task.

## Validation

Before handoff, require:

1. exact branch/head/worktree identity and clean baseline;
2. focused tests proving transition deduplication and fail-closed UNKNOWN/UNOBSERVABLE behavior;
3. privacy test proving no plaintext or deterministic text-derived hashes are persisted;
4. read-only audit proving no event injection/state mutation paths exist;
5. `swift test` and `git diff --check` PASS if package wiring is touched;
6. no app installation, runtime replacement, driver/CoreAudio/TCC/settings mutation;
7. a machine-readable sample using synthetic/test signal input only unless a later control-plane transition explicitly authorizes a live reproduction.

## Handoff gate

Return at `WAITING_FOR_INDEPENDENT_WEB_P0A_IMPLEMENTATION_AUDIT` with:

```text
CONTROL_HEAD:
BRANCH:
BASE_HEAD:
FINAL_HEAD:
WORKTREE:

P0A_SIGNAL_FEASIBILITY:
VERIFIED_EXTERNAL_SIGNAL:
SIGNAL_SEMANTICS_EVIDENCE:

NEW_PROBE_IMPLEMENTED:
PROBE_PATH:
OUTPUT_SCHEMA:
CLOCK_DOMAIN:
TARGET_IDENTITY:
FAIL_CLOSED_BEHAVIOR:

FOCUSED_TESTS:
FULL_SWIFT_TEST:
DIFF_CHECK:
PRIVACY_TEST:
READ_ONLY_AUDIT:

PRODUCT_SOURCE_BEHAVIOR_CHANGED: NO
RUNTIME_MUTATIONS: NONE
USER_REPRODUCTION_PERFORMED: NO
ROOT_CAUSE: UNKNOWN
PRODUCT_CONSTRUCTION_GATE: BLOCKED

FINAL_STATE:
WAITING_FOR_INDEPENDENT_WEB_P0A_IMPLEMENTATION_AUDIT
```
