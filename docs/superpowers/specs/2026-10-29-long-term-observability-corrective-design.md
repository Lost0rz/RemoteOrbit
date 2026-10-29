# Long-Term Observability Audit Corrective Design

Date: 2026-10-29  
Task: `RO-OBSERVABILITY-039`  
Status: corrective-active after independent Web audit failure

## Intent

Repair the long-term observability candidate so a healthy long session remains
summary-only, a real mid-session incident remains recoverable, and the manual
archive is complete and honest. Preserve all existing RemoteOrbit product,
audio, BLE, HID, gesture, receiver, driver, install, and release behavior.

## Selected approach

Use producer-owned, fixed-capacity numeric traces at the existing observation
boundaries, with a bounded incident snapshot captured when a material anomaly is
first observed and merged/persisted only off hot paths. Keep the existing
`DiagnosticAuthority` as the sole durable writer, centralize anomaly policy,
repair journal tails before append/query, paginate export through the authority,
and derive receiver evidence only from bounded useful timing records.

The alternatives are (a) extending the existing service lock until it owns all
trace points, which risks hot-path contention and loses the incident window, or
(b) sending every point directly to the authority, which violates the existing
non-blocking and bounded-memory contract. Both are rejected.

## Corrective goals

- Separate retention metadata (`overwrittenObservationCount`) from anomaly data;
  classify actual drops/out-of-order points and material delivery deficit.
- Preserve a bounded front/recent incident window at the first material anomaly;
  keep later normal wrapping from erasing it.
- Emit real monotonic BLE-arrival, decode-complete, PCM-submit, render/fill,
  starvation, and incident main-queue lag evidence.
- Keep active-vs-tail AudioPipe semantics explicit and never call active state
  strict speech without an independent boundary.
- Recover only an incomplete final JSONL record; fail closed for interior
  corruption and unsupported schema.
- Export all selected-window events, or record an explicit centralized limit;
  use `AppStorage.logsDirectory` and an allowlist for logs.
- Report receiver evidence unavailable unless useful bounded timing records are
  actually present; never collect dictated text.
- Preserve late lifecycle facts with a bounded post-end finalization window or a
  stable follow-up event.

## Non-goals and safety boundaries

No ATVV/protocol/codec/sample-rate/AudioPipe policy/gain/HID/gesture/Option,
driver, Doubao, TCC, LaunchAgent, installation, Air runtime, PR #25, merge,
tag, release, upload, settings backup, raw text capture, or Accessibility
polling changes. CoreAudio render and BLE callbacks remain free of synchronous
disk I/O, DiagnosticAuthority emission, string formatting, and new diagnostic
locks; incident copy/serialization is off-path.

## Verification contract

Tests must cover realistic healthy wrapping, retention-only metadata, actual
drop/out-of-order anomaly, mid-session incident survival, complete monotonic
trace correlation, main-queue/BLE timing correlation, delivery deficit with no
decode rejects, partial-tail journal recovery, fail-closed corruption/schema,
complete-or-explicitly-truncated export, production-equivalent log layout,
receiver available/unavailable semantics, and late lifecycle correlation.
Source review must separately prove hot-path and bounded-memory/disk claims.
