# CURRENT_STATUS

Last updated: 2026-10-31
State: `RO-DIAGNOSTICS-LEGACY-RETIREMENT-045 — WAVE_A_READY_FOR_IMPLEMENTATION_HANDOFF`
Repository: `Lost0rz/RemoteOrbit`
Audited source authority: `main@650a2c011bb640379842ab866d696302c4adc52e`
Task 043: `MERGED / HUMAN_ACCEPTANCE_DEFERRED / USER-OWNED`
Task 045 overall: `ACTIVE`
Task 045A: `DIAGNOSTICS_GATING / READY_FOR_IMPLEMENTATION_HANDOFF`

## Accepted design

Durable Task 045 design authority:

`docs/design/2026-10-31-045-diagnostics-gating-and-legacy-retirement.md`

The audit found no unresolved classification that blocks Wave A.

### Diagnostics facts

- ordinary `RemoteOrbit.log` already has an effective disabled fast path;
- `VoiceDiagnosticLogger`, `DiagnosticAuthority`, runtime-health heartbeat, voice-start diagnostic watchdog, long-term observability, and `AudioPipe` per-session diagnostic probes currently perform work outside the ordinary logging toggle;
- WAV/RAW recording is already a separate explicit opt-in path and remains independent;
- diagnostic persistence/timers can be gated without changing the current LONG-only voice owners.

### Legacy-retirement facts

- current product authority is LONG-only; microphone SHORT is a no-op;
- `VoiceInputProfile` is already the canonical trigger destination authority;
- Persistent and Receiver-B preferences are explicitly excluded from current profile migration authority;
- Settings/overlay/runtime/tests still expose or implement obsolete Persistent/Dual semantics;
- some historically Persistent-named gate/tombstone/suppression mechanisms are now required by LONG-only correctness and must be kept/reframed rather than deleted.

## Selected sequence

1. **Wave A — diagnostics gating**: authorized next implementation handoff.
2. **Wave B — UI/config retirement**: still frozen.
3. **Wave C — Persistent/Dual runtime/test retirement**: still frozen.
4. **Wave D — final regression/resource audit**.

Splitting these waves is intentional so a diagnostics/performance regression cannot be mixed with state-machine retirement.

## Wave A target

One effective process-local diagnostics mode:

```text
effectiveDiagnosticsEnabled = AppStorage.loggingEnabled
                              OR REMOTE_ORBIT_DIAGNOSTICS=1
```

Disabled mode must avoid diagnostic disk I/O, structured writer enqueue/serialization and diagnostic-only recurring timers while preserving product correctness owners. Audio recording remains separately controlled by `AppStorage.recordingEnabled`.

## Current mutation boundary

The next local execution context may implement **Wave A only** according to `CURRENT_TASK.md` and the accepted design document.

It may not remove Persistent/Dual production code, alter SHORT/LONG semantics, install/replace the app, mutate the HAL driver, restart CoreAudio, change TCC/default devices, tag/release, or merge its PR.

Task 043 human runtime acceptance remains deferred; Task 045 work must not relabel it PASS.
