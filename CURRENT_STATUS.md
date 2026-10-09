# CURRENT_STATUS

Last updated: 2026-10-09
State: TASK 027 ACTIVE / RIGHT OPTION PHYSICAL-VS-REPLAY EVENT-SHAPE SOURCE AUDIT / READ-ONLY
Repository: `Lost0rz/RemoteOrbit`

## Authority
- Audited control predecessor: `6c212435eb9e7b0c247a5b19f72c81399c3b5bf8`.
- `230ccf7c97050511478fd3130e1f9a8e71c4ecb1` added only the Task-027 incident/audit note before the formal transition.
- `6c212435eb9e7b0c247a5b19f72c81399c3b5bf8` added an unintended temporary `CURRENT_STATUS.tmp`; this transition removes that temporary file. Neither commit changed product code.
- Corrective branch under audit: `codex/dual-receiver-mic-debounce-corrective` at `458e28d91b5ff748613bb88f5b89212d660279c7`.
- Installed product source remains `406f1242e7c3bc17b1fa0da43b069a0b2c6874c8` by last local evidence.
- Merge remains forbidden.

## Accepted facts entering Task 027
- Set A remains accepted 5/5.
- Corrective 024 fixed the active-dual microphone legacy-debounce conflict.
- Task 025 proved a true Receiver-B transaction completed internally: mapped Right Option entered HardwareOptionGate; B classified; first PCM preceded B DOWN replay; physical UP and mapped B UP were observed; output drain, B-UP release, gate close, `MOMENTARY_COMPLETE`, and B->A restore all completed; normal synthetic trigger edge count remained zero.
- Task 026 proved Receiver B has correct momentary semantics with a direct physical Right Option: hold opens B and release immediately closes B.

## Established boundary
`REMOTEORBIT_REPLAY_NOT_EXTERNALLY_EQUIVALENT_TO_PHYSICAL_RIGHT_OPTION`.

Receiver-B shortcut configuration and the internal B transaction lifecycle are not the unresolved boundary. The unresolved boundary is the externally visible event shape/timing of the captured/replayed mapped Right Option DOWN/UP versus a direct physical Right Option press/release.

## Task 027
Perform a detailed read-only source/evidence audit of the capture/replay path. Determine:

1. what exact CGEvent types/fields are captured for mapped Right Option DOWN and UP;
2. how copied events are stored and replayed;
3. which tap/source/flags/keyCode/userData/timestamp semantics survive replay;
4. whether DOWN and UP are symmetric;
5. whether B->A mapping/filter restoration can occur before the externally consumed B-UP transition;
6. whether A and B use exactly the same replay implementation;
7. what current tests prove and what they do not prove about external equivalence.

No product/test/runtime mutation is authorized in this task. If current code cannot prove the external mismatch cause, define the smallest validation needed before any fix.
