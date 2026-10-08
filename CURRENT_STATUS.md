# CURRENT_STATUS

Last updated: 2026-10-08
State: DUAL-RECEIVER ROUTING DESIGN SPEC FROZEN / USER REVIEW BEFORE IMPLEMENTATION PLAN
Repository: `Lost0rz/RemoteOrbit`

This file is the authority for mutable current project state. Historical detail remains preserved in Git history.

## Control-plane integrity

- Last audited `main` before this transition: `feff02f7a5d6b1519abd077bc6b5331533eb44e9`.
- Candidate branch remains `codex/disabled-short-classifier-regression-fix` at exact HEAD `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`.
- Installed hardware-test baseline last reported: PID `79232`, source HEAD `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`, executable SHA-256 `a033e86a92b02175a498bba3232c5ae8b72719caef781cb74c3187e8e64ed017`.
- Candidate remains unmerged.
- The candidate and current `main` are diverged: candidate is 2 commits ahead of merge base and 36 commits behind current `main`. The candidate commits also contain stale control-plane document edits, so the candidate branch must not be merged/cherry-picked wholesale.

## Accepted preceding results

### Single-input-method collision

Closed. Doubao click/toggle mode and hold-to-talk mode had both been bound to Left Option. Separating those external receiver shortcuts removed that specific fast-click Session activation.

### Disabled-SHORT classifier corrective

Still required. Candidate behavior restores:

```text
bypassesShortClassification = false
```

and has the accepted hardware-path quick-release regression coverage.

### Dual-receiver gesture recognition

Task `RO-DUAL-RECEIVER-GESTURE-RECOGNITION-017` is CLOSED / `GESTURE_RECOGNITION_STABLE`.

Accepted product interaction:

```text
Direct LONG                   -> Receiver A
Quick first tap + second LONG -> Receiver B
Quick single tap              -> no action
```

Accepted first implementation timing:

```text
LONG_THRESHOLD_MS = 350
DOUBLE_WINDOW_MS   = 300
```

Natural test samples classified A 10/10, B 10/10, single-tap no-action 5/5. A 200 ms double window failed 2/10 B samples; 250 ms passed but had only 10.453 ms minimum inter-press margin; 300 ms retained 60.453 ms minimum margin.

## Implementation source audit — FACT

1. `HIDMonitor` already owns a single `EventSuppressor` and arms it from raw HID state before semantic button-edge dispatch. The suppressor runs at a head-insert `cghidEventTap` and can suppress the remote microphone's native F5/keyCode 96 path.
2. Current device-scoped `RemoteVoiceKeyMapping` maps remote F5 to only one `VoiceTriggerKey` at a time. That mapping is incompatible with a gesture whose receiver is not known until after classification.
3. `BLEBridge` already separates transport-only `prepareVoiceTransport()` from `activateVoiceInput()` / `micOpen`, so pending first-tap and double-window states can prewarm without starting external voice input.
4. `VoiceOptionTrigger` already captures `activeTriggerKey` and balances UP against that captured key. It needs only a minimal explicit per-transaction DOWN-key entry point for dual mode.
5. The generic `ButtonGestureRecognizer` demonstrates second-tap-long semantics, but the microphone path deliberately bypasses generic action injection. Dual voice routing should keep audio/trigger ownership with the voice subsystem.
6. Existing Settings already expose the direct-long momentary key and a separate Persistent key. The Persistent preference must not be repurposed as Receiver B.

## Frozen design decision

Design spec:

`docs/superpowers/specs/2026-10-08-dual-receiver-momentary-voice-routing-design.md`

Selected architecture:

```text
raw F5
-> no receiver hidutil mapping while dual mode is active
-> EventSuppressor parks native F5
-> voice-specific 350/300 classifier
-> choose A or B
-> activate ATVV
-> first PCM
-> synthetic DOWN for the selected VoiceTriggerKey only
-> physical release + existing drain
-> matching UP for the captured selected key
```

Dual mode activation contract:

```text
microphone SHORT == Disabled
AND secondary/double-hold trigger is enabled
AND A trigger != B trigger
```

When secondary trigger is Off, legacy single-receiver behavior remains unchanged.

Receiver A reuses the existing momentary trigger setting. Receiver B gets a new optional secondary/double-hold trigger setting. Persistent Session state is not authority for dual-receiver mode.

## Rejected implementation directions

- Dynamic `hidutil` remapping after classification: rejected for the held-key boundary and latency/race risk.
- Keep F5 mapped to A and suppress A only if B later wins: rejected because B's first tap must expose no A edge.
- Persistent A + temporary B handoff: rejected as dual-receiver authority because external IME Session state is not observable reliably.
- seize/virtual-HID/DriverKit: deferred unless real receiver hardware rejects classified synthetic triggers.

## Construction baseline rule

Implementation must start from the latest authoritative `origin/main`, not from the stale candidate branch.

Then adopt only the exact final candidate versions of:

```text
remote-orbit/Sources/RemoteOrbit/main.swift
remote-orbit/Tests/RemoteOrbitTests/DisabledShortClassifierTests.swift
```

from `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`, and verify that the resulting baseline diff is only the already-accepted classifier corrective before feature work.

Do not import the candidate's old `CURRENT_STATUS.md` or `CURRENT_TASK.md`.

## Primary remaining uncertainty

The gesture vocabulary is proven stable. The main remaining product risk is whether both real receivers reliably accept a **classified synthetic Left/Right Option transaction** as the normal trigger owner.

This must be tested at an early construction gate after the minimal core path is built, before broad UI polish or merge work.

If real receiver acceptance fails, STOP and return to architecture. Do not restore a pre-classification receiver `hidutil` mapping as a workaround.

## Next transition

The architecture spec is now frozen for user review. Product-source mutation is still forbidden.

After the user approves the written spec, the next authorized action is a docs-only implementation-plan task using the repository's planning/TDD workflow. The implementation plan must be independently Web-audited before code construction is authorized.
