# Dual-Receiver Momentary Routing — Implementation Plan

Date: 2026-10-08
Task: RO-DUAL-RECEIVER-MOMENTARY-ROUTING-018
Plan state: ready for independent Web audit
Planning base: ab43ce0e8ac7cb3c3fcd1ccfd078e65f75e8d903 (origin/main at plan construction)
Candidate corrective: 172427957fd18a2b5827edd1cb1c4bddb6a5b7db
Planning branch/worktree: codex/dual-receiver-momentary-routing-v1-plan / /private/tmp/remoteorbit-dual-receiver-momentary-routing-v1-plan

This plan does not authorize implementation, build, install, restart, or hardware
actions. A later implementation task must read the then-current controls and
explicitly authorize the listed source changes. If the design spec or accepted
contract changes before then, stop and re-plan from the new authority.

## Frozen contract and invariants

~~~text
Direct LONG                     -> Receiver A
Quick first tap + second LONG   -> Receiver B
Quick single tap                -> no action

Initial A key                   -> Left Option
Initial B key                   -> Right Option
LONG_THRESHOLD_MS               -> 350
DOUBLE_WINDOW_MS                -> 300
~~~

- Receiver A and B are independent momentary transactions; neither depends on
  external Persistent Session state.
- First decoded PCM is the only trigger-DOWN authorization boundary. The
  transaction sends exactly one selected-key DOWN and balances it with UP for
  the key captured by that transaction.
- While dual mode is active, remote F5 has no receiver hidutil mapping. The
  existing HIDMonitor remains the sole raw HID owner and its existing
  EventSuppressor parks the native F5 path. Do not add another HID manager or
  suppressor.
- First DOWN may call prepareVoiceTransport() only. micOpen, route activation,
  and receiver edges wait for A/B classification; receiver DOWN additionally
  waits for first PCM.
- The generic ButtonGestureRecognizer and its 250 ms double-click timing do
  not own microphone routing and must not be changed for this feature.
- Persistent trigger storage/semantics remain separate. Secondary trigger Off
  preserves the current single-receiver path. Dual mode requires SHORT Disabled
  and distinct A/B keys. Reject key/mode edits while gesture, transaction,
  deferred press, output drain, release, or runtime reconfiguration owns the
  voice path.
- If HID/EventSuppressor cannot safely own raw F5 in dual mode, fail closed;
  never fall back to an exposed F5 event or guess a receiver.
- Reuse VoiceDiagnosticLogger; add only bounded semantic events required to
  establish classification, selected key, and transaction boundaries.

## Baseline and execution protocol

1. Record the exact implementation base SHA as IMPLEMENTATION_BASE. The
   implementation checkout must be created from the latest verified
   authoritative origin/main, after re-reading AGENTS.md, CURRENT_STATUS.md, and
   CURRENT_TASK.md. A later documentation-only main successor is acceptable only
   if the task/spec/product contract and scope are unchanged. Any product-source,
   test-contract, or authorization change stops construction pending reconciliation.
2. Do not start implementation from the stale candidate branch. The current
   candidate/main comparison has exactly four changed paths: stale
   CURRENT_STATUS.md, stale CURRENT_TASK.md, and the two accepted corrective
   files below. Relative to current origin/main, its source change is the
   Disabled SHORT classifier decision and its test change is the hardware-path
   quick-release regression. In implementation Task 1, import only:
   remote-orbit/Sources/RemoteOrbit/main.swift and
   remote-orbit/Tests/RemoteOrbitTests/DisabledShortClassifierTests.swift.
   Do not merge/cherry-pick the candidate branch or import either control file.
3. Prove the initial corrective diff is limited to those two files and only the
   accepted behavior: Disabled binding has
   bypassesShortClassification == false; quick release returns to idle with
   hardware gate begin/cancel once, no hold, no route preparation, no short
   replay, and no synthetic edge. Confirm the existing 300 ms legacy classifier
   threshold is unchanged. If the source/test diff contains unrelated behavior,
   stop before feature work.
4. Every implementation task below follows RED → smallest GREEN → focused
   regressions. Run the listed SwiftPM commands from repository root; each uses
   --package-path remote-orbit. Run ./remote-orbit/run-self-tests.sh from
   repository root as well. Preserve test names, source boundaries, and task
   commits so the Web audit can review each seam.
5. No implementation task may merge. Hardware gates require a separately
   authorized test runtime and a human to operate the real receivers; this
   planning task grants neither. Never modify receiver shortcuts, TCC,
   Accessibility/Input Monitoring, driver, CoreAudio, or unrelated audio/BLE
   behavior.

## Source-anchor audit — verified on the planning base

- `remote-orbit/Sources/RemoteOrbit/main.swift` contains
  `RemoteVoiceKeyMapping` (one F5-to-modifier mapping or an empty mapping), the
  300 ms `VoicePressCoordinator`, the AppController microphone entry point,
  `AUDIO_FIRST` handling, and the existing callback wiring from `.holding` to
  `BLEBridge.activateVoiceInput()` and from pending preparation to
  `prepareVoiceTransport()`.
- `remote-orbit/Sources/RemoteOrbit/VoiceOptionTrigger.swift` already has one
  active session owner and captures `activeTriggerKey` for matching UP/abort;
  the current `sendDown(sessionID:purpose:)` chooses the configured momentary
  key. `VoiceTriggerKey.swift` defines the six available modifier choices.
- `remote-orbit/Sources/RemoteOrbit/BLEBridge.swift` already separates
  `prepareVoiceTransport()`, `activateVoiceInput()`, and
  `cancelVoiceTransportPreparation()`; the plan keeps that boundary.
- `AppStorage.swift` currently separates legacy, momentary, and Persistent
  trigger preferences, with no secondary momentary preference. SettingsView
  exposes the direct-long and Persistent keys separately.
- `HIDMonitor.swift` owns one `EventSuppressor`; raw reports update its held
  state before semantic edge delivery. `EventSuppressor.swift` uses the
  existing head-insert `cghidEventTap`; `ButtonDefinitions.swift` maps the
  microphone native event to F5/keyCode 96. Existing tests are in
  `EventSuppressorTests.swift`, `RemoteVoiceKeyMappingTests.swift`,
  `VoicePressCoordinatorTests.swift`, `VoiceOptionTriggerTests.swift`,
  `BLEBridgeTests.swift`, `VoiceTriggerRuntimeTests.swift`, and
  `VoicePersistentSessionTests.swift`.
- The generic `ButtonGestureRecognizer` has its own delayed single/double
  action path. The voice design stays outside it so its global timing and
  non-microphone behavior remain unchanged.

The current candidate comparison was read directly from Git objects after the
fresh fetch. Relative to audited `origin/main`, exactly four paths differ:
the two stale control files plus the exact `main.swift` and
`DisabledShortClassifierTests.swift` corrective paths named above. Do not
transplant its branch history or control files.

## Task 1 — Authoritative implementation baseline + accepted corrective

**Goal**
Start from latest authoritative main and adopt only the independently accepted
Disabled-SHORT corrective before dual-mode work.

**Exact files**
- remote-orbit/Sources/RemoteOrbit/main.swift
- remote-orbit/Tests/RemoteOrbitTests/DisabledShortClassifierTests.swift

**RED first**
Copy/apply only the candidate DisabledShortClassifierTests.swift delta to the
clean latest-main implementation worktree. Do not apply the source hunk yet.
Run:

~~~sh
swift test --package-path remote-orbit --filter DisabledShortClassifierTests
~~~

Expected RED: tests fail against current main because Disabled SHORT still
bypasses classification / enters holding immediately, including the
hardware-option quick-release assertions.

**Smallest implementation**
Apply only the candidate main.swift classifier hunk that makes
AppController.bypassesShortClassification(for:) return false. Retain the
production Disabled no-op short callback and preserve the existing 300 ms
threshold. Do not copy candidate control documents or other candidate history.

**GREEN and regressions**

~~~sh
swift test --package-path remote-orbit --filter DisabledShortClassifierTests
swift test --package-path remote-orbit --filter VoicePressCoordinatorTests
~~~

Expected GREEN: quick Disabled release is pending then idle and is dropped;
true hold promotes only after the existing threshold. Review git diff --check,
git diff --name-only "$IMPLEMENTATION_BASE", and the exact source/test hunks.

**Commit boundary**
One baseline commit containing only the two listed files and the accepted
corrective. Record exact base, candidate SHA, resulting HEAD, test output, and
diff in task controls/evidence.

**PASS / STOP**
PASS only when focused suites pass and the only diff is the accepted corrective.
STOP if transplanting either candidate file would overwrite unrelated current
main work or if the initial diff is broader than the corrective.

## Task 2 — Pure microphone-specific dual-receiver classifier TDD

**Goal**
Add deterministic gesture classification independent of BLE, UI callbacks,
synthetic input, and the generic button recognizer.

**Exact files**
- Add remote-orbit/Sources/RemoteOrbit/DualReceiverVoiceGestureRecognizer.swift.
- Add remote-orbit/Tests/RemoteOrbitTests/DualReceiverVoiceGestureRecognizerTests.swift.

**RED first**
Write deterministic tests against an injected monotonic-time/scheduler seam for:
direct hold → A exactly once; first quick release + second hold → B exactly
once; one quick tap + timeout → none; two quick taps → none; first/second
release at 349 ms vs 350 ms; second DOWN at 299/300 ms vs 301 ms after first UP;
stale timer after cancellation/new gesture; HID disconnect/explicit cancel clears
pending state without classification. State remains voice-specific. Run:

~~~sh
swift test --package-path remote-orbit --filter DualReceiverVoiceGestureRecognizerTests
~~~

Expected RED: test target cannot build because the recognizer/API does not yet
exist. Use monotonic event timestamps and a fake scheduler; do not sleep in
classifier unit tests. Define the 300 ms deadline as inclusive (<= 300 ms) and
assert that edge explicitly.

**Smallest implementation**
Implement explicit states (idle, first press pending, waiting for second, second
press pending, classified A/B) with injected scheduling/cancel and monotonic
timestamps. Emit one classification or no-action result, never a trigger edge.
Keep ButtonGestureRecognizer untouched.

**GREEN and regressions**

~~~sh
swift test --package-path remote-orbit --filter DualReceiverVoiceGestureRecognizerTests
swift test --package-path remote-orbit --filter ButtonGestureRecognizerTests
~~~

Expected GREEN: all timing/cancel cases pass; generic 250 ms behavior is
unchanged.

**Commit boundary**
One classifier-only commit with the new source and test files.

**PASS / STOP**
PASS when fake-clock tests cover all listed edges and stale work cannot classify
a newer gesture. STOP if implementation requires generic action injection or
changes its timing.

## Task 3 — Per-transaction trigger-key ownership TDD

**Goal**
Let one classified transaction choose its modifier while preserving the legacy
configured-key API and exact DOWN/UP balance.

**Exact files**
- remote-orbit/Sources/RemoteOrbit/VoiceOptionTrigger.swift
- remote-orbit/Tests/RemoteOrbitTests/VoiceOptionTriggerTests.swift

**RED first**
Add tests calling sendDown(sessionID:key:purpose:) for Left Option and Right
Option; assert each sends only its requested DOWN and matching UP, a later
configuration attempt cannot change an active transaction's captured UP key,
and legacy sendDown(sessionID:purpose:) still uses the configured momentary key.
Run:

~~~sh
swift test --package-path remote-orbit --filter VoiceOptionTriggerTests
~~~

Expected RED: explicit-key overload is missing or key-specific assertions fail.

**Smallest implementation**
Add the explicit-key overload; keep the old overload and delegate it to the
current configured momentary key. Store the chosen key/purpose in existing
activeTriggerKey/active owner state. Keep sendUp and abort balancing that
captured key; add no second synthetic owner.

**GREEN and regressions**

~~~sh
swift test --package-path remote-orbit --filter VoiceOptionTriggerTests
swift test --package-path remote-orbit --filter VoiceTriggerKeyTests
~~~

Expected GREEN: no A/B cross-edge, legacy callers retain behavior, and active
ownership prevents unsafe reconfiguration.

**Commit boundary**
One commit limited to VoiceOptionTrigger.swift and its focused tests.

**PASS / STOP**
PASS when every DOWN is balanced by the same captured key. STOP if the new API
duplicates ownership or changes persistent/session trigger behavior.

## Task 4 — Raw F5 parking and existing EventSuppressor regression

**Goal**
Prove dual routing has no receiver mapping before classification and uses the
existing raw microphone HID → EventSuppressor path to swallow native F5.

**Exact files**
- remote-orbit/Sources/RemoteOrbit/main.swift (RemoteVoiceKeyMapping and
  AppController connection/mode wiring only, if required by the RED).
- remote-orbit/Sources/RemoteOrbit/KeyMapping/EventSuppressor.swift only if
  focused F5 assertions expose missing existing suppression behavior.
- remote-orbit/Tests/RemoteOrbitTests/EventSuppressorTests.swift.
- remote-orbit/Tests/RemoteOrbitTests/RemoteVoiceKeyMappingTests.swift.
- remote-orbit/Tests/RemoteOrbitTests/VoiceTriggerRuntimeTests.swift.

**RED first**
Add runtime coverage that enabling dual raw-F5 mode requests the existing empty
RemoteVoiceKeyMapping and does not pick A or B before classifier output. Add an
EventSuppressorTests case that marks .microphone held, sends native F5/keyCode 96
DOWN then matching UP and expects both remote-owned edges suppressed; an
unrelated physical keyboard event remains unsuppressed. Run:

~~~sh
swift test --package-path remote-orbit --filter VoiceTriggerRuntimeTests
swift test --package-path remote-orbit --filter EventSuppressorTests
swift test --package-path remote-orbit --filter RemoteVoiceKeyMappingTests
~~~

Expected RED: runtime mode/mapping expectation fails on current single-target
mapping path. Direct EventSuppressor characterization may already pass; retain
it as regression proof and do not manufacture a failing primitive test.

Runtime tests must use AppController's injected mapping closure; never execute
`/usr/bin/hidutil` or change the live machine mapping from a test.

**Smallest implementation**
Route dual-mode entry through the current RemoteVoiceKeyMapping disable/empty
operation. Keep the current single HIDMonitor.eventSuppressor; raw HID
microphone down/up must update that owner before semantic edge dispatch. Do not
add a second IOHID manager or event tap.

**GREEN and regressions**

~~~sh
swift test --package-path remote-orbit --filter VoiceTriggerRuntimeTests
swift test --package-path remote-orbit --filter EventSuppressorTests
swift test --package-path remote-orbit --filter RemoteVoiceKeyMappingTests
swift test --package-path remote-orbit --filter HIDMonitorDiagnosticsTests
~~~

Expected GREEN: dual mode has an empty remote mapping; F5 down/up is suppressed
as a matched pair; unrelated keyboard input passes; normal mapping JSON remains
unchanged.

**Commit boundary**
One commit for dual-mode raw-F5 parking plus focused tests. Do not include
classifier, BLE, or settings work.

**PASS / STOP**
PASS only with one existing raw HID/suppressor owner and zero pre-classification
A/B mapping. STOP if native F5 can leak or a second input owner appears.

## Task 5 — Dual-mode eligibility, runtime authority, and fail-closed behavior

**Goal**
Make dual mode an explicit runtime authority selected only by approved
configuration and safe raw-input readiness.

**Exact files**
- Add remote-orbit/Sources/RemoteOrbit/DualReceiverVoiceMode.swift.
- Add remote-orbit/Tests/RemoteOrbitTests/DualReceiverVoiceModeTests.swift.
- remote-orbit/Sources/RemoteOrbit/main.swift.
- remote-orbit/Tests/RemoteOrbitTests/VoiceTriggerRuntimeTests.swift.

**RED first**
Test eligibility truth table: SHORT Disabled + secondary enabled + A != B is
active; each failed condition is legacy/off. Add runtime tests for raw HID and
EventSuppressor readiness absent, asserting no VoiceKeyFilter/raw F5 fallback
and no BLE activation or trigger edge. Add ownership-busy rejection tests for
pending first tap, second-tap wait, active transaction, release/drain, and
reconfiguration. Run:

~~~sh
swift test --package-path remote-orbit --filter DualReceiverVoiceModeTests
swift test --package-path remote-orbit --filter VoiceTriggerRuntimeTests
~~~

Expected RED: pure mode type and dual-mode runtime gates are absent.

**Smallest implementation**
Introduce a pure mode/config evaluator and inject raw-HID/suppressor readiness
into the runtime seam. Keep HIDMonitor as sole raw owner. Dual mode is
disabled/fails closed unless both capabilities are ready; do not route to legacy
VoiceKeyFilter fallback. When secondary is Off, execute existing legacy mapping
path unchanged. Reject A/B or mode changes whenever any voice-path owner remains
active.

**GREEN and regressions**

~~~sh
swift test --package-path remote-orbit --filter DualReceiverVoiceModeTests
swift test --package-path remote-orbit --filter VoiceTriggerRuntimeTests
swift test --package-path remote-orbit --filter VoicePersistentSessionTests
~~~

Expected GREEN: truth table and failure cases pass, secondary Off retains legacy
behavior, and Persistent Session tests remain unchanged.

**Commit boundary**
One commit for pure mode eligibility, runtime readiness/fail-closed gating, and
tests. Do not add persistence or Settings UI yet.

**PASS / STOP**
PASS only if there is a single receiver for each classified transaction and no
unsafe fallback when raw F5 suppression is unavailable. STOP on ambiguous
ownership or state change accepted while a gesture/drain owns the path.

## Task 6 — Prewarm and gesture-to-voice integration

**Goal**
Connect the pure classifier to existing BLE transport prewarm and voice
transaction owner without activating audio on an unclassified tap.

**Exact files**
- remote-orbit/Sources/RemoteOrbit/DualReceiverVoiceGestureRecognizer.swift.
- remote-orbit/Sources/RemoteOrbit/main.swift (AppController microphone HID
  entry/release wiring and voice-coordinator handoff only).
- remote-orbit/Sources/RemoteOrbit/BLEBridge.swift only if integration proves
  existing lifecycle seams insufficient; no lifecycle redesign.
- remote-orbit/Tests/RemoteOrbitTests/DualReceiverVoiceGestureRecognizerTests.swift.
- Add remote-orbit/Tests/RemoteOrbitTests/DualReceiverVoiceTransactionTests.swift.
- remote-orbit/Tests/RemoteOrbitTests/BLEBridgeTests.swift.

**RED first**
Add callback-order integration tests: first DOWN calls transport prewarm once;
no activateVoiceInput, route preparation, or trigger occurs before A/B
classification; first short release retains prewarm through the 300 ms wait;
timeout and second quick release cancel prewarm once; second qualifying hold
classifies B. Run:

~~~sh
swift test --package-path remote-orbit --filter DualReceiverVoiceTransactionTests
swift test --package-path remote-orbit --filter DualReceiverVoiceGestureRecognizerTests
~~~

Expected RED: AppController/voice path has no classifier handoff and current
holding activation is driven by the legacy coordinator threshold.

**Smallest implementation**
Wire raw HID monotonic down/up observations into the voice-specific recognizer.
Use existing prepareVoiceTransport() / cancelVoiceTransportPreparation(); keep
prewarm alive across the double window. Only a classified A/B hold enters the
existing voice-route lifecycle and calls activateVoiceInput(). Keep BLE
transport acquisition separate from micOpen.

**GREEN and regressions**

~~~sh
swift test --package-path remote-orbit --filter DualReceiverVoiceTransactionTests
swift test --package-path remote-orbit --filter DualReceiverVoiceGestureRecognizerTests
swift test --package-path remote-orbit --filter BLEBridgeTests
swift test --package-path remote-orbit --filter VoicePressCoordinatorTests
~~~

Expected GREEN: first/second quick paths never activate voice input; only
classified holds do; BLE remains transport-only until activation.

**Commit boundary**
One integration commit for classifier/AppController/BLE callbacks and focused
tests. No trigger edges are added before Task 7.

**PASS / STOP**
PASS when timing comes from HID monotonic timestamps and callback-order tests
pass. STOP if delayed UI timing is required or transport prewarm requests micOpen.

## Task 7 — First-PCM authorization and selected receiver transaction

**Goal**
On a classified A/B voice transaction, send exactly the selected key DOWN only
after the first decoded PCM frame.

**Exact files**
- remote-orbit/Sources/RemoteOrbit/main.swift (VoicePressCoordinator dual
  entry/selected key/first-PCM path and AppController handoff).
- remote-orbit/Sources/RemoteOrbit/VoiceOptionTrigger.swift.
- remote-orbit/Tests/RemoteOrbitTests/VoicePressCoordinatorTests.swift.
- remote-orbit/Tests/RemoteOrbitTests/VoiceOptionTriggerTests.swift.
- remote-orbit/Tests/RemoteOrbitTests/DualReceiverVoiceTransactionTests.swift.

**RED first**
Add A/B selected-key tests: classification and AUDIO_START alone emit zero
trigger edges; first PCM emits one DOWN for exactly A or B; no PCM followed by
release emits zero edges. Run:

~~~sh
swift test --package-path remote-orbit --filter DualReceiverVoiceTransactionTests
swift test --package-path remote-orbit --filter VoicePressCoordinatorTests
~~~

Expected RED: current coordinator always uses its configured momentary key and
has no classified-key entry path.

**Smallest implementation**
Pass the classifier's selected receiver key into the existing voice transaction
before route activation. Capture it for the transaction and call the explicit
VoiceOptionTrigger.sendDown(sessionID:key:purpose:) only from the existing
first-PCM path. Keep AUDIO_START informational; do not emit during
classification or micOpen.

**GREEN and regressions**

~~~sh
swift test --package-path remote-orbit --filter DualReceiverVoiceTransactionTests
swift test --package-path remote-orbit --filter VoicePressCoordinatorTests
swift test --package-path remote-orbit --filter VoiceOptionTriggerTests
swift test --package-path remote-orbit --filter VoicePersistentSessionTests
~~~

Expected GREEN: first PCM gives one selected-key DOWN; absent PCM gives no
receiver edges; legacy momentary and Persistent Session paths retain existing
keys/policies.

**Commit boundary**
One commit for selected-key first-PCM transaction entry and tests.

**PASS / STOP**
PASS only if no A/B edge exists before classification and first PCM, and every
transaction records one selected key. STOP on any pre-PCM DOWN or dual use of
Persistent Session ownership.

## Task 8 — Release, drain, transport loss, and rapid-repress ownership

**Goal**
Close each selected receiver transaction safely and prevent stale ownership
from crossing into the next gesture.

**Exact files**
- remote-orbit/Sources/RemoteOrbit/main.swift (VoicePressCoordinator
  transaction release/cleanup and HID disconnect paths only).
- remote-orbit/Sources/RemoteOrbit/VoiceOptionTrigger.swift only if existing
  abort/balance seam is insufficient.
- remote-orbit/Tests/RemoteOrbitTests/DualReceiverVoiceTransactionTests.swift.
- remote-orbit/Tests/RemoteOrbitTests/VoicePressCoordinatorTests.swift.
- remote-orbit/Tests/RemoteOrbitTests/VoiceOptionTriggerTests.swift.
- remote-orbit/Tests/RemoteOrbitTests/BLEBridgeTests.swift.

**RED first**
Add independent A and B cases for physical release → tail/output drain → one
matching UP; BLE/ATVV loss before DOWN → zero edges; loss after DOWN → exactly
one matching UP; HID disconnect while pending/active; rapid repress during
drain; stale callback from the previous transaction; assert the next transaction
never inherits the previous key. Run:

~~~sh
swift test --package-path remote-orbit --filter DualReceiverVoiceTransactionTests
swift test --package-path remote-orbit --filter VoicePressCoordinatorTests
~~~

Expected RED: at least one ownership/release case lacks the captured receiver
key or dual pending-state cleanup.

**Smallest implementation**
Reuse current physical-release, tail, output-drain, transport-loss, and HID
removal barriers. Carry selected key and transaction/session ID through each
callback. Use the single VoiceOptionTrigger owner to balance/abort; stale
completion tokens must not clear a newer transaction. Do not tune tail timing.

**GREEN and regressions**

~~~sh
swift test --package-path remote-orbit --filter DualReceiverVoiceTransactionTests
swift test --package-path remote-orbit --filter VoicePressCoordinatorTests
swift test --package-path remote-orbit --filter VoiceOptionTriggerTests
swift test --package-path remote-orbit --filter BLEBridgeTests
swift test --package-path remote-orbit --filter PostReleaseCaptureGraceTests
~~~

Expected GREEN: each DOWN has one same-key UP or documented pre-DOWN cancel;
the next gesture owns a fresh receiver key.

**Commit boundary**
One release/cleanup commit. Do not include settings/UI.

**PASS / STOP**
PASS only when loss, disconnect, drain, and rapid-repress tests show no stranded
modifier and no ownership transfer. STOP if acceptance would require changing
established tail/drain semantics.

## Task 9 — Secondary-trigger persistence and minimum Settings control

**Goal**
Expose Receiver B independently while preserving Receiver A and Persistent
Session settings. Implement only the minimum UI needed to configure the early
hardware gate; defer nonessential polish until Task 10 passes.

**Exact files**
- remote-orbit/Sources/RemoteOrbit/AppStorage.swift.
- remote-orbit/Sources/RemoteOrbit/KeyMapping/SettingsView.swift.
- remote-orbit/Sources/RemoteOrbit/main.swift (load/save, runtime eligibility,
  and existing busy-result callback wiring only).
- Add remote-orbit/Tests/RemoteOrbitTests/DualReceiverVoiceSettingsTests.swift.
- remote-orbit/Tests/RemoteOrbitTests/VoiceTriggerRuntimeTests.swift.
- remote-orbit/Tests/RemoteOrbitTests/VoicePersistentSessionTests.swift.

**RED first**
Test secondary Off default, all six VoiceTriggerKey round trips, invalid/missing
value handling, no alias to legacy or Persistent Session keys, and key/mode
change rejection while pending/active/deferred/draining. Test that SHORT not
Disabled or A == B prevents dual mode. Run:

~~~sh
swift test --package-path remote-orbit --filter DualReceiverVoiceSettingsTests
swift test --package-path remote-orbit --filter VoiceTriggerRuntimeTests
~~~

Expected RED: no independent secondary preference or dual-mode Settings binding
exists.

**Smallest implementation**
Add an optional RemoteOrbit.secondaryMomentaryVoiceTriggerKey preference
(missing/invalid means Off); do not reuse or migrate the Persistent key. Keep
Receiver A on the existing momentary preference. Add the minimum picker
Off | six VoiceTriggerKey values, disabled/rejected while any transaction,
deferred gesture, release/drain, or runtime reconfiguration owns voice input.
Enforce SHORT == Disabled and A != B in runtime authority, not only the UI.
Keep secondary Off on the legacy path. Add concise explanatory copy for direct
hold → A, quick tap then second hold → B, and quick single tap → no action.

**GREEN and regressions**

~~~sh
swift test --package-path remote-orbit --filter DualReceiverVoiceSettingsTests
swift test --package-path remote-orbit --filter DualReceiverVoiceModeTests
swift test --package-path remote-orbit --filter VoiceTriggerRuntimeTests
swift test --package-path remote-orbit --filter VoicePersistentSessionTests
~~~

Expected GREEN: Off defaults safely; persisted B remains distinct from A,
legacy, and Persistent; invalid activation combinations remain legacy/off.

**Commit boundary**
One commit for persistence and minimum Settings configuration. Do not add layout
polish or unrelated Settings cleanup before hardware acceptance.

**PASS / STOP**
PASS when settings round-trip, busy rejection, and legacy/Persistent isolation
pass. STOP on accidental migration/aliasing or a UI-only safety gate.

## Task 10 — EARLY real-receiver hardware acceptance gate

**Goal**
Validate classified synthetic A/B triggers with real receivers before
nonessential Settings polish or broader finishing work.

**Exact files / artifacts**
- No product source or test file changes at the gate unless implementation
  authority explicitly reopens a failing code task after a recorded result.
- Record a bounded evidence package under the implementation task's authorized
  evidence directory: candidate source/binary identity, settings, per-action
  marker/time, external receiver observation, and matching voice diagnostic
  events. Do not create a new diagnostic authority.

**Automated pre-gate check**

~~~sh
swift test --package-path remote-orbit --filter DualReceiverVoiceTransactionTests
swift test --package-path remote-orbit --filter VoiceOptionTriggerTests
~~~

**Hardware RED / command**
This is a human acceptance gate; no shell command can establish whether a real
IME accepted a synthetic modifier. Use the authorized test candidate and record
each outcome. Any failed row is RED and stops construction:

~~~text
5 x direct LONG: A opens; B does not
5 x double-hold: first tap opens neither; second held press opens B only
5 x quick single: neither opens
after each release: selected receiver closes and the next gesture starts cleanly
~~~

For every row also confirm logs show A/B trigger count = 0 before classification,
trigger count = 0 before first PCM, and exactly one selected receiver owner per
transaction. Record internal events separately from the user's visible receiver
result. The user, not the executor, performs these physical actions.

**Smallest implementation**
There is no code implementation at this gate. Do not tune thresholds or add
fallbacks to force a pass. Do not restore pre-classification hidutil mapping.

**GREEN and regressions**
GREEN is all rows passing with matching logs and identity. No test/build command
substitutes for that evidence. The focused commands above remain required.

**Commit boundary**
No source commit. Store evidence and update implementation task controls at the
authorized gate transition. Do not merge.

**PASS / STOP**
PASS permits Task 11. If either real receiver does not reliably accept the
classified synthetic Left/Right Option, STOP exactly as
SYNTHETIC_RECEIVER_TRIGGER_NOT_ACCEPTED; return to Web for architecture review.
Never restore pre-classification mapping or proceed to UI polish after RED.
The implementation authority must separately authorize any candidate build,
install, or restart before this gate can be run.

## Task 11 — Post-gate polish and full validation

**Goal**
After Task 10 PASS only, finish nonessential UI clarity and validate all changed
boundaries against the full project.

**Exact files**
- remote-orbit/Sources/RemoteOrbit/KeyMapping/SettingsView.swift (approved
  dual-mode explanatory copy/layout only).
- Tests touched by Tasks 1–9, plus remote-orbit/Tests/RemoteOrbitTests/ only
  for a demonstrated coverage gap in this contract.
- CURRENT_STATUS.md and CURRENT_TASK.md only for the authorized control
  transition/evidence handoff; update them in the same commit as each material
  transition.

**RED first**
Use any failed focused UI/config regression found while completing the minimum
control; add a narrow test before changing the relevant code. No polish-only
behavior changes. Re-run its class filter and record the observed failure before
the edit. If no regression exists, do not create an artificial failing test;
begin at the full validation matrix after visual review of the Settings states
(Off, enabled, invalid A==B, busy, and SHORT not Disabled).

**Smallest implementation**
Polish only copy/hierarchy needed to explain the frozen contract and safely
surface unavailable/busy states. No change to classification, keys, storage,
trigger ownership, timing, or hardware path.

**GREEN and full regressions**

~~~sh
swift test --package-path remote-orbit --filter DisabledShortClassifierTests
swift test --package-path remote-orbit --filter DualReceiverVoiceGestureRecognizerTests
swift test --package-path remote-orbit --filter DualReceiverVoiceModeTests
swift test --package-path remote-orbit --filter DualReceiverVoiceSettingsTests
swift test --package-path remote-orbit --filter DualReceiverVoiceTransactionTests
swift test --package-path remote-orbit --filter VoicePressCoordinatorTests
swift test --package-path remote-orbit --filter VoiceOptionTriggerTests
swift test --package-path remote-orbit --filter EventSuppressorTests
swift test --package-path remote-orbit --filter RemoteVoiceKeyMappingTests
swift test --package-path remote-orbit --filter BLEBridgeTests
swift test --package-path remote-orbit --filter VoiceTriggerRuntimeTests
swift test --package-path remote-orbit --filter VoicePersistentSessionTests
swift test --package-path remote-orbit
./remote-orbit/run-self-tests.sh
swift build --package-path remote-orbit -c release
git diff --check
~~~

Also run a scope audit against the implementation task allowlist and verify no
generic ButtonGestureRecognizer threshold change, no Persistent Session semantic
change, no trigger mapping architecture change outside approved dual mode, and no
diagnostic schema/authority change.

**Commit boundary**
Keep polish and any justified regression correction in a reviewable commit after
hardware-gate PASS. Commit/push each coherent implementation checkpoint per
repository policy; verify local HEAD equals authorized remote branch HEAD.

**PASS / STOP**
PASS only with focused suites, full swift test, project self-tests, release
build, diff check, and scope audit all green. STOP and preserve exact failing
evidence for any required check failure; do not skip it silently.

## Task 12 — Final two-receiver acceptance and independent Web audit

**Goal**
Verify the complete candidate and hand it to independent review without merging.

**Exact files / artifacts**
- No product source change unless implementation authority opens a new
  corrective task for a specific failed criterion.
- Authorized evidence and task-control handoff only.

**RED / acceptance check**
Using the exact final candidate identity, the user performs and reports:

~~~text
A direct long
B quick-first-tap + second long
quick single tap
continuous A/B/A/B
rapid re-press during prior release/drain
release/drain closure
disconnect/recovery smoke
~~~

Candidate fails if any transaction emits a pre-classification/pre-PCM key, uses
the wrong receiver, leaves a modifier down, transfers prior ownership, or
violates quick-single no-action. There is no synthetic-input or hardware shell
substitute for user operation.

**Smallest implementation**
No change during acceptance. If a criterion fails, stop and create a narrowly
scoped corrective task; do not patch opportunistically in the acceptance gate.

**GREEN and regressions**
All final hardware rows pass, event timelines agree with selected key and
transaction ID, all Task 11 validation remains green at final HEAD, and the
independent Web reviewer compares actual pushed diff/evidence to this plan and
the design spec.

**Commit boundary**
Commit/push any authorized final control/evidence handoff and verify remote HEAD
equals local HEAD. Do not merge. Final state is
WAITING_FOR_INDEPENDENT_WEB_AUDIT.

**PASS / STOP**
PASS means ready for independent Web audit only. STOP on any acceptance failure,
missing exact candidate identity, stale test/build evidence, or missing remote
sync. Merge remains outside this plan.

## Completion boundary

Construction does not proceed past Task 10 without real-receiver gate PASS.
This plan itself ends after independent Web review is requested. It authorizes no
merge, release, or installation. If the early gate reports
SYNTHETIC_RECEIVER_TRIGGER_NOT_ACCEPTED, return to architecture instead of trying
a pre-classification mapping workaround.
