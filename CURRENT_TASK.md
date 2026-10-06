# RemoteOrbit Current Task

## Current task — RO-INCIDENT-20261004-01 / B4 EXTERNAL EVENT-PLANE VERIFICATION

- **Status:** ACTIVE / DIAGNOSTIC CONSTRUCTION ONLY
- **Incident ID:** `RO-INCIDENT-20261004-01`
- **Authorized branch:** `codex/b4-external-event-plane-verification`
- **Planned worktree:** `/private/tmp/remoteorbit-b4-external-event-plane-verification`
- **Product Construction Gate:** BLOCKED
- **Product behavior mutation:** FORBIDDEN
- **Release/install/runtime replacement:** NOT AUTHORIZED
- **User reproduction:** NOT AUTHORIZED in this phase

## Objective

Resolve the next missing boundary fact without reopening network or P0-A work:

> During LONG while persistent mode is already open, does any Option/Control/key/`flagsChanged` or equivalent trigger-like event appear on the macOS external/session event plane even though RemoteOrbit's internal B3 evidence shows no correlated mapped trigger?

This task distinguishes two questions:

- **B4a — event-plane presence:** whether a trigger-like event exists outside RemoteOrbit's internal trigger-intent boundary.
- **B4b — Doubao receiver acceptance:** whether Doubao specifically accepted such an event.

B4a evidence alone must never be reported as B4b receiver acknowledgement.

## Accepted baseline

```text
PREVIOUS_CONTROL_HEAD: fddcbb7dd2985967cf8d9741c229888d0c0a06c2
NETWORK_VERIFICATION: PASS
NETWORK_STATE: STABLE_FOR_CURRENT_TEST
NETWORK_BLOCKER: CLEARED
P0A_PASSIVE_SEMANTIC_OBSERVER_PATH: CLOSED_UNOBSERVABLE
ROOT_CAUSE: UNKNOWN
PRODUCT_CONSTRUCTION_GATE: BLOCKED
```

The old canonical checkout `/Volumes/Jack-Dev/Projects/RemoteOrbit` is superseded/dirty and must not be used or cleaned for this task. Its historical `HIDMonitor.swift` edit has no unique work that needs preservation for B4.

## Gate 0 — exact authority and clean isolation

Before any diagnostic construction:

1. live-fetch `origin`;
2. verify `origin/main` and `origin/codex/b4-external-event-plane-verification` equal the published B4 control HEAD;
3. verify the remote URL is the canonical `Lost0rz/RemoteOrbit` repository;
4. create or reuse only `/private/tmp/remoteorbit-b4-external-event-plane-verification` for this task;
5. require the worktree to be clean and exactly at the authorized branch HEAD;
6. read `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md` from that HEAD.

Any HEAD mismatch, fetch failure, unexpected existing worktree content, or dirty state => STOP. Do not repair the old canonical checkout.

## Gate 1 — read-only evidence/source audit

Inspect the real production and diagnostic paths relevant to B4, including where applicable:

- existing B3/boundary probes;
- CGEvent/event-tap layers;
- HID/key mapping and Option/Control translation;
- `EventSuppressor`;
- synthetic-event tagging/source metadata;
- `DiagnosticAuthority` event schema/consumers.

Determine the earliest existing observation point that is genuinely outside RemoteOrbit trigger intent and can distinguish whether a trigger-like system event exists.

Do not infer external event presence from `trigger_edge_emitted`, internal state, intended synthetic send, BLE/audio state, or target text.

## Gate 2 — minimal observer decision

If existing instrumentation already provides sufficient external/session event-plane evidence, do not add a new probe. Return the exact event source, clock/domain, identity fields, and why it satisfies B4a.

If existing instrumentation is insufficient, implement only the smallest passive diagnostic observer needed for B4a. Requirements:

- listen-only / non-mutating;
- no event injection, suppression, replay, synthesis, focus change, IME control or settings mutation;
- record event type, relevant modifier flags/key identity, event/source metadata sufficient to distinguish physical/synthetic where technically available, wall-clock timestamp and declared monotonic/event timestamp domain;
- record observer identity/build/source HEAD sufficient for later capture binding;
- avoid target text or unrelated user content;
- fail closed when permission/signal is unavailable;
- use the existing diagnostic authority/schema where doing so preserves a single diagnostic backend, otherwise justify a standalone observer boundary rather than creating a second product-state authority.

Add focused tests that prove the observer is non-mutating and records only the required B4a evidence contract.

## Gate 3 — validation and handoff

Run the smallest sufficient focused tests/build checks for changed diagnostic code.

Do not perform the user SHORT/LONG reproduction in this phase.

If changes were necessary:

- commit only authorized diagnostic/test/control changes;
- push the authorized branch;
- verify remote branch HEAD exactly matches the local final HEAD;
- leave the worktree clean.

Then stop for independent Web audit.

## Forbidden

- no network/DNS repair work;
- no modification/cleanup/reset/stash of the old canonical checkout;
- no product behavior fix;
- no SHORT/LONG live reproduction;
- no app reinstall/runtime replacement;
- no TCC/Input Monitoring/Accessibility changes;
- no driver/CoreAudio/settings changes;
- no event injection, replay or control of Doubao;
- no promotion of B4a event-plane observation into B4b receiver acceptance without independent receiver evidence.

## Completion report

Return:

```text
CONTROL_HEAD:
AUTHORIZED_BRANCH:
WORKTREE:
BASELINE_GATE:
NETWORK_GATE:
WORKTREE_CLEAN_START:

B4_EXISTING_INSTRUMENTATION_AUDIT:
EXTERNAL_EVENT_OBSERVATION_POINT:
OBSERVATION_POINT_IS_OUTSIDE_TRIGGER_INTENT:
CLOCK_DOMAIN:
EVENT_SOURCE_METADATA_AVAILABLE:
PHYSICAL_SYNTHETIC_DISTINCTION_AVAILABLE:

B4_EXISTING_OBSERVER_SUFFICIENT:
B4_MINIMAL_PASSIVE_OBSERVER_IMPLEMENTED:
CHANGED_PATHS:
FOCUSED_TESTS:
BUILD_VALIDATION:
NON_MUTATING_CONTRACT:
PRIVACY_CHECK:

USER_REPRODUCTION_PERFORMED: NO
PRODUCT_BEHAVIOR_CHANGED: NO
RUNTIME_MUTATIONS: NONE
ROOT_CAUSE: UNKNOWN
PRODUCT_CONSTRUCTION_GATE: BLOCKED

FINAL_HEAD:
REMOTE_HEAD:
FINAL_WORKTREE_CLEAN:
FINAL_STATE:
WAITING_FOR_INDEPENDENT_WEB_B4_IMPLEMENTATION_AUDIT
```
