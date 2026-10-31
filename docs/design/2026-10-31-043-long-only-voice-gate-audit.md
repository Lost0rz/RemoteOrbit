# Task 043 — LONG-only Voice Gate Design Audit

## Audit result

The prior LONG-only corrective direction is valid but incomplete. It is safe only if the new 300 ms gate is implemented as a narrow admission layer in front of the already-audited direct voice path and does **not** reuse legacy public `pending/holding` state or legacy SHORT/Persistent promotion logic.

The accepted low-resource receiver-readiness architecture must remain unchanged.

## Verified facts from accepted source `a881121f...`

1. Receiver readiness is already structurally bounded: one private serial queue, at most one 100 ms timer only while active, direct synchronous snapshot sampling, no Core Audio property listeners, no recursive dispatch per tick.
2. AppController currently activates readiness for public voice states `.opening`, `.pending`, `.holding`, `.streaming`, and deactivates it for `.draining`, `.idle`.
3. AppController calls `activateVoiceInput()` when public state becomes `.opening`.
4. Current production microphone DOWN enters `voicePress.keyDown(... directSession: true)` and the direct path immediately releases the hardware Option gate; this bypasses the 300 ms boundary.
5. Existing BLE `prepareVoiceTransport()` is explicitly transport-only and does not request `micOpen`. `cancelVoiceTransportPreparation()` already provides bounded cancellation and can retain an already-READY transport without keeping a voice request active.
6. Existing AudioPipe candidate/prebuffer is fixed-capacity and is intended to preserve early remote PCM without routing it until voice activation.
7. Existing direct rapid-repress logic can activate a retained direct repress as soon as previous drain ownership clears and the new press is still held; it currently does not require the new press to have crossed 300 ms.
8. Pre-HID physical ATVV streams are already owned separately and may exist before the HID press; current code protects that transport identity from stale callbacks.

## Required architecture refinement

### 1. Candidate state is internal, not public voice state

The 0–300 ms interval must be represented by a private direct-candidate owner inside `VoicePressCoordinator` (or an equivalent private seam owned by the same coordinator).

It must **not** call `setMode(.pending)` or `setMode(.holding)`.

Reason: those public states currently activate the Task 043 readiness sampler and HUD. Reusing them would add Core Audio sampling to every quick tap and would make SHORT visibly enter voice-starting state.

During the candidate interval the public state remains `.idle`.

### 2. Preserve existing activation boundary after promotion

At physical DOWN:

- capture session/profile/trigger identity;
- arm the appropriate hardware Option capture owner;
- call only the existing bounded `prepareVoiceTransport()` prewarm seam;
- preserve/allow the existing fixed-capacity AudioPipe candidate/prebuffer behavior;
- start exactly one 300 ms one-shot hold timer;
- do not call `activateVoiceInput()`;
- do not release Option;
- do not activate readiness/HUD.

At LONG confirmation:

- promote into the existing direct session;
- public state becomes `.opening`;
- existing AppController `.opening` callback calls `activateVoiceInput()`;
- existing readiness lifecycle activates;
- release the captured/synthetic trigger at promotion using the current direct behavior.

Do **not** restore the historical rule that waits for first PCM before releasing Option. The only added delay is the 300 ms LONG boundary. After promotion, use the current direct-session latency behavior.

### 3. SHORT cancellation must reuse current bounded cleanup seams

For release before 300 ms:

- cancel/nil the one-shot hold timer;
- invalidate candidate generation/session ownership;
- cancel the hardware gate without replay;
- call existing `cancelVoiceTransportPreparation()` rather than inventing BLE cleanup;
- do not force-reset BLE transport epoch or pre-HID physical ownership;
- end AudioPipe candidate only when existing physical-candidate ownership rules say it is safe;
- publish no public voice state transition.

A transport that completed preparation and is already READY may remain READY under the existing BLE policy; this is internal cache state, not a voice session. No `voiceInputRequested` or `micOpenRequested` may remain after SHORT cancellation.

### 4. Rapid re-press has a two-gate admission rule

The existing direct repress path must be preserved, but its promotion condition must become:

```text
physical still held
AND longConfirmed (>= 300 ms)
AND previous direct-session ownership/drain admission is ready
```

Neither drain completion nor 300 ms alone may promote the new press.

This must cover both orders:

- previous drain clears first, then 300 ms arrives;
- 300 ms arrives first, then previous drain clears.

A quick re-press released before 300 ms must cancel its pending hardware owner and never auto-activate after the previous drain later finishes.

### 5. Preserve special hardware ownership during overlap

When a new physical DOWN occurs while the old direct session still owns terminal hardware Option-UP retirement, use the existing pending-repress hardware capture mechanism. Do not replace it with the ordinary gate owner.

The new LONG timer is an additional admission condition, not a replacement for the current A/B hardware ownership protocol.

### 6. Disconnect/cancellation semantics

If HID disconnects while the candidate is pending:

- cancel the LONG timer;
- invalidate candidate generation;
- use the existing suppression-reset path intended for a missing physical UP;
- do not later promote from a stale timer.

Ordinary early physical UP should use normal gate cancellation, not the disconnect-only reset path.

### 7. Profile/trigger reconfiguration must remain blocked during candidate ownership

Because public voice state remains `.idle`, existing `mode != .idle` guards alone are insufficient.

The private LONG candidate must count as active voice-key ownership for trigger/profile reconfiguration. The profile/trigger captured at DOWN remains authoritative through promotion or cancellation.

Do not apply a new hidutil target while a candidate physical key is held.

### 8. Resource invariants

The corrective must add no persistent resource owner.

Required invariants:

- Task 043 `VoiceReceiverReadiness.swift`: production implementation unchanged unless an independently justified bug is found;
- zero readiness activity during the 0–300 ms candidate interval;
- zero readiness activity for discarded SHORT;
- at most one direct LONG one-shot timer;
- timer exists only while one physical candidate is pending;
- no recurring timer for LONG classification;
- no new dispatch queue;
- no recursive `async` refresh chain;
- no unbounded candidate/repress arrays, dictionaries, work-item lists, or logs;
- BLE prewarm uses only existing bounded BLEBridge ownership/work items;
- AudioPipe prebuffer capacity remains unchanged;
- repeated SHORT taps leave final candidate count 0 and timer count 0.

A deterministic lifecycle stress test should run at least 100,000 synthetic candidate operations against a fake/immediate scheduler seam and prove bounded coordinator state. This is a structural test; it must not create 100,000 real GCD timers.

### 9. Source-diff expectation

Preferred product diff:

- `main.swift` / focused coordinator logic and tests only.

Expected unchanged product files:

- `VoiceReceiverReadiness.swift`;
- `BLEBridge.swift`;
- `AudioPipe.swift`;
- ATVV decode/protocol files;
- driver;
- generic non-microphone HID behavior.

If implementation requires a production diff in any of those files, STOP and return the reason before expanding scope.

## Additional deterministic tests

In addition to prior tests, prove:

1. Candidate interval leaves public `VoicePressCoordinator.State == .idle`.
2. Candidate interval causes readiness activate count `0` and HUD projection `nil`.
3. LONG promotion causes exactly one `.opening` transition; `activateVoiceInput()` count becomes exactly `1`.
4. Promotion releases trigger immediately at LONG confirmation; it does not wait for first PCM.
5. Rapid re-press: drain-ready-before-threshold does not promote early.
6. Rapid re-press: threshold-before-drain does not promote until drain-ready.
7. Rapid re-press released before threshold never promotes after later drain completion.
8. Candidate blocks voice-profile/hidutil reconfiguration until cancel/promotion ownership ends.
9. HID disconnect while candidate pending invalidates timer and suppression owner safely.
10. 100,000 candidate lifecycle stress leaves timer count `0`, candidate count `0`, pending scheduler state bounded, readiness activation count `0` for short-only stress.
11. Existing Task 043 readiness lifecycle stress and source guards remain unchanged and pass.
12. Existing pre-HID physical candidate adoption tests continue to pass without changing BLE/AudioPipe source.

## Audit disposition

The previous corrective design is `STOP` as an implementation authority until these refinements are incorporated into `CURRENT_TASK.md`.

With these refinements, the design is suitable for construction because it changes only **admission timing/eligibility** while preserving the current direct voice, transport, audio, readiness and drain architectures.
