# RemoteOrbit Current Task

## RO-AUDIO-CONTINUITY-DIAGNOSTIC-049 — Resolve sustained PCM supply-deficit boundary

Status: `ACTIVE / WAITING_FOR_FRESH_HARDWARE_CAPTURE`
TASK_CLASS: `DIAGNOSTIC / OBSERVABILITY`
Repository: `Lost0rz/RemoteOrbit`
Control authority: `main`
Implementation branch: `codex/audio-continuity-diagnostic-049`
Implementation HEAD: `1d6370cb9a9bfa1f1d8bff10095f149fefe89288`
Draft PR: `#40`
Exact-head CI: `41628598574 — SUCCESS`

## Objective

Determine whether the confirmed RC003 decoded-PCM supply deficit is caused by local BLE audio-handler service latency, sustained effective source-clock mismatch, or episodic upstream / BLE delivery starvation, without changing product audio behavior before causal evidence exists.

ROOT_CAUSE_STATUS: `UNKNOWN`

## Completed remote scope

Probe A — BLE handler service time:
- exact `handleAudio` entry/exit monotonic timing;
- fixed 0.25 ms histogram plus scalar counters;
- session-end count, p50/p95/p99/max, and >5/>10/>15 ms summary;
- no per-packet logging or unbounded per-packet collection.

Probe B — decoded supply-rate windows:
- read-only analysis of existing persisted continuity trace;
- approximately one-second windows with decoded sample count, effective source Hz, notification count/max gap and AudioPipe queue-depth start/end when retained;
- incomplete bounded-trace windows are explicitly marked non-contiguous and do not expose an authoritative source-Hz value;
- read-only CLI entry: `RemoteOrbit diagnostics audio-continuity --session <id>`.

Verification:
- exact implementation HEAD: `1d6370cb9a9bfa1f1d8bff10095f149fefe89288`;
- Draft PR #40 remains OPEN / DRAFT / UNMERGED;
- CI run `41628598574`: SUCCESS;
- Full Swift tests: 513 / 513 PASS;
- Native Release build: PASS;
- build-only packaging smoke: PASS;
- exact-diff audit: PASS;
- no product audio behavior change found outside the authorized diagnostic boundary.

## Current required action — fresh hardware capture

Run a fresh local RC003 voice capture from the instrumented Task 049 build. This is now the only evidence-producing action required before choosing a corrective architecture.

Capture requirements:
1. Diagnostic logging / DiagnosticAuthority capture is enabled so `voice.session.summary` and `voice.session.trace` are persisted for Probe B.
2. Exercise several ordinary short phrases and several longer holds that previously exposed continuity loss.
3. Preserve the normal RemoteOrbit runtime log containing `[AUDIO-PATH] BLE_HANDLER_SUMMARY ... metric=handler_service_time`.
4. Preserve the affected session IDs and obtain the read-only report with `RemoteOrbit diagnostics audio-continuity --session <id>` for those sessions.
5. Do not change reserve, prebuffer, resampling, drain, keepalive, decoder or HID/Option behavior during the capture.

## Decision rules after capture

- Material handler p95/p99/max or repeated >15 ms service events correlated with starvation keeps local BLE callback work in the causal boundary.
- Low handler service time plus multiple contiguous windows persistently below nominal 16 kHz supports source-clock mismatch / clock-recovery investigation.
- Low handler service time plus mostly nominal windows with isolated low-rate windows and large notification gaps supports episodic upstream transport starvation.
- Any `trace_contiguous=false` window is excluded from source-Hz causal claims.

These are diagnostic decision rules, not pre-authorized fixes.

## Forbidden until fresh evidence is reviewed

Do not change:
- ADPCM decode or ATVV frame size;
- playout reserve;
- prebuffer;
- resampling ratio / adaptive clock recovery;
- packet-loss concealment;
- AUDIO_STOP drain / post-release grace;
- keepalive;
- HID/Option lifecycle;
- packaging / release version;
- installed driver, CoreAudio, TCC or default devices.

Do not merge PR #40 or publish a release under this task state.

## STOP

`WAITING_FOR_FRESH_HARDWARE_CAPTURE`

After fresh RC003 evidence is collected, return for read-only causal classification. Any corrective implementation requires a subsequent governed transition after that evidence is reviewed.

DOCUMENT_ALIGNMENT: `TASK_049_WAITING_FOR_FRESH_HARDWARE_CAPTURE`
