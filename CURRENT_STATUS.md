# CURRENT_STATUS

Last updated: 2026-10-08
State: TASK 023 IMPLEMENTATION AND CANDIDATE INSTALL COMPLETE / WAITING FOR USER SET A
Repository: `Lost0rz/RemoteOrbit`

This file is the authority for mutable current project state. Historical detail remains preserved in Git history.

## Control-plane authority

- Audited authoritative parent control HEAD: `bf5579fc43f2efbe627dec03f4d0b52182a2848f`.
- Latency task `RO-DUAL-RECEIVER-MAPPING-LATENCY-GATE-022` is complete and Web-audited.
- Next active task: `RO-DUAL-RECEIVER-SYSTEM-MAPPED-IMPLEMENTATION-023`.
- Final design: `docs/superpowers/specs/2026-10-08-dual-receiver-system-mapped-trigger-design-final.md`.
- Implementation plan: `docs/superpowers/plans/2026-10-08-dual-receiver-system-mapped-routing.md`.
- Plan addendum after latency audit: `docs/superpowers/plans/2026-10-08-dual-receiver-system-mapped-routing-latency-addendum.md`.
- Preserved implementation base branch: `codex/dual-receiver-momentary-routing-v1` at `c90edbf73ad9b0642fa344734571c0e806c0eb73`.
- Preserved product HEAD: `ef29186e25c64cd4d1d7209cb2a41f95c51d4a11`.
- Authorized v2 branch: `codex/dual-receiver-system-mapped-routing-v2`.
- Authorized v2 worktree: `/private/tmp/remoteorbit-dual-receiver-system-mapped-routing-v2`.
- Validated and installed candidate source HEAD: `50a20174632dc105fb670a9b83e3f6feaa8e9f9b`; candidate was built from this exact commit.
- Current v2 branch tip is this closeout control-sync commit on the authorized branch; local and remote branch heads were verified equal after push.
- Task 12 full focused/full validation, self-tests, release package, diff check and scope audit completed.
- Installed app: `/Applications/RemoteOrbit.app`, version `0.2.13` build `42`, Bundle ID `com.lost0rz.RemoteOrbit`, executable SHA-256 `7bf64aaea9e988f4857d49509ac897e952bd6b67dd405585a486d6a1f1c4a219`; running RemoteOrbit PID `93962`.
- Only RemoteOrbit was restarted. No remote gesture, BLE/audio test, Set B/C, or merge was performed. Core Audio driver PID `615` was left running and untouched.
- Current stop boundary: `READY_FOR_USER_SYSTEM_MAPPED_SET_A`.
- Merge remains forbidden.

## Mapping latency gate result — PASS

Gate 022 measured the real `/usr/bin/hidutil --set` process boundary on the same Xiaomi remote match and A/B destinations used by `RemoteVoiceKeyMapping`.

A -> B, 50/50 successful:

```text
min     4.721000 ms
median  5.428063 ms
p90     6.076817 ms
p95     6.137273 ms
p99     6.488425 ms
max     6.698084 ms
```

B -> A, 50/50 successful:

```text
min     4.774709 ms
median  5.326646 ms
p90     6.190333 ms
p95     6.389208 ms
p99     6.621409 ms
max     6.703750 ms
```

Observed natural first-UP -> second-DOWN gap from prior hardware evidence:

```text
74.476 ms .. 239.547 ms
```

Therefore even the measured worst A->B sample retained:

```text
74.476 - 6.698084 = 67.777916 ms
```

of process-level margin versus the fastest observed user second press. A->B p95 retained `68.338727 ms` margin.

Pre-test mapping was empty, post-test mapping was restored to empty, and semantic restoration matched exactly. No product/test source changed; the app was not restarted; no remote gestures were performed.

Decision:

`MAPPING_LATENCY_GATE_PASS`

This authorizes v2 construction. It does not prove total production `first UP -> SECONDARY_READY` latency; v2 must log that end-to-end interval, including filter target update and reconfiguration-suppression completion. The measured process margin is sufficient to proceed while retaining fail-closed admission if a second DOWN still beats readiness.

## Frozen architecture

```text
idle dual mode:
F5 -> Receiver A mapping active
filter target = A

Direct LONG:
physical F5 -> system-mapped A -> HardwareOptionGate capture
350 ms classify A -> remote audio -> first PCM -> release captured A DOWN
release/drain -> captured A UP

First quick release:
discard captured A pair
-> guarded A -> B mapping transition
-> hidutil --set B success
-> filter target B
-> end transition suppression
-> SECONDARY_READY

Second LONG while SECONDARY_READY:
physical F5 -> system-mapped B -> HardwareOptionGate capture
350 ms classify B -> remote audio -> first PCM -> release captured B DOWN
release/drain -> captured B UP
-> restore B -> A
```

No normal A/B CGEvent synthetic trigger. No virtual-HID provider. No Persistent Session receiver authority.

## Runtime safety requirements

- `HIDMonitor` remains the only raw HID owner.
- `VoiceKeyFilter` / `HardwareOptionGate` remains the only mapped-edge owner.
- `RemoteVoiceKeyMapping` remains the only device-scoped mapping authority.
- Second DOWN before `SECONDARY_READY` fails closed; do not buffer or replay it later.
- A->B or B->A mapping failure fails closed.
- B->A restore failure blocks all new gestures until reconciliation.
- Do not add synchronous `hidutil --get` to the critical double-tap path.
- Keep asynchronous mapping readback as diagnostic evidence.
- Record end-to-end `FIRST_UP_TO_SECONDARY_READY_MS`, plus `A_TO_B_APPLY_MS` and `B_TO_A_APPLY_MS`.
- Generic button timing, BLE codec, tail/drain timing, Persistent Session semantics and diagnostic authority remain unchanged.

## Construction baseline

Do not rebuild the accepted 019 work from docs-only `main`.

Create v2 from:

```text
codex/dual-receiver-momentary-routing-v1
c90edbf73ad9b0642fa344734571c0e806c0eb73
```

Then sync only authoritative control/spec/plan/addendum files from `origin/main` before product mutation.

The reported local branch `codex/v0211-nonseize-hid-audit` is not an authority for task 023. Treat it read-only and do not use, delete or merge it during this task without separate attribution.

The pre-existing canonical dirty `remote-orbit/Sources/RemoteOrbit/KeyMapping/HIDMonitor.swift` remains protected: do not clean, stash, reset, restore or copy it into v2.

## Hardware boundary

After the full planned automated implementation and exact candidate install, STOP before user gestures at:

`READY_FOR_USER_SYSTEM_MAPPED_SET_A`

The user then performs Set A first. Do not proceed automatically to Set B or merge.
