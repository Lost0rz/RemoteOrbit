# CURRENT_STATUS

Last updated: 2026-10-06
State: ACTIVE INCIDENT — B4 EXTERNAL EVENT-PLANE VERIFICATION AUTHORIZED / PRODUCT CONSTRUCTION BLOCKED
Repository: `Lost0rz/RemoteOrbit`

This file is the authority for mutable current project state. Historical detail remains preserved in Git history.

## Control-plane integrity

- Previous authoritative HEAD: `fddcbb7dd2985967cf8d9741c229888d0c0a06c2`.
- P0-A passive external semantic-signal feasibility is CLOSED as `UNOBSERVABLE`.
- Network recovery was independently re-tested on the owning Mac using DNS, HTTPS, `git ls-remote`, real `git fetch`, and three repeated rounds; the current network blocker is CLEARED for the tested environment.
- The old canonical checkout at `/Volumes/Jack-Dev/Projects/RemoteOrbit` is not an execution authority for this task. It is on superseded branch `codex/v0211-nonseize-hid-audit`, is far behind `origin/main`, and contains a non-unique historical `HIDMonitor.swift` edit whose effective behavior already exists in main history. Do not reset, stash, clean, or reuse it for B4.

## Foundation

- Lane A governance: CLOSED.
- PR #18 boundary probes: MERGED + CLOSED.
- PR #19 DiagnosticAuthority: MERGED + CLOSED.
- PR #20 read-only Diagnostic CLI v1: MERGED + CLOSED.
- Product fix construction: BLOCKED.

## Active incident

```text
INCIDENT_ID: RO-INCIDENT-20261004-01
EXPECTED: SHORT opens persistent session; LONG while open is audio-only and must leave it open.
OBSERVED: user confirmed external Doubao IME session exits after LONG.
BOUND_SHORT_GESTURE_ID: 9D7DDD10-95CD-4494-A73C-C09923D6A6D4
BOUND_LONG_GESTURE_ID: 05DE2189-B9AA-4B05-9385-46CD3667E3D5
INTERNAL_STATE_EXTERNAL_STATE_DIVERGENCE: YES
FIRST_CONFIRMED_BROKEN_BOUNDARY: B5 external semantic state
EXTERNAL_EXIT_MECHANISM: UNKNOWN
ROOT_CAUSE: UNKNOWN
PRODUCT_CONSTRUCTION_GATE: BLOCKED
```

Correlated internal facts remain:

```text
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

## P0-A disposition

```text
P0A_SIGNAL_FEASIBILITY_IN_CODEX_EXECUTOR: UNOBSERVABLE
P0A_SIGNAL_FEASIBILITY_ON_HOST: UNOBSERVABLE
VERIFIED_EXTERNAL_SIGNAL: NONE
NEW_PROBE_IMPLEMENTED: NO
```

No further AX/text/focus proxy instrumentation is justified under P0-A.

## Current boundary disposition

- B1: OBSERVED.
- B2: OBSERVED.
- B3: OBSERVED; bound LONG has no correlated mapped trigger and `trigger_edge_emitted=false`.
- B4: ACTIVE INVESTIGATION.
  - B4a: whether a LONG-correlated Option/Control/key/flagsChanged or equivalent trigger-like event is visible on the macOS external/session event plane after leaving RemoteOrbit's internal trigger-intent boundary.
  - B4b: whether Doubao specifically accepted such an event remains UNKNOWN unless an independent receiver acknowledgement exists. B4a observation alone must not be promoted to receiver acceptance.
- B5 internal: OBSERVED / preserved.
- B5 external: BROKEN at user-confirmed semantic level; passive semantic state is unobservable on inspected supported surfaces.
- B6: OBSERVED.
- B7: UNKNOWN; no target-process audio-consumption proof.
- B8: UNKNOWN for the gesture interval.
- B9: BROKEN at user-visible semantic level; passive semantic transition timestamp unavailable.

## Authorized B4 diagnostic authority

```text
AUTHORIZED_BRANCH: codex/b4-external-event-plane-verification
PLANNED_WORKTREE: /private/tmp/remoteorbit-b4-external-event-plane-verification
BASE_PARENT: fddcbb7dd2985967cf8d9741c229888d0c0a06c2
SINGLE_ACTIVE_DIAGNOSTIC_SCOPE: B4 external event-plane verification
PRODUCT_BEHAVIOR_CHANGE: FORBIDDEN
RELEASE_OR_INSTALL: FORBIDDEN
NETWORK_REPAIR_WORK: CLOSED
OLD_CANONICAL_CHECKOUT_MUTATION: FORBIDDEN
```

## B4 construction gate

The first B4 phase is source/evidence audit plus the smallest sufficient passive observation path.

Allowed:

1. create one clean worktree from the authoritative B4 branch after live ref verification;
2. inspect existing boundary probes, event taps, HID/key mapping, EventSuppressor and DiagnosticAuthority paths read-only;
3. determine whether existing instrumentation can already observe the external/session event plane independently of RemoteOrbit trigger intent;
4. only if existing instrumentation is insufficient, implement the smallest standalone/listen-only diagnostic observer required to distinguish event-plane presence from absence;
5. add focused tests for the observer's non-mutating/transition-recording contract;
6. commit and push only diagnostic-source/test/control changes on the authorized B4 branch.

Not yet allowed:

- no user SHORT/LONG reproduction;
- no runtime install/replacement;
- no event injection, replay or synthesis;
- no product behavior change;
- no TCC/settings/driver/CoreAudio mutation;
- no claim of Doubao receiver acceptance from a generic event-plane observation.

## Acceptance for first B4 phase

Return one of:

```text
B4_EXISTING_OBSERVER_SUFFICIENT: YES
```

with exact evidence path and semantics, or:

```text
B4_MINIMAL_PASSIVE_OBSERVER_IMPLEMENTED: YES
```

with focused tests and proof that it is listen-only/non-mutating.

In either case, stop before live reproduction at:

```text
WAITING_FOR_INDEPENDENT_WEB_B4_IMPLEMENTATION_AUDIT
```

Root cause remains UNKNOWN until a later controlled capture provides evidence.
