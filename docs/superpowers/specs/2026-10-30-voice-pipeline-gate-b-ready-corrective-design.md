# Gate B Strict ATVV READY Corrective

**Task:** `RO-VOICE-PIPELINE-SIMPLIFICATION-042`

## Intent

Make `READY` truthful: the existing dedicated BLE queue may transition the
transport to READY only after all three required ATVV characteristics are
discovered, both required notify subscriptions are positively confirmed by
`didUpdateNotificationState`, and capabilities have been accepted.

## Selected approach

Extend the existing queue-owned `BLEVoiceTransportState` with the readiness
facts and one `evaluateATVVReadiness()` transition path. Characteristic discovery,
notification confirmation, and capability acceptance only record facts and then
call that evaluator. The evaluator is idempotent and calls the existing READY
transition once; `requestMicOpenIfReady()` additionally requires strict READY.

This is smaller and keeps the current single writer than introducing a new
transport object. Treating discovery-time `isNotifying` as confirmation is
rejected because it does not prove the delegate confirmation contract.

## Required facts and failure behavior

- Discovered: audio, command, and control characteristics.
- Confirmed: audio and control notifications, only from successful
  `didUpdateNotificationState` callbacks with `isNotifying == true`.
- Accepted: ATVV capabilities.
- Either arrival order remains CONNECTING until the final fact is recorded.
- Notify error/disabled state enters the existing failure/reset path.
- `clearTransportState`, new connection setup, and disconnect/reset clear all
  readiness facts. Existing `CBPeripheral` identity/current-transport guards
  reject obsolete callback objects.
- Normal voice close retains confirmed facts and READY for reuse.

## Non-goals

No ATVV bytes or protocol semantics, queue model, connection persistence,
post-release grace, 350ms drain, 600ms safety timeout, AudioPipe, CoreAudio,
jitter, Gate A semantics, driver, packaging, install, TCC, Air, or Gate C/D/E
changes.

## Verification

Add pure state tests for capabilities-first, notify-first, partial notify,
notify failure, reset clearing, READY reuse, and strict MIC_OPEN eligibility.
Run the required focused suites, full Swift tests, both release builds,
protocol self-tests, and `git diff --check`. Update both control files in one
completion commit and stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`.

**TASK_RECONCILIATION_REQUIRED:** NO

**DURABLE_DOCUMENT:** This file.
