# RemoteOrbit Current Task

## RO-OBSERVABILITY-039 — Long-Term Production-Safe Observability

Status: `ACTIVE — IMPLEMENTATION CANDIDATE CONSTRUCTION`

Repository: `Lost0rz/RemoteOrbit`

Canonical repository: `/Volumes/Jack-Dev/Projects/remoteorbit`

## Objective

Build production-safe, low-overhead, always-on RemoteOrbit observability before any further audio corrective. Ordinary launches must retain compact machine-readable session summaries; material anomalies may retain bounded high-resolution evidence; the owner must have one explicit manual export workflow for later MacBook Air natural-use evidence.

## Authority and transition

- Transitioned from `RO-RELEASE-V0.2.15` / `LOCAL_SOAK_ACTIVE` after the owner's natural-use result showed substantial final-text omission.
- Release decision: `RELEASE_BLOCKED / SOAK_FAILED`; no root cause is inferred from that observation.
- Audited parent: `8f71cde21df6ca1f5a831a8b5390abbfde61e9d9`.
- Active branch: `codex/observability-039`.
- Active worktree: `/private/tmp/remoteorbit-longterm-observability-039`.
- PR #25 remains Draft/Open/Unmerged and must not be merged, tagged, or released.

## Authorized scope

1. Extend the existing Diagnostics authority with an always-on compact session summary correlated by process instance, voice session/capture identity, anomaly/incident, time window, event type, and subsystem.
2. Account for gesture/control, transport, decode, supply, playout, and runtime identity fields already owned by the relevant subsystems.
3. Add a fixed-capacity/reused in-memory temporal trace preserving startup/front-edge and rolling recent observations for BLE arrival → decode → PCM submission → queue depth → render request/fill/starvation; persist it only after anomaly classification and only off hot paths.
4. Centralize and test anomaly thresholds; classify evidence-worth-preserving only, never root cause.
5. Add a low-overhead main-queue responsiveness probe with aggregate count/max/percentile or histogram and incident-only timestamped detail.
6. Preserve RemoteOrbit receiver boundaries without Accessibility polling or raw dictated-text collection; export bounded best-effort receiver unified-log evidence and explicitly record unavailable evidence.
7. Replace indefinite whole-file JSONL authority with a simple crash-tolerant bounded rotation/retention policy, preserving asynchronous/best-effort producer behavior and visible drop/write-failure metrics.
8. Provide one explicit manual `RemoteOrbit-diagnostics-<timestamp>.tar.gz` export with manifest, provenance, summaries, frozen traces, selected journal segments/logs, unavailable-evidence errors, and `SHA256SUMS`; never upload automatically or create settings backups.
9. Add focused tests for summary accounting, anomaly classification, fixed-capacity wrap/freeze/drop behavior, queue-lag aggregation, active-versus-tail underrun semantics, journal rotation/querying, export correctness, unavailable receiver evidence, and existing audio/gesture contract preservation.
10. Document L1/L2 architecture, retention, export/correlation workflow, probe limits, observer-effect boundaries, and questions requiring A/B/HCI/PacketLogger evidence.

## Frozen non-goals

- No ATVV MIC_OPEN mode, BLE command/protocol, codec, sample rate, jitter, AudioPipe buffer/queue/playout, gain, HID, gesture, Option/Control, persistent-session, driver, or Doubao behavior changes.
- No speculative corrective, Accessibility polling, continuous raw text capture, automatic upload, automatic settings backup, database introduction, package/install/release/tag/PR lifecycle mutation, Air runtime mutation, TCC/permission mutation, or LaunchAgent mutation.
- Do not unconditionally allocate the existing 8192-bucket opt-in ledger if that creates meaningful normal-runtime cost.
- Do not synchronously write disk, format strings, allocate, or acquire a new shared diagnostic lock in CoreAudio render or CoreBluetooth audio hot callbacks.

## Completion gate

Stop at a verified implementation candidate ready for independent Web audit and later owner-controlled Air installation/testing. Completion requires focused tests, proportionate Swift regression/build/self-tests, source/test evidence for hot-path and bounded-memory/disk claims, documentation, exact changed-file identity, and reconciled controls. It does not authorize merge, tag, release, or Air runtime validation.
