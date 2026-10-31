# CURRENT_STATUS

Last updated: 2026-10-31
State: `RO-IME-READINESS-PROMPT-SYNC-043 — MEMORY_STABILITY_CORRECTIVE_AUTHORIZED`
Repository: `Lost0rz/RemoteOrbit`
Active branch: `main` control authority; implementation branch to use `codex/ime-readiness-stability-043`
Merged product baseline: `8b76ee336d36e9dd58d072bd5ab1dae208b3a77f`
Current main/control parent: `5144678bb529a2128e53f4eb285d752cdf45473a`
Corrective design authority: `docs/design/2026-10-31-043-receiver-readiness-stability-corrective.md`

## Runtime incident

Human acceptance of the merged 0.2.15 Task 043 candidate is BLOCKED by an established memory/CPU regression in `VoiceReceiverReadinessObserver`.

Frozen PID 14011 evidence:

- physical footprint about 6.0 GB;
- default malloc zone about 6.4 GB / about 127.55 million allocations;
- `Malloc Small` about 5.2 GB and `Malloc Large` about 0.8 GB;
- CPU roughly 100-170% during the capture;
- readiness queue active in 1848/1848 samples;
- 877 samples in `AudioObjectAddPropertyListenerBlock` via `installProcessListeners`;
- 816 samples in `AudioObjectRemovePropertyListenerBlock` via `removeProcessListeners`;
- Core Audio HAL listener queue simultaneously saturated by property/listener work;
- RemoteOrbit became unresponsive and the remote-button path stopped responding.

Root-cause status: `ESTABLISHED` for a listener-refresh/callback-amplification storm. The current implementation rebuilds the full Core Audio process-listener graph from property callbacks, creating unbounded listener/dispatch churn. The icon, log volume, and AudioPipe buffering are not supported as the source of this incident.

## Selected corrective architecture

Replace the persistent Core Audio listener graph with a session-scoped snapshot sampler:

- zero Core Audio process property listeners in the readiness path;
- one private serial queue;
- at most one timer while the HUD needs receiver truth;
- immediate sample on activation plus nominal 100 ms bounded sampling while active;
- zero readiness timer/background sampling when idle/draining;
- synchronous read-only Core Audio snapshots only;
- fail-closed non-green state on unavailable/partial reads;
- no readiness influence on BLE, AudioPipe, HID, trigger timing, admission, cooldown, retry, or Task 042 transport ownership.

The previous anti-polling boundary is superseded specifically for this evidence-driven architectural replacement. This is not authorization for generic timers elsewhere.

## Accepted limitation unchanged

The owner still accepts the existing rapid-double-press edge: if Doubao is still post-processing the previous external IME session, RemoteOrbit may truthfully reflect the physical press while Doubao does not reopen. No cooldown/retry/state-machine optimization is requested for that edge.

## Release/runtime status

The existing 0.2.15 (44) App/DMG is NOT accepted for continued use because of the memory incident. Do not tag/publish it. Do not treat prior startup/package verification as runtime acceptance.

Task 042 remains CLOSED and frozen.

## Next

Implement the bounded Task 043 readiness-stability corrective on `codex/ime-readiness-stability-043`, run source/regression verification, push and stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`. No package/install/runtime replacement before that source audit.
