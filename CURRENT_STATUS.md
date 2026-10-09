# CURRENT_STATUS

Last updated: 2026-10-09
State: RECEIVER B EXTERNAL SEMANTICS GATE PASSED / REMOTEORBIT REPLAY NOT EXTERNALLY EQUIVALENT
Repository: `Lost0rz/RemoteOrbit`

## Authority
- Previous control HEAD: `a75131519085f222a4c7e8f1a613e38a2e191858`.
- Corrective branch: `codex/dual-receiver-mic-debounce-corrective` at `458e28d91b5ff748613bb88f5b89212d660279c7`.
- Installed product source: `406f1242e7c3bc17b1fa0da43b069a0b2c6874c8`.
- Merge remains forbidden.

## Accepted facts
- Set A remains accepted 5/5.
- Corrective 024 fixed the active-dual microphone legacy-debounce conflict.
- Task 025 proved a true Receiver-B transaction completed internally: mapped Right Option entered HardwareOptionGate; B classified; first PCM preceded B DOWN replay; physical UP and mapped B UP were observed; output drain, B-UP release, gate close, `MOMENTARY_COMPLETE`, and B->A restore all completed; normal synthetic trigger edge count remained zero.
- The user nevertheless observed Receiver B remain open after RemoteOrbit's completed internal release transaction.
- Task 026 direct keyboard test now proves Receiver B itself has the intended momentary semantics: physical Right Option hold opens B and physical Right Option release immediately ends B.

## Decision
`REMOTEORBIT_REPLAY_NOT_EXTERNALLY_EQUIVALENT_TO_PHYSICAL_RIGHT_OPTION` is established.

The current evidence rules out Receiver-B shortcut semantics/configuration as the explanation and rules out an incomplete RemoteOrbit transaction as the observed internal failure. The unresolved boundary is the externally visible shape/timing of RemoteOrbit's captured/replayed Right Option DOWN/UP versus a real physical Right Option press/release.

Do not modify gesture timing, debounce, BLE, mapping authority, HardwareOptionGate lifecycle, release/drain timing, or Receiver-B settings without a new authorized task and direct evidence.

## Next recommended investigation
A future read-only task should compare the exact CGEvent/event-tap characteristics of:

1. a direct physical Right Option hold/release that opens and closes Receiver B; and
2. the RemoteOrbit B transaction's captured/replayed mapped Right Option DOWN/UP.

Compare event type, key code, flags before/after modifier transition, source PID/state, timestamp, event source/user-data marker, replay tap, and ordering relative to B->A mapping restoration. No product mutation is authorized by this status file.
