# RemoteOrbit Current Task

## RO-OBSERVABILITY-039 — Long-Term Production-Safe Observability

Status: `WAITING_FOR_INDEPENDENT_WEB_AUDIT`

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
- Corrective transition start HEAD: `24d08c64abf5832a89957241713fb50cfd60da04`.
- Corrected implementation baseline HEAD: `ad223e4b5f35653abe1014697cb50a87d3db05ad`.
- Second corrective transition parent: `bcecd35e47d7a21df3f1213395970a6c8e4073da`.
- Second corrective implementation HEAD: `447b3b9`.
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

## Corrective gate

The second independent Web audit was blocked by bounded cross-layer incident-window findings. This corrective establishes one shared incident identity/anchor across the existing service and AudioPipe producer-owned traces, preserves relevant BLE/decode/PCM/render/starvation evidence when either producer triggers, aligns production material triggers with centralized classification, corrects exact-limit export truncation, and makes ADR capacities exact. It preserves the product/audio freeze and adds no hot-path disk I/O, formatting, authority emission, or new contended diagnostic lock. Focused realistic tests, full Swift regression, release build, self-tests, `git diff --check`, and exact source/product-freeze review pass. The candidate was pushed at `e703e16554e98e69ed6fb4e84ccce542c4169b20` and remote-verified; await another independent Web audit. This does not authorize merge, tag, release, or Air runtime validation.

## Final verification receipt

- `swift test`: 461 passed, 0 failed.
- `swift build -c release`: passed.
- `./run-self-tests.sh`: passed all 3 protocol self-tests.
- `git diff --check`: passed.
- PR #25 remains Draft/Open/Unmerged; no merge, tag, release, install, or Air runtime mutation is authorized by this corrective.
