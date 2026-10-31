# RemoteOrbit Current Task

## RO-IME-READINESS-PROMPT-SYNC-043 — Human runtime acceptance gate

Status: `HUMAN_ACCEPTANCE_PENDING`
TASK_CLASS: `VERIFY / HUMAN_ACCEPTANCE`
Repository: `Lost0rz/RemoteOrbit`
Active authority branch: `codex/ime-readiness-stability-043`
Remote-verified branch HEAD: `4493657ae266072b95b159e539fa2e7fb6aa2a35`
Accepted product source: `ed96d2285b7a3a24aecb30c09aebc38ccc4c4b16`

## Current authority

Task 043 is the only active product/runtime task. The CI migration task
`RO-CI-SELF-HOSTED-RUNNER-MIGRATION-20261031` is CLOSED by merged PR #29 at
`489af61a1b081781bcc386fe7476bc37479c79dd`.

No new product implementation is authorized by this control transition.

## Required human acceptance

The user owns final Task 043 runtime acceptance. Record only explicit PASS/FAIL for:

1. quick SHORT tap -> no visible action / no Doubao voice session;
2. normal LONG -> Doubao voice input opens and receives audio;
3. LONG release -> normal drain/close;
4. SHORT followed immediately by LONG -> LONG opens exactly once;
5. repeated LONG / release / LONG;
6. several rapid/repeated LONG interactions around the accepted Doubao
   post-processing edge;
7. HUD/readiness activates only for admitted LONG and clears after release;
8. runtime/resource soak shows no recurrence of the prior CoreAudio listener/memory
   amplification failure.

## Allowed actions now

- read-only source/runtime evidence review;
- collect/finalize already-authorized Task 043 runtime/resource evidence;
- record the user's explicit PASS or FAIL;
- if PASS, perform the separately governed Task 043 closeout/audit/merge transition;
- if FAIL, freeze the fresh incident and return to minimum-observable incident work.

## Forbidden until Task 043 PASS and closeout

Do not modify product source, voice semantics, BLE/ATVV, AudioPipe, HID, readiness,
HAL driver, TCC, CoreAudio configuration, or start the planned legacy retirement /
diagnostic gating implementation.

## Planned next task — not authorized yet

`RO-VOICE-LEGACY-RETIREMENT-DIAGNOSTICS-GATING-045`

The next task is already design-scoped but remains blocked. Its intended boundary is:

- existing `记录运行日志` becomes the authority for persistent runtime diagnostic
  logging, including ordinary log, voice diagnostic JSONL, diagnostic authority
  journal, runtime-health heartbeat, and other persistent diagnostic emission;
- `保存调试录音` remains independent and opt-in;
- logging OFF must avoid persistent diagnostic writes and unnecessary serialization /
  scheduling work, while bounded in-memory correctness counters/state may remain;
- retire Persistent Session and Dual Receiver product semantics, UI/configuration,
  runtime ownership paths, stale migration, and obsolete contract tests;
- preserve LONG-only candidate, SHORT tombstone/discard, mapped-trigger suppression,
  pending re-press, synthetic fallback, pre-HID candidate/prebuffer, BLE READY reuse,
  output drain, and current Task 043 readiness behavior;
- add source-contract and regression tests preventing legacy authority from returning;
- verify on `remoteorbit-macmini`, then require independent source audit and final
  human runtime acceptance before merge.

Do not create the implementation branch from current `main`: Task 043 accepted source
has not yet been closed/merged, so doing so would build the retirement task on the
wrong product baseline.

## Next action

Wait for explicit human Task 043 `PASS` or `FAIL`. Read-only planning may continue;
product mutation may not.
