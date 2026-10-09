# RemoteOrbit Current Task

## Current task — RECEIVER B EXTERNAL SHORTCUT SEMANTICS GATE

- **Status:** CLOSED / EXTERNAL SEMANTICS VERIFIED
- **Task ID:** `RO-DUAL-RECEIVER-B-EXTERNAL-SEMANTICS-GATE-026`
- **Previous task:** `RO-DUAL-RECEIVER-SET-B-RELEASE-INCIDENT-025` — INTERNAL RELEASE COMPLETE / EXTERNAL DIVERGENCE
- **Corrective branch HEAD:** `458e28d91b5ff748613bb88f5b89212d660279c7`
- **Installed source:** `406f1242e7c3bc17b1fa0da43b069a0b2c6874c8`
- **Merge:** FORBIDDEN

## User manual result
The user performed exactly one direct physical-keyboard Right Option hold/release test against Receiver B, without using the Xiaomi remote.

```text
PHYSICAL_RIGHT_OPTION_OPENS_B: YES
PHYSICAL_RIGHT_OPTION_RELEASE_CLOSES_B: YES
STUCK_AFTER_PHYSICAL_RELEASE: NO
```

## Accepted classification
`REMOTEORBIT_REPLAY_NOT_EXTERNALLY_EQUIVALENT_TO_PHYSICAL_RIGHT_OPTION`

This closes the external shortcut-semantics gate. Receiver B itself accepts normal physical Right Option momentary semantics correctly.

Combined with Task 025, the accepted boundary is now:

```text
RemoteOrbit internal B transaction completes
RemoteOrbit records B mapped UP / output-drained release / gate close / MOMENTARY_COMPLETE
B->A restore succeeds
BUT Receiver B stays open

Direct physical Right Option hold/release
-> B opens
-> physical release immediately closes B
```

Therefore the remaining unknown is not Receiver-B configuration and not the already-proven RemoteOrbit transaction lifecycle. It is the external equivalence of the captured/replayed mapped Right Option event sequence.

## Stop boundary
No new product work is authorized in this task.

Do not:

```text
NO source/test edits
NO build/install/restart
NO mapping/settings changes
NO remote Set-B retry
NO Set C
NO release/drain retune
NO HardwareOptionGate redesign
NO driver/CoreAudio/TCC changes
NO merge
```

## Recommended next task — NOT YET AUTHORIZED
A separate read-only event-shape audit may compare a known-good physical Right Option sequence against the RemoteOrbit captured/replayed B sequence, including:

```text
event type (flagsChanged/keyDown/keyUp)
key code
modifier flags and transition semantics
event source/state/PID fields
event source user-data marker
timestamp/order
capture tap and replay/post tap
DOWN/UP symmetry
ordering of B UP exposure versus B->A hidutil/filter restoration
```

The next task must be explicitly authorized before changing diagnostics or product code.
