# ADR-0003: Long-term voice observability

Status: second corrective candidate for next independent audit

Date: 2026-10-29

## Decision

RemoteOrbit uses one DiagnosticAuthority for durable evidence. When the effective
diagnostics gate is enabled, each ordinary voice session emits one compact,
machine-readable `voice.session.summary` event. A bounded high-resolution trace is
retained in memory and is serialized only when centralized anomaly thresholds classify
the session as worth preserving.

The two evidence levels are:

- L1 summary: emitted whenever the effective diagnostics gate is enabled. It carries
  `session_id`, `capture_id`, lifecycle timestamps,
  control policy/classification, ATVV transport identity, notification/decode/supply/
  playout counters, active-versus-tail deficits, runtime provenance, observation
  schema version, receiver evidence status, and diagnostic drop/write counters.
- L2 incident trace: anomaly only. The service keeps a fixed front-edge capacity of 64
  observations and a rolling recent capacity of 256; each AudioPipe producer trace
  keeps 64 front-edge and 512 rolling recent observations. Each producer also owns a
  bounded 128-observation pre-incident ring and a bounded 128-observation follow-up
  ring. A lock-free first-writer-wins coordinator establishes one capture generation at
  the earliest gesture or transport boundary, before either producer can publish
  pre-HID evidence. A later HID session binding is not a reset boundary; the generation
  is released only after the capture snapshot is detached, and the next independent
  capture starts clean. Within that generation, the coordinator assigns one incident
  identity, trigger, and monotonic anchor across both producers. The triggering producer freezes
  its pre-ring and appends to its follow-up ring; the other producer synchronizes to
  the same anchor on its next observation, so merging never silently prefers one
  producer's incident evidence over the other's. Intentional recent-ring overwrite is
  retention metadata only; an actual out-of-order/drop condition is anomalous. Trace
  observations are numeric records with a typed kind, monotonic timestamp, frame
  accounting, queue depth, and active/tail marker. Trace chunks contain at most 128
  observations and are emitted off the BLE/CoreAudio callback path.

The default journal policy is 2 MiB per JSONL segment and 5 retained segments. The
authority remains asynchronous and best-effort; queue drops and journal write failures
are counted separately. Centralized anomaly flags include material notification/decode
gaps, active or tail deficits, explicit delivery deficit, queue starvation, lifecycle
order inconsistency, main-queue lag, actual trace drop, and authority write failure.
A normal callback gap over 20 ms contributes to aggregate timing statistics but is not
anomalous by default; the default material callback-gap gate is over 100 ms. Delivery
deficit requires both the configured sample-count and duration thresholds. Main-queue
lag retains bounded timestamped occurrences in addition to the aggregate histogram and
percentiles. Querying scans one bounded segment at a time and supports process,
session, incident, correlation, event, subsystem, severity, and wall-clock window
filters.

## Task 045A runtime policy supersession

Task 045A supersedes the earlier L1 always-on policy. The effective diagnostics gate
is `AppStorage.loggingEnabled || REMOTE_ORBIT_DIAGNOSTICS == "1"`, sampled into a
process-local runtime state. When the gate is disabled, structured diagnostic
producers, timers, probes, bounded trace lifecycle, and persistent diagnostic journal
work are stopped or skipped; ordinary recording remains independently controlled by
`AppStorage.recordingEnabled`. The environment override is an explicit diagnostic
operator control, not a replacement for user-owned acceptance or independent audit.

The prior phrase “L1 summary: always on” is retained only as historical ADR context;
the L1 always-on policy is superseded by Task 045A.

## Receiver evidence boundary

RemoteOrbit records its own trigger, transport, first-PCM, output, and drain
boundaries. The explicit export command may request a bounded structured unified-log
window using the receiver timing subsystem/category predicate. If that evidence is
unavailable, the archive contains `receiver/evidence-unavailable.json`; no value is
fabricated and no dictated text is intentionally harvested.

## Export

The supported manual workflow is:

```text
RemoteOrbit diagnostics export --output <directory> --host-role TEST_HOST \
  --since-unix-ms <start> --until-unix-ms <end>
```

For MacBook Air natural-use acceptance, `TEST_HOST` means “MacBook Air”; the source
head, app/build identity, and capture window in `manifest.json` are the authority for
cross-host comparison. The resulting archive is named
`RemoteOrbit-diagnostics-<timestamp>.tar.gz` and may include:

```text
manifest.json
runtime/runtime-context.json
sessions/diagnostic-events.json
journal/<bounded-retained-segment>.jsonl
logs/<allowlisted-json-or-jsonl-file>
receiver/unified-log-window.jsonl
receiver/evidence-unavailable.json
SHA256SUMS
```

The receiver file is mutually exclusive: an available bounded window containing useful
receiver timing records, or an explicit unavailable record. Empty output, output with
no useful timing evidence, and command failure remain unavailable. The export follows
authority query cursors in bounded pages rather than silently stopping at one page; it
has a centralized 10,000-event safety limit and records count/limit/truncation in the
manifest. Truncation is true only when the bounded query proves that events remain
beyond the exported limit. Logs are sourced from the production `AppStorage.logsDirectory` and are
limited to `RemoteOrbit.log` plus approved JSON/JSONL diagnostic files in that same
directory. Settings, backups, and recordings are excluded. The export does not upload,
reset, install, modify settings, or create a settings backup.

## Air acceptance workflow

1. Keep the Mac mini as the construction host. Later, install the exact candidate
   source/build on the MacBook Air only under an explicitly authorized acceptance
   task; do not compare runtime PIDs or local process identities between hosts.
2. Launch RemoteOrbit through the normal Finder/Login Item path and use the voice
   control naturally for the agreed acceptance window. Do not enable the old opt-in
   continuity environment variable as a substitute for L1 evidence.
3. Record the exact app version/build/source head and the wall-clock start/end of the
   natural-use window.
4. Run the export command above on the Air with `--host-role TEST_HOST` and that
   window. Inspect `manifest.json`, `SHA256SUMS`, the L1 session events, and any L2
   chunks before manual upload or sharing.
5. Keep the Air installation, final visual acceptance, and any release decision
   user-owned. This ADR does not authorize installation, merge, tag, or release.

## What the probes establish

They establish recorded local observations: event ordering and monotonic timestamps,
the RemoteOrbit-owned lifecycle boundaries, bounded notification/decode/supply/
playout counters, active-versus-tail accounting, real BLE-arrival/decode-complete/
PCM-submit/render observations, bounded timestamped main-queue lag occurrences,
runtime identity, and whether receiver evidence was available at export time. An
incomplete final JSONL record is repaired without discarding valid history; interior
corruption and unsupported schema versions fail closed. Lifecycle events that arrive
after end remain queryable as bounded `voice.session.lifecycle_followup` events
correlated to the finalized capture.

They do not establish receiver text, an InputMethodKit state that RemoteOrbit cannot
observe, BLE radio causality, firmware behavior, or a product root cause. This evidence does not establish root cause. Anomaly flags
only decide whether to preserve L2 evidence; an anomaly classifier does not claim root
cause. Receiver-side questions remain UNKNOWN until independent evidence exists.

## Follow-up questions requiring upstream evidence

- A/B: with the same candidate build and natural-use utterance, does changing only the
  receiver launch/voice-input condition change the local timing signature?
- HCI: do the captured HID down/up reports, report ordering, and connection lifecycle
  match the RemoteOrbit session and Option ownership boundaries?
- PacketLogger: do ATT notification intervals, retransmissions, or link events align
  with the local BLE callback-gap observations?

Those questions require independent Air-side A/B, HCI, or PacketLogger evidence. This
observability candidate does not infer their answers.

## Frozen product boundaries

This change does not alter ATVV commands, ADPCM decoding, AudioPipe buffering or gain,
sample rate, HID mapping, short/long gesture semantics, Option/Control ownership,
persistent-session behavior, driver audio semantics, or receiver behavior.
