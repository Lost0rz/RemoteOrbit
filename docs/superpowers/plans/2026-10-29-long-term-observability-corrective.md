# Long-Term Observability Audit Corrective Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or inline execution under the current task) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct the failed independent Web audit findings while preserving RemoteOrbit product/audio behavior.

**Architecture:** Keep `DiagnosticAuthority` as the durable writer. Add bounded producer-owned traces and an incident snapshot separate from ordinary recent-ring retention, centralize anomaly thresholds, repair journal tails before use, and make export source/pagination/receiver evidence explicit and bounded.

**Tech Stack:** Swift 5.9, XCTest, Foundation `FileHandle`/`Process`, existing macOS unified-log and archive helpers.

**Spec:** `docs/superpowers/specs/2026-10-29-long-term-observability-corrective-design.md`

## Global Constraints

- No product/audio/BLE/HID/gesture/Option/driver/Doubao behavior change.
- No render/BLE hot-path disk I/O, authority emission, formatting, or new diagnostic lock.
- Fixed-capacity trace and bounded incident snapshot only; merge/copy/serialize off hot paths.
- Healthy timing variance and intentional ring wrapping remain summary-only.
- Default journal remains 2 MiB per segment and 5 retained segments.
- No raw dictated text, Accessibility polling, Air installation, PR #25 lifecycle mutation, merge, tag, or release.

## Review Focus

- Ring overwrite must be retention metadata, while out-of-order/drop remains anomalous — `LongTermObservabilityTests` wrap/drop classification tests.
- A mid-session anomaly must survive later writes — incident-freeze survival test.
- BLE/decode/PCM/render and main-queue evidence must be real monotonic records — trace correlation tests.
- Journal recovery must repair only a trailing partial record — append/query and fail-closed corruption tests.
- Export must be complete, production-layout based, allowlisted, and honest about receiver evidence — archive and manifest tests.

### Task 1: Reconcile controls and add failing corrective coverage

**Files:** `CURRENT_STATUS.md`, `CURRENT_TASK.md`, `remote-orbit/Tests/RemoteOrbitTests/LongTermObservabilityTests.swift`, `DiagnosticAuthorityTests.swift`, `DiagnosticExportTests.swift`, `JSONLinesDiagnosticJournal` tests.

- [ ] Confirm branch/worktree/HEAD and record the authorized corrective transition as one control commit.
- [ ] Add failing tests for healthy wrap, retention-only overwrite, out-of-order anomaly, incident survival, delivery deficit, complete stage trace, main-queue correlation, journal tail recovery, export pagination/layout, receiver usefulness, and late lifecycle correlation.
- [ ] Run each focused test filter and confirm failures represent missing corrective behavior.

### Task 2: Correct trace ownership, anomaly policy, delivery semantics, and late lifecycle

**Files:** `remote-orbit/Sources/RemoteOrbit/Diagnostics/LongTermObservability.swift`, `AudioDataPlaneDiagnostics.swift`, `AudioPipe.swift`, `BLEBridge.swift`, `VoiceOptionTrigger.swift`.

- [ ] Add bounded incident capture separate from recent-ring overwrite accounting and preserve the captured window through end/finalization.
- [ ] Add real numeric BLE-arrival/decode-complete/PCM-submit/render/fill/starvation observations at existing boundaries; keep all hot-path writes numeric and bounded.
- [ ] Add bounded timestamped main-queue incident-lag evidence while retaining aggregate statistics.
- [ ] Replace decode-gap-as-delivery semantics with a named delivery-deficit flag and centralized thresholds; keep active/tail fields separate.
- [ ] Preserve late `markForSession` facts through a bounded post-end finalization or correlated follow-up event without altering the state machine.

### Task 3: Repair journal recovery and bounded query behavior

**Files:** `remote-orbit/Sources/RemoteOrbit/Diagnostics/JSONLinesDiagnosticJournal.swift`, `DiagnosticAuthority.swift`, related tests.

- [ ] Add a red test for valid records followed by an incomplete final line, reopen, append, and query.
- [ ] Implement tail-only truncation/repair before append/query; reject interior malformed records and unsupported schema without partial results.
- [ ] Preserve 2 MiB/5-segment retention, non-blocking authority producer behavior, and bounded page/segment memory.

### Task 4: Correct export pagination, log source, and receiver evidence

**Files:** `remote-orbit/Sources/RemoteOrbit/Diagnostics/DiagnosticExport.swift`, `DiagnosticCLI.swift`, `AppStorage.swift`, related tests and docs.

- [ ] Add red tests for >500 selected-window events, explicit export limits, AppStorage-relative `RemoteOrbit.log`/diagnostic allowlist, backups/recordings exclusion, and useful-vs-empty receiver evidence.
- [ ] Follow authority cursors until the window is exhausted or the centralized limit is reached and recorded in the manifest.
- [ ] Collect only bounded allowlisted real-layout logs and mark receiver evidence unavailable unless useful timing records exist.

### Task 5: Verify, document, and deliver the corrected candidate

**Files:** `docs/diagnostics/ADR-0003-long-term-observability.md`, `README.md`, `SETUP_NOTES.md`, changed source/tests.

- [ ] Update documentation with threshold meaning, incident freeze, trace correlation, journal recovery, export source/pagination, receiver semantics, and late lifecycle behavior.
- [ ] Run focused tests, full/proportionate Swift regression, release build, self-tests, and `git diff --check`.
- [ ] Source-review frozen product paths and prove render/BLE observer-effect boundaries; verify changed-file identity and PR #25 remains untouched.
- [ ] Push only `codex/observability-039` and verify the remote HEAD for another independent Web audit; do not install on Air or create/merge a PR.
