# RemoteOrbit Long-Term Observability Design

Date: 2026-10-29  
Task: `RO-OBSERVABILITY-039`  
Status: Approved execution brief from the owner handoff (`MODE: EXECUTE`)

## Intent

RemoteOrbit needs durable evidence from ordinary voice sessions after the v0.2.15 soak was blocked by the owner's natural-use final-text omission. The implementation must make later Air-side evidence possible without changing the audio, BLE, HID, gesture, Option, driver, or receiver behavior being observed.

## Verified constraints

- `DiagnosticAuthority` is the canonical machine-readable producer/query boundary and already provides asynchronous best-effort emission.
- `AudioPipe` owns the existing render state lock; render observation can be added to a reused fixed buffer while that existing lock is held, but no new diagnostic lock, formatting, or disk operation may enter render.
- The existing 038-B 8,192-bucket continuity ledger is opt-in and appropriate for its bounded evidence phase, but is not an acceptable unconditional normal-session allocation.
- `JSONLinesDiagnosticJournal` is a single indefinitely growing file with whole-file caching and must be bounded before long-term use.
- Receiver text content and Accessibility polling are outside RemoteOrbit's safe observation boundary.

## Goals

- Emit one compact `voice.session.summary` DiagnosticAuthority event for every real RemoteOrbit voice session, correlated by process instance, voice session/capture identity, incident/anomaly, time window, event type, and subsystem.
- Preserve the required gesture/control, transport, decode, supply, playout, and runtime facts with explicit active-versus-tail semantics.
- Keep a reused fixed-capacity front-edge plus rolling recent trace in memory; freeze and persist it only for material anomalies.
- Aggregate main-queue scheduling lag without per-sample log output.
- Rotate and retain journal segments under one bounded policy while retaining non-blocking producers and visible drop/write-failure counters.
- Offer an explicit read-only CLI export producing a manifest-bearing tarball and recording unavailable receiver evidence instead of fabricating it.

## Non-goals and anti-goals

- No product behavior correction or tuning.
- No raw dictated text, continuous Accessibility polling, automatic upload, settings backup, database, installation, release, tag, PR lifecycle, Air runtime, TCC, driver, or LaunchAgent mutation.
- No synchronous disk I/O, string formatting, allocation, or new shared diagnostic lock in CoreAudio render or CoreBluetooth audio callbacks.
- No unconditional reuse of the existing 8,192-bucket ledger.

## Approaches

### A. Extend the existing DiagnosticAuthority with L1/L2 events — selected

Add registered summary and anomaly-trace event types to the existing typed envelope, add a fixed-capacity observation trace owned at the AudioPipe boundary, and emit only at session completion through the existing asynchronous authority. Replace the journal implementation behind the same protocol with bounded rotation and streaming/bounded-segment queries. Add export as a CLI consumer of that authority.

This preserves the canonical writer, existing correlation/query contract, and current producer non-blocking semantics. The main integration cost is a small set of observation-only calls at already-owned lifecycle boundaries.

### B. Expand `VoiceDiagnosticLogger` into a permanent flight recorder — rejected

It already has voice lifecycle coverage, but it is opt-in/current-run, text-shaped, lacks a stable query API, and owns file lifecycle separately from `DiagnosticAuthority`. Making it authoritative would create a parallel schema and duplicate retention policy.

### C. Introduce a database or an unconditional full-resolution ledger — rejected

A database is not justified for personal desktop retention, and a full-resolution per-session ledger would recreate the observer-effect/cost problem that 038-B explicitly corrected. A reused bounded trace plus anomaly freeze provides the needed ordering at lower cost.

## Ownership and interfaces

- `LongTermObservability.swift` owns observation schema, fixed-capacity trace, session accounting, centralized anomaly thresholds, main-queue lag aggregation, and conversion to DiagnosticAuthority payloads.
- `AudioPipe` owns a preallocated pair of fixed traces and records submission/render/queue observations while its existing state lock is held. It detaches the completed trace before off-path snapshotting.
- `VoiceTimingLogger` remains the voice lifecycle facade and forwards timestamps/control/transport/decode facts to the long-term observer; it does not become a second persistence authority.
- `BLEBridge` supplies notification/decode/transport values already owned by that component and passes the existing AudioPipe snapshot at drain completion.
- `JSONLinesDiagnosticJournal` keeps its protocol but rotates the current segment at a bounded byte threshold, retains a bounded number of segments, and scans segments without a whole-history cache.
- `DiagnosticCLI` adds `export` as an explicit, read-only collection command. Archive creation is a user-invoked side effect, never an automatic producer action.

## Storage policy

The default journal retains at most five JSONL segments, each capped at 2 MiB before rotation. The current segment plus four rotated segments are the query/export authority; older segments are retired by ordinary file replacement under the journal lock. Query reads one bounded segment at a time and returns a page, so memory is bounded by one segment plus the requested result page. Append writes a complete newline-terminated event and synchronizes the handle before rotation; a partial trailing line is treated as a corrupt segment rather than silently invented evidence.

Normal sessions persist only the summary event. A summary is anomaly-marked when centralized thresholds observe a material delivery deficit, significant BLE gap, strict active underrun, queue starvation, trace drop, main-queue lag, or lifecycle inconsistency. Only then are trace chunks emitted.

## Receiver evidence

The export invokes a bounded unified-log provider for the selected wall-clock window with a predicate limited to receiver startup/AVCapture/InputMethodKit timing categories. The provider is injectable in tests. If the command cannot obtain receiver evidence, the archive contains a machine-readable unavailable record with the error; no text value is synthesized.

## Verification implications

Focused tests must prove accounting, anomaly thresholds, trace wrap/freeze/drop behavior, active-versus-tail separation, main-queue lag aggregation, rotated-segment queries, export manifest/archive policy, and receiver-unavailable handling. Source inspection and tests must separately prove no render disk/formatting/new-lock path, no synchronous BLE journal write, normal-session summary-only persistence, and bounded memory/disk.

## Consequences and reversibility

- The authority envelope remains schema v1; the long-term observation payload carries its own stable `observation_schema_version` so existing v1 records remain readable.
- The journal file name remains the canonical base path; rotated siblings are an implementation detail of the same authority.
- The design is reversible by removing the new event producers and retaining the journal protocol; the retention policy is independently adjustable through its centralized policy type.

TASK_RECONCILIATION_REQUIRED: NO  
REASON: The selected design stays within `CURRENT_TASK.md` diagnostics-only scope and preserves all frozen product boundaries.  
DURABLE_DOCUMENT: `docs/superpowers/specs/2026-10-29-long-term-observability-design.md`
