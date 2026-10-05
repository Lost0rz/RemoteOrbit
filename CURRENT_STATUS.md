# CURRENT_STATUS

Last updated: 2026-10-05
State: ACTIVE INCIDENT — P0-A HOST-NATIVE FEASIBILITY REQUIRED / PRODUCT CONSTRUCTION BLOCKED
Repository: `Lost0rz/RemoteOrbit`

This file is the authority for mutable current project state. Historical detail remains preserved in Git history.

## Control-plane integrity

- Commit `b43a0eb8c9fa21bb869ea1d9177ad96acd8f699d` is a non-authoritative partial transition because it changed STATUS without the matching TASK.
- Commit `6561d8ac14b3de9478f414719877d853e86e434a` atomically authorized the P0-A diagnostic task.
- Commit `2d6a89ea83a61c6b134db17f7330b5d0d8b89049` recorded a local executor network blocker that has since been superseded by a successful operator Terminal fetch.

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
- B3: OBSERVED.
- B4: UNKNOWN; no external IME trigger-receipt acknowledgement.
- B5 internal: OBSERVED / preserved.
- B5 external: BROKEN; user-confirmed external session exit while internal state remains open.
- B6: OBSERVED.
- B7: UNKNOWN; no target-process audio-consumption proof.
- B8: UNKNOWN for gesture interval.
- B9: BROKEN at user-visible semantic level; no machine-readable external semantic timestamp.

## Existing observer audit

The local `RemoteOrbit P1A5 Observer.app` is not sufficient for P0-A. It observes generic NSWorkspace/Accessibility focus and text-derived metadata but not external Doubao OPEN/LISTENING/STOPPED/CLOSED state. Existing `persistent_session_*` fields are RemoteOrbit internal truth, not external IME truth.

## Gate 0 network disposition

The earlier Codex executor DNS failure is not an owning-Mac freshness blocker.

The user successfully ran in the owning Mac Terminal:

```text
git fetch origin --prune
origin/main = 2d6a89ea83a61c6b134db17f7330b5d0d8b89049
origin/codex/p0a-external-ime-observer-minimal = 2d6a89ea83a61c6b134db17f7330b5d0d8b89049
```

Therefore the previous Gate 0 freshness requirement was satisfied. The executor's DNS/network environment must be treated separately from host Terminal network state.

## P0-A executor feasibility result

A clean isolated worktree was created on the authorized branch at exact base `2d6a89ea83a61c6b134db17f7330b5d0d8b89049`. No source changes were made.

The executor returned:

```text
P0A_SIGNAL_FEASIBILITY_IN_CODEX_EXECUTOR: UNOBSERVABLE
NEW_PROBE_IMPLEMENTED: NO
SOURCE_CHANGES: NONE
RUNTIME_MUTATIONS: NONE
USER_REPRODUCTION_PERFORMED: NO
```

This does **not** establish that Doubao has no externally observable semantic session signal. The feasibility attempt was constrained by executor/sandbox limitations:

- process listing was denied;
- `log show` / Unified Log inspection was blocked by sandbox policy;
- Accessibility trust in the executor was false;
- no verified external semantic signal could be established from the remaining surfaces.

The installed Doubao bundle contains InputMethodKit connection metadata and internal ASR/session symbols, but those facts alone do not constitute an externally consumable session-state signal.

## Independent audit conclusion

The next allowed action is **host-native read-only feasibility only**. Use the owning Mac's normal Terminal environment to inspect passive external surfaces that were unavailable to the executor. Do not implement a probe yet.

```text
AUTHORIZED_DIAGNOSTIC_BRANCH: codex/p0a-external-ime-observer-minimal
P0A_SIGNAL_FEASIBILITY_IN_CODEX_EXECUTOR: UNOBSERVABLE
P0A_SIGNAL_FEASIBILITY_ON_HOST: NOT_YET_ASSESSED
ALLOWED_NEXT_WORK: HOST-NATIVE READ-ONLY P0-A SIGNAL FEASIBILITY
NEW_PROBE_IMPLEMENTATION: BLOCKED UNTIL HOST SIGNAL VERIFIED
PRODUCT_BEHAVIOR_CHANGE: FORBIDDEN
ROOT_CAUSE: UNKNOWN
PRODUCT_CONSTRUCTION_GATE: BLOCKED
```
