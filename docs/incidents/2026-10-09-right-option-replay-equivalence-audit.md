# Task 027 — Right Option physical-vs-replay equivalence audit

This note records a read-only source/evidence audit. Product code, tests, runtime, mappings, settings, drivers, and installed app are not authorized to change in this task.

Accepted boundary entering the audit:

- Task 025 proved a true Receiver-B transaction completed internally, including mapped Right Option DOWN/UP ownership, output drain, gate close, MOMENTARY_COMPLETE, and B->A restore.
- Task 026 proved a direct physical Right Option hold opens Receiver B and physical release immediately closes it.
- Therefore Receiver B shortcut semantics are correct, while RemoteOrbit's captured/replayed mapped Right Option sequence is not externally equivalent to a physical Right Option sequence.

Audit targets:

1. VoiceKeyFilter / HardwareOptionGate capture and replay implementation.
2. Event type, keyCode, flags, event source fields, userData marker, and posting tap for captured/replayed mapped Right Option DOWN/UP.
3. A-vs-B symmetry in the shared replay implementation.
4. Ordering of physical UP, mapped B UP capture, output-drained replay, gate close, B->A mapping/filter restore, and any readback.
5. Existing tests that prove internal lifecycle but may not prove external CGEvent equivalence.
6. Whether current evidence is sufficient for a causal code conclusion; otherwise define the smallest validation needed before any fix.

No fix is authorized by this note.