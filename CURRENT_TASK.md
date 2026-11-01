# RemoteOrbit Current Task

## RO-DIAGNOSTICS-LEGACY-RETIREMENT-045 — Wave A diagnostics-gating corrective

Status: `CORRECTIVE_REQUIRED`
TASK_CLASS: `BOUNDED PRODUCT CORRECTIVE`
Repository: `Lost0rz/RemoteOrbit`
Design authority: `docs/design/2026-10-31-045-diagnostics-gating-and-legacy-retirement.md`
Human runtime acceptance: `Task 043 still DEFERRED / USER-OWNED`

## Audit result

Independent Web audit of PR #31 at reviewed head `856fcb065ab94ae01e210df7fa55561a4cfcf11a` returned:

`STOP — REQUIRED CORRECTIVE BEFORE MERGE`

The implementation's core diagnostics gate and machine regression are accepted as the starting point. Do not re-audit or redesign Wave A locally.

## Authorized corrective

Continue the existing Task 045A execution branch/worktree/PR. Perform only these corrections:

1. **Frontmost diagnostic observer runtime lifecycle**
   - when effective diagnostics transitions OFF→ON, the diagnostic frontmost-application observer must become active exactly once;
   - when effective diagnostics transitions ON→OFF, it must unregister/stop and own no notification observation;
   - repeated same-state transitions must be idempotent;
   - lifecycle changes must remain diagnostics-only and must not change application routing or mapping behavior.

2. **Recording independence regression**
   - add a deterministic test that exercises a real WAV/RAW recording lifecycle while effective diagnostics are OFF;
   - prove WAV/RAW data is still created/finalized by the independent recording opt-in;
   - prove structured recording diagnostic metadata is not persisted/enqueued through the disabled diagnostics authority path;
   - preserve existing recording-OFF behavior.

3. **Finite launch-only diagnostic work**
   - if locally achievable without crossing a frozen product boundary, avoid selected-input diagnostic registry lookup and run-start calibration/field construction while diagnostics are OFF;
   - if this cannot be done as a narrow diagnostics-only edit, leave it unchanged and report it explicitly rather than widening scope.

4. Update `CURRENT_STATUS.md` and `CURRENT_TASK.md` atomically for the corrected handoff.

## Frozen boundaries

Do NOT:

- remove/refactor Persistent-session production state;
- remove Dual-Receiver source/callers/tests;
- remove microphone SHORT UI/configuration;
- change the 300 ms LONG-only contract;
- change rapid-repress, pre-HID, BLE READY/reuse, drain/tail/grace behavior;
- change HID mapping/readback correctness semantics;
- change receiver-readiness polling architecture;
- change ATVV commands/codec/sample rate/gain or AudioPipe transport/buffer/IOProc;
- install/replace the app;
- install/reload driver, restart CoreAudio, modify TCC/default devices;
- tag/release or merge PR #31.

## Verification required

Run focused tests proving:

- frontmost observer OFF→ON starts once;
- ON→OFF stops/unregisters;
- repeated state transitions remain bounded/idempotent;
- diagnostics OFF + recording ON produces valid/finalized WAV/RAW while diagnostic structured work remains suppressed;
- existing diagnostics gate tests remain green;
- current LONG-only regression tests remain green.

Then run the existing durable machine gate on `remoteorbit-macmini` for the corrected PR head:

- source/protocol checks;
- full `swift test`;
- native Release build;
- Universal2 build-only packaging smoke.

## Delivery / stop

Push the corrected existing branch and keep PR #31 OPEN/DRAFT. Stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`. Do not merge.

Return actual changed paths, corrected head/remote identity, focused/full test results, CI run identity, and any unresolved blocker/uncertainty.
