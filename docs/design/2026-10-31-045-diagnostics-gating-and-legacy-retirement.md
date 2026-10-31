# Task 045 — diagnostics gating and legacy voice retirement audit/design

Date: 2026-10-31
Repository: `Lost0rz/RemoteOrbit`
Audited authority: `main@650a2c011bb640379842ab866d696302c4adc52e`
Status: `ACCEPTED DESIGN / WAVE_A_READY_FOR_IMPLEMENTATION_HANDOFF`

## Objective

Reduce RemoteOrbit's normal-mode diagnostic overhead to near-zero when ordinary diagnostics and audio recording are disabled, then retire obsolete Persistent-session and Dual-Receiver product authority without changing the accepted LONG-only microphone contract.

This task deliberately separates diagnostics from correctness. A symbol's historical name is not evidence that the mechanism can be deleted.

## Decision classes

### USER / PROJECT DECISIONS

- RC003 microphone SHORT before 300 ms is an absolute user-visible no-op.
- LONG at/after 300 ms enters the direct remote-voice lifecycle; release drains/closes through the direct path.
- Persistent and Dual-Receiver semantics are not current production authorities.
- Final combined RC003/Doubao human acceptance remains user-owned and may occur after machine/source work is merged.
- Normal development may continue before that deferred human acceptance.

### VERIFIED FACTS / CONSTRAINTS

1. `Log.write()` already returns before text-file work when `AppStorage.loggingEnabled == false`, and `Log.setEnabled(false)` closes its handle.
2. `VoiceDiagnosticLogger.startRun()` creates/truncates/opens `voice-diagnostic-current.jsonl`; `main.swift` currently starts it unconditionally. `VoiceDiagnosticLogger.log()` still captures timestamps and enqueues writer work unless a new front gate is added.
3. `DiagnosticAuthorityService.emit()` currently performs semaphore admission, timestamp capture and writer-queue enqueue without consulting `AppStorage.loggingEnabled`.
4. `DiagnosticRuntimeHealthService.shared.start()` is currently called unconditionally at app launch and owns a repeating heartbeat timer.
5. `VoiceAttemptDiagnostics.shared` constructs a `VoiceStartWatchdog` with automatic scheduling enabled. The watchdog is diagnostic-only: observed code emits stall/failure evidence and does not retry or mutate the voice transport.
6. `AudioPipe.beginRemoteAudioDiagnostics()` currently starts per-session diagnostic capture and a 50 ms `MainQueueResponsivenessProbe` regardless of the ordinary logging toggle.
7. Long-term observability currently follows ADR-0003's old `L1 summary: always on` policy. Session end builds/emits a summary and anomaly traces through `DiagnosticAuthority`.
8. WAV/RAW recording is separately gated by `AppStorage.recordingEnabled`; `BLEBridge.createRecordingIfEnabled` returns without constructing `WavRecorder` when disabled.
9. `VoiceInputProfileStore` is already the current single voice-trigger configuration authority. Its migration explicitly seeds from the old momentary trigger only; Persistent and Receiver-B values are deliberately excluded.
10. Settings still exposes obsolete Persistent, configurable microphone SHORT, and Receiver-B UI. `KeymapOverlay` still labels a microphone single-click as `输入法持续会话`.
11. `DualReceiverVoiceMode`, `DualReceiverVoiceGestureRecognizer`, and `DualReceiverMappedTriggerState` exist solely for the retired A/B product path.
12. `main.swift` still contains substantial Persistent and Dual runtime orchestration despite the current direct LONG-only path.
13. `beginShortTapDiscard` and `transferShortTapDiscardToAudioOnlySuppression` retain historical Persistent terminology but are also used by the current LONG-only late-mapped-edge/tombstone handoff. They cannot be deleted with the retired feature.
14. Generic `VoiceKeyFilter`, hardware Option ownership, `EventSuppressor`, `RemoteVoiceKeyMapping` verification/readback, pre-HID candidate ownership, BLE READY reuse, output-drain ownership, and post-release grace remain part of current correctness and must not be gated as diagnostics.

## Selected architecture

### 1. One effective diagnostics runtime gate

Introduce one process-local diagnostics gate/controller whose effective state is:

```text
effectiveDiagnosticsEnabled = persisted ordinary logging enabled
                              OR REMOTE_ORBIT_DIAGNOSTICS=1
```

The hot-path read must use a cheap thread-safe in-memory value. It must not read UserDefaults, touch disk, serialize JSON, or dispatch synchronously on every observation.

`AppStorage.loggingEnabled` remains the persisted user preference and the Settings toggle remains the user-facing control. The explicit environment variable remains a force-on development override. Audio recording remains independent and must not imply diagnostics-on or vice versa.

When the user toggles diagnostics ON, the controller may start structured diagnostic services. When toggled OFF, it first prevents new diagnostic work and then cancels/stops recurring diagnostic services. Finite work already queued before disable may drain, but no new persistent timer/writer activity may remain.

Rejected alternatives:

- **Gate only `Log.write()`: rejected** because structured diagnostics, health, long-term observation and per-session probes bypass it today.
- **Gate only journal append:** rejected because clock capture, event construction, writer enqueue and recurring timers would still consume resources.
- **Delete diagnostics entirely:** rejected because explicit incident diagnostics/export remain valuable and are already mature.

### 2. Disabled mode is behaviorally inert

With diagnostics OFF:

- `VoiceDiagnosticLogger` does not create/open/truncate a file and `log()` returns before timestamp/field/enqueue work;
- `DiagnosticAuthority.emit()` returns before semaphore admission, clock capture, event construction or writer enqueue;
- runtime-health heartbeat owns no timer;
- voice-start watchdog owns no recurring timer;
- `VoiceTimingLogger` does not maintain a live diagnostic timeline beyond any tiny identity state required to preserve caller API behavior;
- long-term observability performs no persistent summary/trace emission and no main-queue responsiveness sampling;
- `AudioPipe.beginRemoteAudioDiagnostics()` does not start the 50 ms main-queue probe or realtime diagnostic capture;
- ordinary diagnostic disk writes are zero;
- with recording also OFF, WAV/RAW file creation/writes are zero.

Any API identity needed so existing production callers do not branch differently may remain as bounded in-memory state. Such retained state must have no timer, writer, serialization or disk side effect.

### 3. Correctness remains always-on

The diagnostics gate MUST NOT control:

- voice candidate/hold classification;
- Option/mapped-edge gating and tombstone ownership;
- trigger DOWN/UP balancing;
- remote route activation/deactivation;
- BLE transport, ATVV decode, keepalive or READY reuse;
- pre-HID candidate/prebuffer;
- output drain and tail ownership;
- post-release grace;
- receiver-readiness polling used for current product HUD state;
- HID mapping application/readback used to establish mapping correctness;
- CoreAudio IOProc/output path.

Diagnostic logging around these mechanisms may be gated; the mechanisms themselves may not.

## Classification — Wave A diagnostics

| Surface | Decision | Reason |
| --- | --- | --- |
| `Log.swift` | KEEP / ALREADY GATED | Text log has an appropriate disabled fast path. |
| `VoiceDiagnosticLogger` | GATE | File lifecycle, timestamps, enqueue, JSON and sync must disappear disabled. |
| `DiagnosticAuthorityService.emit` | GATE | Disabled return must occur before semaphore/clock/queue. |
| `JSONLinesDiagnosticJournal` | KEEP BACKEND | Retain explicit diagnostics/query backend; it becomes unreachable from disabled emit. |
| `DiagnosticRuntimeHealthService` | GATE | No heartbeat timer disabled. |
| `DiagnosticRuntimeHealthRegistry` | GATE or bounded inert state | No persistent work; retain only cheap state if required by API compatibility. |
| `VoiceAttemptDiagnostics` identity | KEEP-IN-MEMORY | Preserve caller identity semantics without persistence/timers. |
| `VoiceStartWatchdog` | GATE | Diagnostic-only; enabled mode may schedule lazily per active attempt, disabled owns no timer. |
| `VoiceTimingLogger` | GATE | Diagnostic-only timeline and prints/events. |
| `LongTermObservabilityService` | GATE | Old always-on persistence policy is superseded. |
| fixed-capacity trace storage | KEEP-IN-MEMORY / inactive disabled | Preallocation may remain, but no disabled active mutation required. |
| `MainQueueResponsivenessProbe` | GATE | Diagnostic recurring 50 ms sampling. |
| `AudioPipe` transport/IO | KEEP-ALWAYS | Product correctness path. |
| `AudioPipe` diagnostic lifecycle | GATE | No per-session diagnostic probe/capture disabled. |
| WAV/RAW recorder | KEEP SEPARATE | Already explicit opt-in; independent from ordinary diagnostics. |
| HID mapping/readback correctness | KEEP-ALWAYS | Establishes mapping authority/fail-closed state; gate only its observations. |

ADR-0003's `L1 summary always on` statement is superseded by this task for production runtime policy. Explicit diagnostics-on mode retains durable summary/trace/export capability.

## Classification — Waves B/C legacy retirement

### DELETE / RETIRE FROM PRODUCTION

- microphone SHORT action configuration (`persistentIME`, `codexVoiceChat`) for the RC003 microphone button;
- Persistent-session settings labels and live controls;
- Receiver-B / second-receiver settings and live controls;
- `VoiceSessionMode.persistentOpen`, persistent toggle state/events/callbacks and audio-only Persistent segment behavior;
- AppController's Dual-Receiver recognizer/mode/A↔B mapping orchestration;
- `DualReceiverVoiceMode.swift`;
- `DualReceiverVoiceGestureRecognizer.swift`;
- `DualReceiverMappedTriggerState.swift`;
- tests whose sole contract is that Persistent or Dual-Receiver remains a supported product mode.

### MIGRATION-ONLY

- legacy momentary/voice-trigger preference may continue to seed `VoiceInputProfile` once for compatibility;
- Persistent and Receiver-B stored values must not remain runtime authorities and should not seed the current profile.

### KEEP / RENAME / RECOMMENT

- `VoiceInputProfile` and selected profile persistence;
- generic hardware Option gate and synthetic fallback;
- short-discard / late-mapped-edge tombstone ownership needed by LONG-only handoff;
- suppression handoff used by rapid SHORT→LONG and late mapped edges;
- EventSuppressor;
- RemoteVoiceKeyMapping single-profile mapping + verification;
- pre-HID physical candidate, AudioPipe candidate/prebuffer, BLE READY reuse, output drain, post-release grace;
- current LONG-only regression tests.

Historical dual/persistent plans, specs and incidents remain as `HISTORICAL-DOC`; they are not production authority and do not need deletion.

## Implementation waves

### Wave A — diagnostics gating

Bounded implementation only. Do not remove Persistent/Dual production code in this wave.

Likely touched boundaries:

- a small diagnostics runtime gate/controller;
- startup/toggle lifecycle in `main.swift` / Settings;
- `VoiceDiagnosticLogger`;
- `DiagnosticAuthorityService`;
- `DiagnosticHardening` runtime-health/watchdog lifecycle;
- `VoiceTimingLogger` / long-term observability enablement;
- `AudioPipe` diagnostic lifecycle;
- focused diagnostics tests and ADR/documentation updates.

Do not change voice semantics, BLE commands, AudioPipe buffering/gain/sample rate, receiver-readiness architecture, HID mapping semantics, or driver/runtime installation.

### Wave B — product UI/config retirement

Remove obsolete microphone SHORT/Persistent/Receiver-B UI and live configuration authority; make overlays/settings represent LONG-only behavior. Keep `VoiceInputProfile` as the single trigger destination authority.

### Wave C — runtime/test retirement

Remove Persistent/Dual runtime state machines/files/callers; rehome any still-valid generic gate/tombstone tests and rename historical terms where they now describe generic LONG-only correctness.

### Wave D — final regression/resource audit

Run full machine regression and object/timer invariants, then return for independent web audit. Human RC003/Doubao acceptance remains user-owned.

## Wave A acceptance matrix

Diagnostics OFF + recording OFF must establish:

- no `voice-diagnostic-current.jsonl` run creation caused by normal launch;
- no `DiagnosticAuthority.emit` queue admission/writer enqueue caused by normal events;
- no diagnostic journal append caused by normal events;
- no runtime-health heartbeat timer;
- no voice-start watchdog recurring timer;
- no per-session main-queue responsiveness timer;
- no WAV/RAW files;
- LONG-only production behavior tests unchanged.

Diagnostics ON must establish:

- VoiceDiagnosticLogger structured records still work;
- DiagnosticAuthority journal/query/snapshot still work;
- runtime health and voice-start diagnostic evidence still work;
- long-term summary/anomaly trace behavior remains testable;
- explicit diagnostic export remains functional.

Recording ON must remain independently testable whether or not ordinary diagnostics are on.

Machine gate for every implementation wave that changes source:

- focused tests for changed boundary;
- full `swift test`;
- native Release build;
- Universal2 build-only packaging smoke on `remoteorbit-macmini`;
- no app install, HAL/driver mutation, CoreAudio/TCC/default-device mutation, tag or release.

## Resource/object invariants for final closeout

With diagnostics disabled:

```text
VoiceDiagnosticLogger persistent writer/file = inactive
DiagnosticAuthority producer enqueue          = 0
runtime-health heartbeat timers               = 0
voice-start diagnostic watchdog timers        = 0
main-queue diagnostic probe timers             = 0
WAV/RAW writers (recording off)                = 0
```

Correctness bounds remain:

```text
receiver-readiness active timer <= 1
long-only candidate timer       <= 1
pending direct-repress owner    <= 1
AudioPipe IOProc                <= 1
HID monitor/event suppressor    bounded by existing role contracts
```

## Test retirement/rehome rules

Pure Dual suites may be deleted only after their production source/callers are removed. Persistent suites may be deleted only after unique generic late-edge/suppression/release assertions are shown to exist in current LONG-only suites or are rehomed there.

Expected pruning targets later include:

- `DualReceiverVoiceGestureRecognizerTests`
- `DualReceiverVoiceModeTests`
- `DualReceiverVoiceSettingsTests`
- `DualReceiverVoiceTransactionTests`
- `VoicePersistentSessionTests`
- `VoicePersistentShortTapTests`
- Persistent/Dual cases inside `VoiceTriggerRuntimeTests`, `VoiceTriggerKeyTests`, `VoiceOptionTriggerTests`, and `KeymapOverlayTests`.

Keep/regress current LONG-only coverage in `VoicePressCoordinatorTests`, `VoicePipelineSimplificationTests`, `VoiceKeyFilterTests`, `BLEBridgeTests`, `DisabledShortClassifierTests`, and `VoiceReceiverReadinessTests`.

## Consequences

Normal operation becomes cheaper and easier to reason about; explicit diagnostics become opt-in rather than a parallel always-on runtime. This intentionally reduces evidence available for incidents that occur while diagnostics are disabled. A future incident may therefore require enabling diagnostics and reproducing a fresh incident.

Legacy retirement reduces code/test surface but must be staged after diagnostics gating so a regression can be attributed to one boundary at a time.

## Reversibility

Diagnostics gating is reversible by enabling the existing persisted diagnostics preference or the explicit environment override. Legacy retirement is less trivially reversible, which is why it is separated into later waves and requires independent audit before merge.

REVERSAL_TRIGGER: if Wave A changes any user-visible voice behavior or causes a current LONG-only regression, revert/repair Wave A rather than compensating in the voice state machine.

## Design convergence

Selected design meets the requested performance/cleanup objective while preserving current correctness owners and explicit diagnostic capability. No unresolved architecture decision blocks Wave A.

TASK_RECONCILIATION_REQUIRED: YES
REASON: audit-only Task 045 authority must advance to a bounded diagnostics-gating implementation handoff before product mutation.
DURABLE_DOCUMENT: `docs/design/2026-10-31-045-diagnostics-gating-and-legacy-retirement.md`
