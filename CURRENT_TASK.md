# RemoteOrbit Current Task

## Current task — CANONICAL LEGACY HID PRESERVATION RECONCILIATION

- **Status:** ACTIVE / PRESERVE FIRST
- **Task ID:** `RO-CANONICAL-HID-PRESERVATION-030`
- **Control parent:** `9c3b0e4446ac89d34ec0c7ee7cb3da18c0e961c5`
- **Canonical branch:** `codex/v0211-nonseize-hid-audit`
- **Canonical HEAD:** `48a6d54ffa1a2798ac9ac760673d6406cec6bf12`
- **Target:** `remote-orbit/Sources/RemoteOrbit/KeyMapping/HIDMonitor.swift`

Goal: preserve the exact historical working content and patch outside the repository, verify hashes and reconstruction from historical HEAD, then reconcile the canonical checkout to current authoritative `main`. The historical media-suppression behavior is evidence only and must not be reintegrated.

Stop on remote-main drift, additional dirty paths, hash mismatch, failed reconstruction, or containment failure. No product/runtime behavior change and no unrelated worktree/branch cleanup are authorized.

Completion evidence must report the preservation location and hashes, reconstruction result, final canonical branch/HEAD/clean state, and whether the historical local branch remains.
