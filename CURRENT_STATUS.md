# CURRENT_STATUS

Last updated: 2026-10-31
State: `RO-DIAGNOSTICS-LEGACY-RETIREMENT-045 — AUDIT_AND_DESIGN_ACTIVE`
Repository: `Lost0rz/RemoteOrbit`
Control base: `main@4b0131902a64a7cc92dcc3c9be001b185a8834ce`
Task 043: `MERGED / HUMAN_ACCEPTANCE_DEFERRED / USER-OWNED`
Task 045: `AUTHORIZED BY USER / AUDIT_AND_DESIGN_ACTIVE`

## Transition authority

The user explicitly reauthorized normal forward development before completing the deferred Task 043 human runtime acceptance. This removes the prior Task 045 blocker but does not convert Task 043 into a human PASS.

Task 043 remains merged through PR #30 and retains its deferred manual RC003/Doubao acceptance. If later manual testing finds a regression, open a fresh incident from the exact tested runtime identity rather than rewriting the historical Task 043 conclusion.

## Active next work

Task 045 audits and designs two related cleanup boundaries:

1. diagnostics gating / normal-mode overhead reduction;
2. retirement of obsolete Persistent and Dual-Receiver production authority.

The durable product contract remains LONG-only:

- SHORT `<300 ms` is a user-visible no-op;
- LONG `>=300 ms` enters direct remote voice;
- release drains/closes through the existing direct path;
- rapid repress, late mapped Option suppression, pre-HID candidate ownership, bounded candidate/prebuffer ownership, BLE readiness reuse, output drain ownership, and post-release grace must be preserved where they are still required for correctness.

## Known audit targets

Diagnostics surfaces to classify include ordinary `RemoteOrbit.log`, `VoiceDiagnosticLogger`, `DiagnosticAuthority`, runtime-health/heartbeat observability, long-term observability, and WAV/RAW recording. Audio recording is a separate opt-in surface and must not be conflated with ordinary logging.

Legacy retirement surfaces to classify include production UI/configuration, AppStorage migration/state, `main.swift` Persistent session machinery, AppController Dual Receiver machinery, supporting source files, and tests that still assert obsolete Persistent/Dual behavior.

## Current phase boundary

Current authority is AUDIT + DESIGN only. Product source mutation, deletion of legacy source/tests, runtime installation, HAL/driver mutation, TCC/CoreAudio mutation, release, and merge are not yet authorized.

The next transition requires a repository-grounded inventory and bounded implementation plan that explicitly separates:

- DELETE/RETIRE: obsolete production authority;
- KEEP/RENAME: mechanisms still required by LONG-only correctness;
- GATE: diagnostic work that should disappear when diagnostics are disabled;
- KEEP-ALWAYS: correctness/safety work that must remain active independent of logging.
