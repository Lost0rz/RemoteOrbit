# CURRENT_STATUS

Last updated: 2026-11-01
State: `RO-DIAGNOSTICS-LEGACY-RETIREMENT-045 — HUMAN_RUNTIME_ACCEPTANCE_PASS / CLOSED`
Repository: `Lost0rz/RemoteOrbit`
Human runtime/UI acceptance: `PASS / USER-CONFIRMED`

## Task 045 progress

- Task 045A: `DIAGNOSTICS_GATING / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 1: `LEGACY_VOICE_PRODUCT_SURFACE / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 2: `LEGACY_VOICE_PERSISTED_PREFERENCE_AUTHORITY / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 3: `PERSISTENT_VOICE_RUNTIME_STATE_MACHINE / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 4: `DUAL_RECEIVER_RUNTIME_STATE_MACHINE / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 5: `LEGACY_GENERIC_SHORT_CLASSIFIER_RUNTIME / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045B Domain 6: `LOCAL_MICROPHONE_CAPTURE / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045D Domain 1: `REMOTE_ONLY_PCM_ATTRIBUTION / MERGED / MAIN_CI_PASS / CLOSED`
- Task 045D Domain 2: `P1A5_FRONT_EDGE_EXPERIMENT_DIAGNOSTICS / MERGED / MAIN_CI_PASS / CLOSED`
- Final whole-repository machine audit: `PASS_WITH_FOLLOWUPS`
- Human runtime acceptance: `PASS / USER-CONFIRMED`
- Task 045 overall: `CLOSED`

## Accepted final voice/runtime contract

The accepted production model is now the direct LONG-only RC003 remote-voice lifecycle:

- SHORT below the 300 ms boundary is a user-visible no-op;
- LONG crossing the boundary promotes into direct remote voice;
- release preserves queued PCM through bounded output drain before final trigger/session release;
- rapid LONG/release/LONG uses bounded ownership handoff without an intermediate stuck trigger or incorrect physical-input restoration;
- Persistent and Dual Receiver product/runtime semantics are retired;
- generic non-direct SHORT/LONG classifier states are retired;
- RemoteOrbit-owned local/external microphone AVCapture fallback and microphone TCC ownership are retired;
- local/mixed PCM attribution and P1-A5 experiment diagnostics are retired.

Historical `ShortTap` / `AudioOnly` suppression names and `P1A4MonotonicClock` remain current implementation details because live callers still use them for accepted LONG-only correctness/timing.

## Machine evidence

The machine gate before human acceptance was complete and green:

- product merge CI after Wave D Domain 2: run `41282571433`, job `124777309274`, `SUCCESS`, including 504/504 Swift tests, Release and Universal2 packaging;
- Domain 2 closeout CI: run `41282783523`, job `124777921972`, `SUCCESS`;
- final machine-audit / human-acceptance entry commit `675a88bf87611d4788b9b5c72d11d2c9203cba01` CI: run `41284015670`, job `124781533923`, `SUCCESS`, including Source contracts, Protocol self-tests, Full Swift tests, Native Release and Universal2 packaging.

The final repository audit found no additional product-code retirement Domain required before human acceptance.

## Human acceptance result

The owner completed real runtime testing of the exact accepted candidate and reported no problems. The human gate is therefore recorded as:

`HUMAN_RUNTIME_ACCEPTANCE = PASS`

This closes Task 045. No further Task 045 product-code cleanup is authorized or required by the accepted plan.

## Remaining non-blocking release-readiness follow-ups

These are outside the completed Task 045 runtime acceptance and do not reopen it:

1. `README.md` and `SETUP_NOTES.md` still contain stale baseline/version text and portions of the older first-PCM/classifier narrative. Reconcile before a final release/tag.
2. Draft PR #25 is a historical/diverged v0.2.15 soak/release candidate and must not be merged into current `main` without a separate reconciliation.
3. Draft PR #26 is a historical/diverged Settings corrective and must not be merged into current `main` without a separate reconciliation.
4. Draft PR #28 is a separate branding/icon task and requires its own lifecycle decision.
5. One test-only unnecessary-`try` compiler warning remains in `LocalMicrophoneCaptureRetirementContractTests.swift`; no runtime impact was found.
6. CI packaging does not build the HAL driver; release packaging/driver policy remains a separate release-readiness concern.

## Current boundary

Task 045 is closed.

No additional Wave D product-cleanup Domain is authorized.

No tag/release is authorized by this closeout. Documentation reconciliation, stale-PR hygiene, branding work, driver/release packaging, tag, or release must be handled as separate follow-up work with fresh authority.
