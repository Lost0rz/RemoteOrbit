# RemoteOrbit v0.2.14

## Baseline purpose

This release freezes the currently accepted RemoteOrbit runtime and product behavior. Release preparation changes only release metadata and these notes; it introduces no new product behavior.

## Dual Receiver baseline

- In dual-receiver mode, a quick single tap has no action by contract.
- A direct LONG selects Receiver A.
- A quick tap followed by a second LONG selects Receiver B.
- Dual-receiver mode requires the macOS single-click action to be Disabled.
- The A/B system-mapped trigger architecture is retained.
- The Receiver-B replay-UP acknowledgement ordering corrective is retained.

## Accepted validation record

- User-reported direct LONG testing was stable.
- Receiver-B user stability gate: 5/5 PASS.
- Internal Receiver-B corrected ordering: 5/5 PASS.
- No additional hardware sample counts are asserted here.
- Standalone quick-single hardware acceptance was not rerun specifically for this release. The automated no-action contract remains covered.

## Known deferred issue

In Codex short Voice Chat mode, the local or external microphone is used for the short input action. A remote LONG takes over with the remote microphone. Local microphone capture resumption after the remote LONG ends has not yet been independently accepted as stable.

This behavior is explicitly deferred. It is not fixed or validated by v0.2.14.

## Version

RemoteOrbit 0.2.14
Build 43
Universal 2
