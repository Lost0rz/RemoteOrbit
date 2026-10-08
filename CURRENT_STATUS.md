# CURRENT_STATUS

Last updated: 2026-10-08
State: SET B CORRECTIVE RETRY / B OPENS / RELEASE DOES NOT CLOSE / INCIDENT READ-ONLY
Repository: `Lost0rz/RemoteOrbit`

## Authority
- Previous control HEAD: `3fd2271e7dbb80c8407f7a963b3615a8116c8382`.
- Debounce corrective task `RO-DUAL-RECEIVER-MIC-DEBOUNCE-CORRECTIVE-024` produced product source `406f1242e7c3bc17b1fa0da43b069a0b2c6874c8` and branch closeout `458e28d91b5ff748613bb88f5b89212d660279c7`.
- Installed corrective candidate: `/Applications/RemoteOrbit.app`, source `406f1242e7c3bc17b1fa0da43b069a0b2c6874c8`, version 0.2.13 build 42, PID reported as 5331.
- Corrective branch: `codex/dual-receiver-mic-debounce-corrective`.
- Merge remains forbidden.

## Proven 024 result
The earlier input-layer failure is resolved by the corrective candidate at the user-observable boundary: the natural quick-tap + second-LONG gesture again opens Receiver B. This is consistent with the 024 RED/GREEN evidence that the legitimate second microphone DOWN is no longer discarded by the legacy 180 ms debounce.

Do not infer that the entire Set-B transaction is accepted. User report for the first corrective hardware retry:

```text
B opened normally.
Physical release did not close/end B normally.
```

## New incident boundary
The remaining defect is now isolated to the accepted B transaction's release/close path or to divergence between RemoteOrbit's internal close path and the external receiver's handling of Right Option UP.

Root cause of this remaining release failure is UNKNOWN until fresh runtime ordering is captured.

Required evidence must determine, for this exact corrective sample:

```text
second raw F5 DOWN emitted (not debounce-suppressed)
B HardwareOptionGate begin
B classification
first PCM and mapped B DOWN replay
second raw F5 UP
mapped Right Option UP capture/defer/replay
VoicePress release/tail/output-drain completion
MOMENTARY_COMPLETE
B->A restore request/result
final mapping/filter/phase/transaction/runtime state
external B still open vs internal completion
```

## Freeze
No further remote gestures, Set C, settings/mapping changes, app restart, build/install, source/test edits, release/drain fix, receiver shortcut changes, driver/CoreAudio/TCC changes, or merge before this fresh corrective incident is audited.

## Next action
Read-only capture of the single corrective Set-B retry. Stop after evidence collection. Do not repair yet.
