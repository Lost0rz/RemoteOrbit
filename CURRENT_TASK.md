# RemoteOrbit Current Task

## Current task — DUAL-RECEIVER MOMENTARY ROUTING DESIGN SPEC REVIEW

- **Status:** DESIGN SPEC WRITTEN / WAITING FOR USER APPROVAL BEFORE IMPLEMENTATION PLAN
- **Task ID:** `RO-DUAL-RECEIVER-MOMENTARY-ROUTING-018`
- **Previous task:** `RO-DUAL-RECEIVER-GESTURE-RECOGNITION-017` — CLOSED / `GESTURE_RECOGNITION_STABLE`
- **Design spec:** `docs/superpowers/specs/2026-10-08-dual-receiver-momentary-voice-routing-design.md`
- **Candidate corrective HEAD:** `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`
- **Product source mutation:** FORBIDDEN until implementation plan is written, Web-audited, and explicitly authorized
- **Runtime install/restart:** FORBIDDEN
- **Merge:** FORBIDDEN

## Accepted product contract

```text
Direct LONG                   -> Receiver A
Quick first tap + second LONG -> Receiver B
Quick single tap              -> no action
```

Initial receiver trigger contract:

```text
Receiver A -> Left Option
Receiver B -> Right Option
```

Both are independent momentary voice transactions. Dual-receiver mode must not use external Persistent Session state as ownership authority.

## Accepted timing

```text
LONG_THRESHOLD_MS = 350
DOUBLE_WINDOW_MS   = 300
```

These values are supported by the closed 017 hardware timing evidence.

## Frozen architecture

### Trigger parking before classification

While dual mode is active:

- disable/clear the device-scoped F5 -> receiver `hidutil` mapping;
- retain one raw HID owner (`HIDMonitor`);
- use the existing `EventSuppressor` to swallow the remote's native F5 path;
- no Left/Right Option edge may exist before receiver classification.

### Gesture ownership

Add a small microphone-specific, pure/testable classifier adjacent to the voice coordinator. Do not hand BLE/trigger lifecycle to the generic button action injector.

Expected states/semantics:

```text
first DOWN -> transport-only prewarm
first hold >= 350ms -> classify A
first UP < 350ms -> wait <= 300ms for second DOWN
no second DOWN -> no action / cancel prewarm
second DOWN in window + hold >= 350ms -> classify B
second quick UP -> no action / cancel prewarm
```

### Voice transaction

After A/B classification:

```text
activateVoiceInput
-> first PCM
-> selected trigger DOWN
-> stream
-> physical release
-> existing tail/output drain
-> matching selected trigger UP
```

`VoiceOptionTrigger` remains the trigger-balance owner and must capture the transaction's exact key.

### Settings

- Existing momentary trigger = Receiver A.
- Add optional secondary/double-hold trigger = Receiver B.
- Secondary Off = legacy single-receiver behavior unchanged.
- Dual mode requires SHORT Disabled and A != B.
- Do not repurpose the Persistent trigger preference.

### Fail-closed rule

If the raw HID/EventSuppressor path is unavailable in dual mode, do not silently fall back to OS F5 or guess A/B. Stop dual routing safely.

## Construction baseline reconciliation

Current `main` and classifier candidate are diverged. The candidate is 2 commits ahead of its old base and 36 commits behind current `main`; candidate commits contain stale control-document edits.

Implementation must therefore:

1. branch from the latest authoritative `origin/main`;
2. transplant only the exact candidate versions of:
   - `remote-orbit/Sources/RemoteOrbit/main.swift`
   - `remote-orbit/Tests/RemoteOrbitTests/DisabledShortClassifierTests.swift`
   from HEAD `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`;
3. verify that this initial adopted diff is only the already-accepted Disabled-SHORT classifier corrective;
4. never import candidate `CURRENT_STATUS.md` / `CURRENT_TASK.md`.

## User-review gate

The written design spec must be reviewed by the user before detailed implementation-plan construction.

If the user sends the planning execution card supplied by Web after reviewing this spec, treat that as approval to create the implementation plan only.

That approval does **not** authorize product-code mutation.

## Next authorized task after user approval — PLAN ONLY

Create a docs-only implementation plan using the repository planning/TDD workflow.

Recommended planning branch/worktree:

```text
BRANCH: codex/dual-receiver-momentary-routing-v1-plan
WORKTREE: /private/tmp/remoteorbit-dual-receiver-momentary-routing-v1-plan
```

Base the planning worktree on the exact current authoritative `origin/main` after freshness verification.

The plan file must be:

`docs/superpowers/plans/2026-10-08-dual-receiver-momentary-routing.md`

The plan must specify exact files, tests and commands for at least these construction stages:

1. authoritative baseline + exact classifier-corrective adoption;
2. pure dual-receiver voice gesture classifier TDD;
3. explicit per-transaction trigger-key ownership TDD;
4. raw F5/EventSuppressor microphone regression coverage;
5. dual-mode runtime mapping/fail-closed behavior;
6. BLE prewarm/classification/first-PCM integration;
7. release/drain/transport-loss/rapid-repress ownership;
8. secondary trigger persistence + settings UI;
9. early real-receiver synthetic-trigger hardware gate;
10. full regression/build/diff audit;
11. final two-receiver hardware acceptance;
12. independent Web audit before merge.

The plan must place the early hardware trigger-acceptance gate before nonessential UI polish. If synthetic Left/Right Option is unreliable against real receivers, construction must STOP and return to architecture instead of restoring pre-classification hidutil mapping.

## Plan-task allowed side effects

After explicit user approval of the design spec:

Allowed:
- `git fetch origin --prune`;
- read-only repository/source/history audit;
- create the single planning worktree/branch above;
- create/edit only the implementation plan document and plan-specific control handoff if required by the repository protocol;
- run read-only commands needed to make the plan exact;
- commit/push the docs-only plan branch.

Forbidden during plan task:
- product source edits;
- test source edits;
- runtime setting changes;
- build/install/restart;
- receiver shortcut changes;
- hardware experiment;
- merge.

## Required plan handoff

Return:

```text
TASK_ID: RO-DUAL-RECEIVER-MOMENTARY-ROUTING-018
CONTROL_HEAD:
PLAN_BRANCH:
PLAN_WORKTREE:
PLAN_HEAD:
REMOTE_PLAN_HEAD:
PLAN_PATH:
BASE_MAIN:
CANDIDATE_CORRECTIVE_AUDITED:
PRODUCT_SOURCE_CHANGED: NO
TEST_SOURCE_CHANGED: NO
RUNTIME_CHANGED: NO
MERGED: NO
FINAL_STATE: PLAN_READY_FOR_INDEPENDENT_WEB_AUDIT
```

Until user approval is expressed by sending the authorized planning card, local AI must return:

`HOLD_FOR_DUAL_RECEIVER_DESIGN_SPEC_APPROVAL`
