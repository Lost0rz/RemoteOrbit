# CURRENT_STATUS

Last updated: 2026-10-09
State: TASK 027 ACTIVE / SOURCE AUDIT COMPLETE / EXISTING-LOG EVENT-SHAPE COMPARISON AUTHORIZED / READ-ONLY
Repository: `Lost0rz/RemoteOrbit`

## Authority
- Audited predecessor: `358f2db4e65432fe11798f4c90943fdfda6d648a`.
- Corrective branch under audit: `codex/dual-receiver-mic-debounce-corrective` at `458e28d91b5ff748613bb88f5b89212d660279c7`.
- Installed product source remains `406f1242e7c3bc17b1fa0da43b069a0b2c6874c8` by last local evidence.
- `296d4fa7c540c507519b8def6ee9757c093a9aad -> 358f2db4e65432fe11798f4c90943fdfda6d648a` was independently compared: only control files plus the Task-027 incident note changed; no product/test code changed.
- Merge remains forbidden.

## Accepted boundary
- Set A passed 5/5 using the mapped Left Option hardware path.
- Corrective 024 fixed the active-dual microphone legacy-debounce conflict.
- Task 025 proved a true Receiver-B transaction completed internally, including mapped Right Option DOWN/UP ownership, output drain, B-UP release, gate close, `MOMENTARY_COMPLETE`, and B->A restore.
- Task 026 proved direct physical Right Option has correct Receiver-B momentary semantics: hold opens B; release immediately closes B.
- Accepted classification remains `REMOTEORBIT_REPLAY_NOT_EXTERNALLY_EQUIVALENT_TO_PHYSICAL_RIGHT_OPTION`.

## Task 027 source-audit findings
FACT:
- `VoiceKeyFilter` captures matching mapped modifier components with `event.copy()` at a `.cghidEventTap` head-insert filter and suppresses the originals while the gate owns them.
- Hardware DOWN replay posts the retained copied DOWN event(s) back at `.cghidEventTap` after first PCM. A long hold then retains ownership for the later mapped UP.
- After physical release, mapped UP component(s) are again copied, originals suppressed, then the copied UP event(s) are posted at `.cghidEventTap` after output drain.
- Normal hardware replay does not add `Key.syntheticMarker` and does not construct a fresh synthetic modifier event.
- The same replay implementation is parameterized by `momentaryVoiceTriggerKey`; there is no separate Left-Option versus Right-Option replay function.
- Right Option uses keyCode 61, generic `.maskAlternate`, and the device-side `NX_DEVICERALTKEYMASK`; Left Option uses keyCode 58 and the left-side device flag.
- `releaseHeldHardwareOption` posts the copied B-UP event(s) before `handleDualReceiverHardwareOutputDrainClosed` schedules B->A restoration on the main queue.
- Existing transaction tests model copied hardware edges with `captureDeferredHardwareOptionEdgeForTesting(... copied: true)` and assert internal ownership/callback ordering; they do not prove downstream external CGEvent equivalence.
- Existing diagnostics log mapped-event type, keyCode, flags, synthetic-marker classification, raw Quartz timestamp, gate state and action, but do not log all source-state/PID/keyboard-type fields.

INFERENCE:
- At source level A and B share the replay mechanism; the observed A/B behavioral difference is therefore not explained by a deliberate A-vs-B replay branch.
- Program order prevents B->A restore from beginning before the B-UP `post(.cghidEventTap)` call, but current evidence does not prove that the external receiver has consumed that UP before the later mapping restoration begins.

UNKNOWN:
- Whether Receiver B sees the replayed B-UP with the same downstream event shape/state as direct physical Right Option release.
- Whether delayed reposting through `.cghidEventTap`, preserved original timestamps/source fields, source-state changes, or the later B->A remap accounts for the external mismatch.

Decision: root cause is NOT proven from code alone. Before any product fix, perform one read-only comparison using already-existing logs: compare the Task-025 B original/replay event records with the already-performed Task-026 direct physical Right Option hold/release. No new gesture is needed yet.
