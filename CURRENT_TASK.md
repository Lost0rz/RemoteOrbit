# RemoteOrbit Current Task

## RO-OBSERVABILITY-039 — Long-Term Production-Safe Observability

Status: `AIR_VALIDATION_ACTIVE / EXPORTER_CORRECTIVE_DELIVERED / WAITING_FOR_INDEPENDENT_WEB_AUDIT`

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
- Pre-HID lifecycle corrective start HEAD: `c6cc2918ab9314507ad85f8e82fac58c74f26674`.
- Pre-HID lifecycle corrective implementation HEAD: `ae8265108c6b8cdff1ef67cb7b4ac3555a9f5a7d`.
- Air-validation preparation source/control authority before this transition: `e524b636021b4af407dffae6b1b5c2c5baab718d`.
- Independent Web audit: `PASS` for the exact pushed candidate, as authorized by the current Air-validation preparation card.
- The prior natural-use omission remains an observed release-blocking result; this task makes no root-cause claim.
- Air validation is active under the owner-controlled candidate workflow. The first real Air export failed repeatedly with `diagnostics: export failed: evidenceTooLarge` and produced no archive.
- The observed Air `RemoteOrbit.log` was approximately 4.86 MB / 29,813 lines. The pre-corrective source review showed approved application logs were copied whole-file and an individual copied file above 2 MiB failed the export.
- This exporter corrective remains under `RO-OBSERVABILITY-039`; it does not authorize an audio or root-cause corrective.
- Exporter corrective implementation: `d366646` (`diagnostics: bound long-term export evidence`). It applies parseable time windows to `RemoteOrbit.log`, uses an honest bounded fallback for unparseable lines, and preserves archives with source-specific bounded/unavailable/failed manifest receipts for sessions, journals, application logs, and receiver evidence.
- Exporter corrective independent Web audit: `PENDING`; do not infer PASS from local tests or remote delivery.
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

The second independent Web audit was blocked by bounded cross-layer incident-window findings and then identified one remaining pre-HID lifecycle boundary. The completed corrective establishes the shared incident coordinator generation exactly once at the earliest authoritative gesture/transport capture boundary; a later HID session binding preserves incident identity, anchor, and producer synchronization state; a genuinely new capture receives a clean generation. It preserves first-writer-wins, pre-HID BLE/decode/PCM/render evidence, AudioPipe-first evidence, wrap survival, and all existing journal/export/receiver/late-lifecycle behavior. It preserves the product/audio freeze and adds no hot-path disk I/O, formatting, authority emission, or new contended diagnostic lock. Focused lifecycle tests, full Swift regression, release build, self-tests, `git diff --check`, and exact source/product-freeze review pass locally. The candidate is pushed on `codex/observability-039`; remote readback matched `593a488cad186d02485ea821fb41f966a135ac77` before the delivery receipt, and receipt `93f1b91ad06f9717251b09653557aebe4ff44910` was also pushed and read back before this factual control correction. The independent Web audit is now PASS. This authorizes exact candidate packaging and owner-run Air validation preparation only; it does not authorize merge, tag, release, PR #25 mutation, or Mac mini/Air runtime installation.

## Air-validation preparation gate

- Reconcile `origin/codex/observability-039`, the active worktree, and these authority files before packaging.
- Build the exact candidate from the current branch lineage without changing product/audio semantics.
- Record source/control HEAD, semantic implementation HEAD, app version/build, architecture, code identity, executable/artifact SHA-256, and embedded source revision when supported.
- Verify Swift tests, release build, protocol self-tests, packaging, artifact contents, signatures, checksums, `git diff --check`, and clean worktree.
- Provide owner-run Finder/Login Item installation and natural-use instructions for the MacBook Air. Do not install or launch the Air candidate from the Mac mini. Do not upload evidence automatically.

## Air-validation candidate receipt

- Independent Web audit: `PASS`; no root-cause claim is made for the prior natural-use omission.
- Candidate build source/control HEAD: `9200a9f8e21715038a07d64bb6a607f550b4f765`.
- Candidate semantic implementation HEAD: `ae8265108c6b8cdff1ef67cb7b4ac3555a9f5a7d`.
- Candidate artifact: `/private/tmp/remoteorbit-air-validation-20261029/RemoteOrbit-0.2.14-AIR-VALIDATION.dmg`.
- Artifact SHA-256: `63ccb29361260437a9d77444c9ce07c1568603399b859eb67d5a2aae1e112825`.
- App executable SHA-256: `80caecc29f57aef52c2afd37182ed28b093ce807d9f0fb1e379df8a282128aed`.
- App version/build: `0.2.14 (43)`; App and embedded driver architectures: `x86_64 arm64`.
- Embedded `RemoteOrbitDiagnosticSourceHead`: `9200a9f8e21715038a07d64bb6a607f550b4f765`.
- App and driver ad-hoc signatures verified; App designated requirement is `identifier "com.lost0rz.RemoteOrbit"`; no Developer ID/notarization claim.
- Read-only DMG mount/content check passed with the top-level App, `/Applications` link, Documentation, embedded signature, and source revision present.
- Packaging used only ephemeral current-toolchain overrides for the pinned driver deployment target and SwiftPM x86 triple; no source, tests, or packaging scripts changed.
- `swift test`: 466 passed, 0 failed. `swift build -c release`: passed for the native build and the manual x86 `--triple` build. Protocol self-tests: 3/3 PASS. `git diff --check`: passed. Worktree: clean.

The candidate was installed and used by the owner under the prior Air-validation handoff. The next authorized step is an exporter-only corrective: reproduce the large-log/three-hour-window failure shape in a fixture, implement bounded time-windowed log evidence and source-specific manifest status, preserve journal/receiver integrity, and re-run the full verification set. Preserve the existing Air runtime and raw evidence; do not automatically upload or delete it.

## Exporter corrective gate

- Before implementation, this control transition records independent observability source audit `PASS`, active Air validation, the real `evidenceTooLarge` export failure, and the exporter-only scope.
- Make `--since-unix-ms` / `--until-unix-ms` materially constrain timestamped `RemoteOrbit.log` evidence where parseable; use an honest bounded fallback for unparseable lines.
- A single oversized `RemoteOrbit.log`, journal segment, or receiver evidence source must not destroy otherwise useful archive evidence. Bound or mark unavailable with source-specific machine-readable manifest status, reason, original size, and exported size when available.
- Preserve journal rotation, partial-tail recovery, interior-corruption fail-closed behavior, schema validation, receiver privacy boundaries, allowlists, checksums, pagination, and exact 10,000-event semantics.
- Add realistic focused regressions for large log, time window, bounded fallback, receiver oversize partial success, source-specific manifest status, normal export, and checksums. Keep the full observability/audio/gesture regression green.
- Return to independent Web audit after remote delivery. Do not claim an independent Web-audit result in this corrective receipt.

## Corrective gate

- Start from literal HEAD `c6cc2918ab9314507ad85f8e82fac58c74f26674`.
- Update `CURRENT_STATUS.md` and `CURRENT_TASK.md` together before implementation.
- Do not reset the shared incident coordinator merely because a HID UUID becomes available if an active pre-HID capture already owns the generation.
- Do not add a hot-path lock or change ATVV, BLE, AudioPipe, HID, gesture, driver, Doubao, packaging, installation, release, PR, or Air runtime behavior.

## Exporter corrective verification receipt

- Root failure reproduced by an oversized `RemoteOrbit.log` fixture with a requested time window; the prior implementation raised `evidenceTooLarge` before creating an archive.
- Focused exporter regressions: 9 passed, including large-log windowing, bounded journal/receiver evidence, provider oversize fallback, session-query failure status, allowlist, pagination, exact event-limit semantics, and checksum verification.
- Full Swift regression: 470 passed, 0 failed. Release build passed. Protocol self-tests: 3/3 PASS. `git diff --check` passed before the implementation commit.
- Product/audio freeze review: changed product source is limited to `Diagnostics/DiagnosticExport.swift`; no audio, BLE, HID, gesture, receiver behavior, driver, install, or runtime files changed.
- Next action: verify and publish `d366646` plus the final control receipt on `codex/observability-039`, then hand off for independent Web audit. Air validation remains active and owner-controlled; preserve the observed Air runtime/evidence.

## Final verification receipt

- `swift test`: 466 passed, 0 failed.
- `swift build -c release`: passed.
- `./run-self-tests.sh`: passed all 3 protocol self-tests.
- `git diff --check`: passed.
- PR #25 remains Draft/Open/Unmerged; no merge, tag, release, install, or Air runtime mutation is authorized by this corrective.
