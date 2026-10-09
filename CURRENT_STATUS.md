# CURRENT_STATUS

Last updated: 2026-10-09
State: TASK 028 IMPLEMENTED / AUTOMATED VALIDATION PASSED / CANDIDATE INSTALLED / WAITING FOR INDEPENDENT WEB AUDIT
Repository: `Lost0rz/RemoteOrbit`

## Authority
- Audited control predecessor: `10359be1edf6fab3beb400e28f294cfecb6acfcd`.
- Corrective product lineage under audit: `codex/dual-receiver-mic-debounce-corrective` at `458e28d91b5ff748613bb88f5b89212d660279c7`.
- Installed product source before corrective: `406f1242e7c3bc17b1fa0da43b069a0b2c6874c8`.
- New authorized corrective branch: `codex/dual-receiver-b-up-replay-ack-fix`, based exactly on `458e28d91b5ff748613bb88f5b89212d660279c7`.
- Authorized worktree: `/private/tmp/remoteorbit-dual-receiver-b-up-replay-ack-fix`.
- Product implementation commit and installed source: `f938b919e288a481f5eacaf9aad9c254dcf0cffe`.
- Installed candidate: `/Applications/RemoteOrbit.app`, version `0.2.13` build `42`, Bundle ID `com.lost0rz.RemoteOrbit`, running PID `39949`.
- Candidate executable SHA-256: `104d4bf0cad8f7316ceea8c8e21568737d3ba3eea0f3c44207107a1159eb850e`.
- Merge remains forbidden.

## Accepted prior gates
- Set A remains accepted 5/5 using system-mapped Left Option through the hardware gate.
- Corrective 024 fixed the dual-mode microphone legacy-debounce conflict.
- Task 025 proved a true Receiver-B transaction internally reached mapped Right Option DOWN/UP ownership, output drain, gate close, `MOMENTARY_COMPLETE`, and B->A restore, while Receiver B remained open externally.
- Task 026 proved direct physical Right Option momentary semantics are correct: hold opens Receiver B and release closes it.

## Task 027 Web audit conclusion
Task 027 existing-log comparison is accepted. The evidence upgrades the prior boundary from `ROOT_CAUSE UNKNOWN` to a proven lifecycle defect for the observed stuck-B failure.

FACT:
- Original mapped B DOWN: `flagsChanged`, keyCode 61, flags `0x00080140`; its copied replay returned through `VoiceKeyFilter` with the same Quartz timestamp, action `pass`, and flags `0x20080140`.
- Original mapped B UP: `flagsChanged`, keyCode 61, flags `0x00000100`, seq 49, Quartz timestamp `9904141163026`.
- A later event with the exact same key/type/Quartz timestamp returned at seq 58 with flags `0x20000100`, but action was `reconfiguration_suppress`, not `pass`.
- Source code retains mapped UP with `event.copy()`, preserves its timestamp, reposts the copy at `.cghidEventTap`, then the controller schedules B->A restore.
- `restorePrimaryMappingAfterSecondary` begins `VoiceKeyFilter.beginVoiceTriggerReconfiguration(...)`; the event tap drops any old/new trigger key while that gate is active using action `reconfiguration_suppress` and `return nil`.
- Therefore seq 58 is sufficiently correlated to the reposted copied B-UP: the reposted UP re-entered `VoiceKeyFilter` after B->A reconfiguration suppression became active and RemoteOrbit dropped its own release before it could pass downstream.

## Proven causal chain
```text
physical B release
-> original mapped Right Option UP captured/suppressed
-> output drain completes
-> copied B UP post(.cghidEventTap)
-> B->A restore starts too early
-> reconfiguration suppression becomes active for Right Option
-> reposted B UP re-enters VoiceKeyFilter
-> action=reconfiguration_suppress / return nil
-> Receiver B never receives the release
-> Receiver B remains open
```

Classification:
`B_REPLAY_UP_SELF_SUPPRESSED_BY_B_TO_A_RECONFIGURATION = PROVEN`

The replay-only `0x20000000` flag difference remains an observed event-shape difference but is not the first corrective target: replayed B DOWN carries the same extra bit and still opens Receiver B. Do not normalize flags or alter event source/tap level unless the ordered-release corrective fails hardware acceptance.

## Task 028 decision
Implement the smallest deterministic ordering correction. The B->A mapping/filter restore must not begin merely because `post(.cghidEventTap)` returned. It may begin only after the expected copied B-UP has re-entered `VoiceKeyFilter` and reached the pass path.

No fixed sleep/delay is allowed. Do not change BLE/audio/tail timing, hidutil destinations, trigger keys, generic gesture timing, event flags, source fields, event tap location, or normal dual synthetic-trigger policy.

TDD is mandatory: prove RED on the current code before product edits, then GREEN with the minimal change.

## Task 028 implementation result
- RED was captured before production edits: the new pending-UP and pass-ack tests failed compilation because the required pending ownership, acknowledgement, and replay-poster seams did not exist; the controller test also lacked a held-UP capture seam.
- GREEN focused suites: `VoiceKeyFilterTests` 16/16, `DualReceiverVoiceTransactionTests` 20/20, `VoiceTriggerRuntimeTests` 53/53, `VoicePressCoordinatorTests` 38/38.
- Full Swift suite: 394 tests, 0 failures. Self-tests: 3/3 PASS. Release build and package: PASS. Signature verification: PASS. `git diff --check`: PASS.
- Scope audit: only `main.swift` and the two focused test files changed for the product checkpoint. No HIDMonitor behavior, mapping authority, second event tap, BLE/audio/tail timing, generic gesture timing, flag normalization, event-tap relocation, or normal synthetic B-UP change.
- Installed candidate provenance matches product commit `f938b919e288a481f5eacaf9aad9c254dcf0cffe`. RemoteOrbit was restarted; Core Audio PID `590` and RemoteOrbitAudio driver PID `615` were unchanged. No remote gesture or physical Option test was performed.
- Next action: independent Web audit. Do not perform the Receiver-B hardware gate until separately authorized by that audit; do not merge.

Hardware acceptance remains user-only after a validated candidate is installed. No merge until Web audits the implementation and the user completes Receiver-B acceptance.
