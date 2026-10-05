# RemoteOrbit Current Task

## Current task — RO-INCIDENT-20261004-01 / P0-A HOST-NATIVE EXTERNAL SIGNAL FEASIBILITY

- **Status:** ACTIVE / READ-ONLY HOST FEASIBILITY
- **Incident ID:** `RO-INCIDENT-20261004-01`
- **Authorized diagnostic branch:** `codex/p0a-external-ime-observer-minimal`
- **Product Construction Gate:** BLOCKED
- **Probe implementation:** NOT AUTHORIZED until host-native signal verification succeeds
- **Product behavior mutation:** FORBIDDEN
- **Release/install/runtime replacement:** NOT AUTHORIZED
- **User reproduction:** NOT AUTHORIZED

## Accepted facts

The bound exact-main incident shows:

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

Internal/external state divergence is confirmed. External exit mechanism remains UNKNOWN.

## Gate 0 disposition

The user successfully performed a live owning-Mac Terminal fetch and verified both remote-tracking refs at `2d6a89ea83a61c6b134db17f7330b5d0d8b89049`. Gate 0 freshness is therefore satisfied. Codex executor DNS failures are an executor-environment limitation, not proof that the owning Mac is offline.

## Executor feasibility disposition

The authorized clean worktree at `/private/tmp/remoteorbit-p0a-external-ime-observer` remained unchanged. The executor found no verified external semantic signal and correctly stopped without implementing a proxy observer.

Treat the result as:

```text
P0A_SIGNAL_FEASIBILITY_IN_CODEX_EXECUTOR: UNOBSERVABLE
P0A_SIGNAL_FEASIBILITY_ON_HOST: NOT_YET_ASSESSED
```

Why it is not a global `UNOBSERVABLE` conclusion:

- process enumeration was denied in the executor;
- Unified Log `log show` was sandbox-blocked;
- executor Accessibility trust was false;
- no live external semantic signal could be verified from the remaining surfaces.

## Objective

Determine, from the owning Mac's normal Terminal environment, whether a passive external-origin signal exists that genuinely represents Doubao voice-session state.

### Allowed host-native read-only surfaces

- process identity and lifecycle (`ps`, `pgrep`, `launchctl print` read-only queries);
- installed bundle metadata, Info.plist, symbols/strings already present on disk;
- `log show` / `log stream` read-only inspection of relevant Doubao/InputMethodKit/system-service messages;
- read-only Accessibility inspection if the querying host process already has permission;
- window/UI attributes that directly encode a voice-session/listening state;
- passive OS APIs that do not mutate IME or target state.

### Invalid semantic proxies

Do not treat any of these as session truth by themselves:

- RemoteOrbit `persistent_open`;
- trigger send/success intent;
- focus changes alone;
- target text/value changes alone;
- BLE/ATVV/audio lifecycle alone;
- presence of internal ASR/session symbols in the binary;
- file-write order.

### Valid host signal standard

A signal is `VERIFIED` only if all are satisfied:

1. it originates outside RemoteOrbit;
2. its semantics can be tied directly to Doubao voice-session/listening state;
3. it can distinguish an active/open/listening state from stopped/closed, or expose a documented state transition equivalent;
4. it is passively readable without injecting events or changing IME state;
5. its source process/service identity can be recorded;
6. its timing can be machine recorded with wall clock and, where possible, a declared monotonic source.

If no such signal can be established from the host environment, stop with:

```text
P0A_SIGNAL_FEASIBILITY_ON_HOST: UNOBSERVABLE
NEW_PROBE_IMPLEMENTED: NO
ROOT_CAUSE: UNKNOWN
PRODUCT_CONSTRUCTION_GATE: BLOCKED
```

Do not manufacture a proxy state.

## Forbidden

- no source changes;
- no new probe implementation;
- no user SHORT/LONG reproduction;
- no restart/reinstall;
- no TCC/Accessibility permission changes;
- no driver/CoreAudio/settings mutation;
- no event injection or IME control;
- no speculative product fix.

## Handoff

Return:

```text
CONTROL_HEAD:
HOST_NATIVE_AUDIT_ENVIRONMENT:

DOUBAO_PROCESS_FOUND:
DOUBAO_PID:
DOUBAO_BUNDLE_ID:

HOST_PROCESS_ENUMERATION:
HOST_UNIFIED_LOG_ACCESS:
HOST_ACCESSIBILITY_READ_ACCESS:

EXTERNAL_SIGNAL_CANDIDATES:

P0A_SIGNAL_FEASIBILITY_ON_HOST:
VERIFIED_EXTERNAL_SIGNAL:
SIGNAL_SOURCE:
SIGNAL_SOURCE_IDENTITY:
SIGNAL_SEMANTICS_EVIDENCE:
SIGNAL_ACTIVE_STATE:
SIGNAL_STOPPED_STATE:
WALL_CLOCK_AVAILABLE:
MONOTONIC_CLOCK_AVAILABLE:

WHY_NOT_PROXY:

NEW_PROBE_IMPLEMENTED: NO
SOURCE_CHANGES: NONE
RUNTIME_MUTATIONS: NONE
USER_REPRODUCTION_PERFORMED: NO
ROOT_CAUSE: UNKNOWN
PRODUCT_CONSTRUCTION_GATE: BLOCKED

FINAL_STATE:
WAITING_FOR_INDEPENDENT_WEB_HOST_P0A_FEASIBILITY_AUDIT
```
