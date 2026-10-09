# CURRENT_STATUS

Last updated: 2026-10-09
State: TASK 028 SINGLE RECEIVER-B HARDWARE GATE + CAUSAL LOG VALIDATION PASS / USER 5x RECEIVER-B STABILITY GATE AUTHORIZED / MERGE FORBIDDEN
Repository: `Lost0rz/RemoteOrbit`

## Authority
- Audited control parent: `2d238cf1d85b0e0aa6ce9475c71dcc8b459e2b6b`.
- Corrective branch: `codex/dual-receiver-b-up-replay-ack-fix`.
- Product implementation / installed source: `f938b919e288a481f5eacaf9aad9c254dcf0cffe`.
- Final corrective branch HEAD: `85bb2e12cad41198e5a27d9e610cbdb30b01d357`.
- Installed candidate remains `/Applications/RemoteOrbit.app`, version `0.2.13` build `42`, Bundle ID `com.lost0rz.RemoteOrbit`, RemoteOrbit PID `39949` by the accepted single-run evidence.
- Merge remains forbidden.

## Accepted prior evidence
- Set A passed 5/5 on the system-mapped Left Option hardware path.
- Corrective 024 fixed the dual-mode microphone legacy 180 ms debounce conflict.
- Task 025/027 proved the stuck-B defect: reposted copied Right Option UP could be swallowed by B->A reconfiguration suppression before downstream delivery.
- Task 026 proved direct physical Right Option hold/release has correct Receiver-B momentary semantics.
- Independent Web source audit accepted Task 028 implementation: pending replay-UP ownership blocks reconfiguration; exact replay acknowledgement is checked before suppression; B->A restore is allowed only after acknowledgement.

## Task 028 first user hardware gate — PASS
User report: Receiver B opened normally, physical release closed B normally, no stuck state.

Accepted read-only evidence for gesture `5A66F46A-5817-48E1-9A14-3C903B7AD55D`:
- evidence window `2026-10-09 11:35:23.831–11:35:28.037 +08:00`, seq 492–550;
- first-UP -> secondary-ready `22.797 ms`;
- second-DOWN gap `139.672 ms`; second raw DOWN emitted and B was ready before the edge;
- B mapped hardware gate began, B classified hold, first PCM preceded B DOWN replay;
- original B UP captured as `flags_changed`, keyCode 61, Quartz timestamp `11046382134235`;
- output drain completed, then `REPLAY_UP_PENDING -> REPLAY_UP_POSTED -> REPLAY_UP_PASS_ACK`;
- replay ACK matched the same Right Option key/type/original Quartz timestamp;
- matching replay-UP `reconfiguration_suppress` count = 0;
- replay pass acknowledgement seq 543 preceded B->A restore begin seq 544;
- B->A restore succeeded; final mapping/filter returned to `left_option`, phase `primaryReady`, transaction/gate none, BLE idle;
- normal synthetic trigger DOWN/UP count remained 0/0;
- replay flag `0x20000100` remained unchanged by product code and did not prevent successful external B close.

## Causal validation conclusion
Task 028 is causally validated for one real hardware sample:

```text
captured B UP
-> output drain
-> REPLAY_UP_PENDING
-> REPLAY_UP_POSTED
-> REPLAY_UP_PASS_ACK
-> no matching reconfiguration_suppress
-> B->A restore
-> primaryReady / idle
```

This is the corrected ordering predicted by the Task-027 root cause and it coincides with the external user result: B opened and closed normally.

## Current authorization
User-only Receiver-B 5-run stability gate is authorized now.

Perform five natural independent samples, each:

```text
quick first tap -> immediate second LONG -> speak briefly -> physical release
```

For every sample require:
- first quick tap opens neither receiver;
- second LONG opens Receiver B only;
- Receiver A does not open;
- physical release closes Receiver B normally;
- no duplicate text;
- no stuck state.

Do not deliberately slow the second press. If any sample fails, STOP immediately and preserve that first failing sample; do not continue to overwrite it. No Set C and no merge until the 5-run gate is accepted and read-only evidence is reviewed.
