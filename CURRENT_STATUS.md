# CURRENT_STATUS

Last updated: 2026-10-09
State: SET B INTERNAL RELEASE COMPLETE / EXTERNAL RECEIVER DIVERGENCE / EXTERNAL SEMANTICS GATE
Repository: `Lost0rz/RemoteOrbit`

## Authority
- Previous control HEAD: `b8ca994e102e441ad9ad4b6f98b3a72f931ca79e`.
- Corrective branch: `codex/dual-receiver-mic-debounce-corrective` at `458e28d91b5ff748613bb88f5b89212d660279c7`.
- Installed product source: `406f1242e7c3bc17b1fa0da43b069a0b2c6874c8`.
- Merge remains forbidden.

## Accepted facts
- Set A remains accepted 5/5.
- Corrective 024 fixed the legacy 180 ms microphone debounce conflict for active dual mode.
- Fresh Set-B retry contains a true B transaction: second DOWN 140.400083 ms after first UP; B was already ready; mapped Right Option entered HardwareOptionGate; B classified; first PCM preceded B DOWN replay.
- Physical second UP was observed and emitted.
- Mapped B UP was observed; HardwareOptionGate physical-up ownership, output drain, B-UP release after drain, gate close and `MOMENTARY_COMPLETE` all completed.
- B->A mapping/filter restoration succeeded and A readback matched.
- Normal synthetic trigger edge count remained zero.

Decision: `INTERNAL_B_RELEASE_COMPLETE`.

## Remaining incident
The user reports Receiver B remained open after RemoteOrbit completed the entire internal B release transaction. This is an internal/external state divergence. Current evidence does not prove why the external receiver stayed open.

Do not modify RemoteOrbit release/drain, mapping, HardwareOptionGate, BLE, gesture timing or synthetic trigger policy without new causal evidence.

## Next boundary
Run an external Receiver-B shortcut semantics gate before any new product change. The minimum user action is a direct physical Right Option hold/release test against Receiver B, without using the remote gesture. This distinguishes receiver/shortcut semantics from RemoteOrbit replay equivalence.
