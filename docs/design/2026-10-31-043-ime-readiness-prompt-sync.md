# Task 043 — IME Receiver Readiness and HUD Truth

Date: 2026-10-31
Status: DESIGN COMPLETE
Task: `RO-IME-READINESS-PROMPT-SYNC-043`
Predecessor: `RO-VOICE-PIPELINE-SIMPLIFICATION-042`

## 1. Design question

How should RemoteOrbit represent voice-input readiness when its own BLE/audio path is active but the external input method may still be busy and may not have started consuming `RemoteOrbit Mic 2ch`?

The design must make the HUD truthful without coupling the stable Task 042 transport/audio state machine to Doubao-specific timing or private signals.

## 2. Verified facts and constraints

### Verified project facts

- Task 042 fixed the prior rapid re-press ownership/candidate failures.
- Fresh RC003 acceptance no longer reproduces the old stuck-waveform-after-release behavior.
- When the Doubao voice bar actually appears, speech is accepted.
- Extreme rapid re-press can occur while the previous IME lifecycle is still cleaning up; a new trigger may not reopen Doubao, while a later press succeeds after cleanup.
- RemoteOrbit can show its own voice HUD even in a session where the external IME did not begin a new capture session.

### Verified source facts

`VoicePressCoordinator.State.streaming` is an internal RemoteOrbit session/transport state.

Current AppController behavior maps:

- `.opening` -> pending HUD;
- `.streaming` -> `RemoteActionHUDState.recording`;
- `onRemoteAudioChanged(true)` -> `RemoteActionHUDState.recording`.

`RemoteActionHUDState.recording` renders the title `正在语音中`.

Therefore the current HUD conflates two separate truths:

1. RemoteOrbit has opened/routed remote audio;
2. an external receiver is actually listening to the virtual microphone.

`AudioPipe` starts a CoreAudio IOProc for `RemoteOrbit Mic 2ch` at app startup and keeps that output path running. Therefore device-level `kAudioDevicePropertyDeviceIsRunningSomewhere` is not a valid external-consumer signal: RemoteOrbit itself can keep the device running.

The package deployment target is macOS 13.

### Platform constraints

Modern Core Audio exposes process objects with per-process input-running state and process/device membership. Those APIs can provide a candidate external-consumer signal on newer macOS versions.

They cannot be assumed reliable without a target-runtime spike:

- the project must retain macOS 13 compatibility;
- the modern process API/classes are newer than macOS 13;
- input-scoped process/device membership has known edge-case behavior when a process switches devices while already streaming.

## 3. User/project decisions

- Preserve the current Task 042 voice transport/audio behavior.
- Do not add a blind fixed cooldown for Doubao post-processing.
- Do not treat rapid IME unavailability as justification to rewrite BLE, AudioPipe, the 350 ms tail, or the 180 ms debounce path.
- The HUD must not claim successful listening merely because RemoteOrbit has started its own audio route.

## 4. Selected option

### Option A — Read-only receiver observer + truthful HUD projection

SELECTED.

Introduce an external-consumer truth layer that is read-only with respect to the voice state machine.

Ownership:

- `VoicePressCoordinator`: local gesture/session/transport authority only.
- `BLEBridge`: transport authority only; unchanged.
- `AudioPipe`: audio routing/render authority only; unchanged.
- `VoiceReceiverReadinessObserver`: external-consumer observation only.
- `AppController`: owns projection of local state + audio readiness + receiver readiness into user-facing HUD state.
- `RemoteActionHUD`: presentation only.

No receiver observation is allowed to mutate BLE ownership, trigger ownership, candidate preservation, route activation, output drain, or gesture admission in Task 043.

## 5. Receiver observer design

### 5.1 State model

The observer should expose a small state surface such as:

```text
unsupported
inactive
listening(consumerPID, bundleID?)
```

`unknown` may be used during observer startup/reconfiguration if needed, but must not be projected as confirmed listening.

The observer is about external consumption of `RemoteOrbit Mic 2ch`, not about Doubao as a brand.

### 5.2 Supported runtime path

On a sufficiently new macOS runtime, observe Core Audio process objects and identify external consumers that satisfy all of:

1. process is not the current RemoteOrbit PID;
2. process reports active input IO;
3. input-scoped process device membership includes the AudioDeviceID for `RemoteOrbit Mic 2ch`.

Prefer property listeners over a permanent high-frequency polling loop.

A small initial enumeration is acceptable to establish baseline state and register listeners.

### 5.3 Correlation semantics

At a new voice session:

- if an external consumer is already actively consuming `RemoteOrbit Mic 2ch`, readiness may immediately be `listening`; this supports persistent/open receiver scenarios;
- otherwise readiness begins as inactive and becomes listening only on an observed external consumer transition.

Pre-existing unrelated consumers must not become a false session-specific activation merely because they exist. The observer should maintain the active consumer set rather than inventing a synthetic receiver identity.

### 5.4 Compatibility

Keep `.macOS(.v13)` unchanged.

Newer process-object APIs must be availability-gated. On unsupported systems, expose `unsupported`; do not raise the deployment target and do not emulate readiness with private APIs.

### 5.5 Signal validation gate

Before the observer is allowed to drive a green listening HUD, validate it on the target environment.

Minimum runtime validation:

- multiple normal IME voice starts;
- matching normal stops;
- rapid re-press cases where the trigger is ignored by the IME;
- delayed later re-open that succeeds;
- no false listening state during the known post-processing/text-insertion interval;
- no false signal from RemoteOrbit's own always-running IOProc.

If the input-scoped process/device mapping proves unreliable, the design falls back to local-truth HUD semantics and does not invent another receiver signal.

## 6. HUD projection design

The HUD must distinguish local transport readiness from external receiver readiness.

### Voice-specific presentation states

Recommended bounded additions to `RemoteActionHUDState`:

```text
voiceStarting
voiceAudioReady
recording
```

Existing generic `.pending` semantics remain untouched for non-voice buttons.

Suggested user-facing titles:

- `voiceStarting` -> `等待输入法`
- `voiceAudioReady` -> `音频已就绪`
- `recording` -> `正在语音中`

Recommended visual semantics:

- `voiceStarting`: yellow/pending;
- `voiceAudioReady`: blue/informational;
- `recording`: green/confirmed.

### Projection rules

Conceptually:

```text
VoicePress idle
  -> dismiss

VoicePress opening/pending, receiver not confirmed
  -> voiceStarting

RemoteOrbit audio available/streaming, receiver not confirmed
  -> voiceAudioReady

Receiver confirmed listening while the voice session is active
  -> recording

Draining
  -> existing truthful ending state
```

A supported observer reporting no consumer must override the temptation to show green based only on `.streaming` or `AUDIO_FIRST`.

On unsupported runtimes, the HUD may still show `voiceStarting` and `voiceAudioReady`, but it must not claim external listening without evidence.

Do not add a release-time failure toast in the first implementation. Very short presses are legitimate and should not generate noisy false failures.

## 7. Diagnostics

Add only bounded state-transition diagnostics, not a new broad probe system.

Recommended event:

```text
VOICE_RECEIVER_READINESS
```

Fields may include:

- supported/unsupported;
- state;
- target AudioDeviceID or stable UID;
- external consumer PID;
- bundle ID when available;
- session ID when one exists.

Log transitions, not every poll/sample.

Do not read unified logs from production code and do not scrape Doubao logs.

## 8. Rejected options

### Fixed cooldown after release

REJECTED.

Why:

- post-processing duration is not proven constant;
- it adds latency to normal rapid re-presses;
- it hides readiness uncertainty rather than measuring it.

### Automatic trigger retry in Task 043

REJECTED FOR THIS TASK.

Why:

- a delayed first trigger and a retry can double-toggle the IME;
- safe retry requires a trustworthy receiver-confirmation signal and measured timing first;
- it would turn a HUD/readiness task into trigger-admission behavior.

A later task may reconsider a one-shot readiness-aware retry only after observer reliability is proven and separately authorized.

### Delay audio route until receiver confirmation

REJECTED.

Why:

- changes the now-stable Task 042 audio path;
- risks first-syllable latency/loss;
- unnecessarily couples receiver UI behavior to AudioPipe ownership.

### Doubao-specific Accessibility/private API/log scraping

REJECTED.

Why:

- brittle across Doubao releases;
- permission and focus behavior are unreliable;
- it makes RemoteOrbit receiver-specific when the virtual microphone contract can remain generic.

### Device-level `DeviceIsRunningSomewhere`

REJECTED as readiness truth.

Why:

- RemoteOrbit itself starts a persistent IOProc on the virtual device, so the device can be running even with no external listener.

## 9. Implementation boundary

Expected product files for a later authorized implementation:

- new `VoiceReceiverReadiness.swift` or equivalent bounded Core Audio observer;
- `RemoteActionHUD.swift` for voice-specific truthful visual states;
- `main.swift` / AppController wiring and projection;
- targeted tests for observer parsing/projection and HUD state decisions.

Normally out of scope:

- `BLEBridge.swift`;
- `AudioPipe.swift`;
- ATVV protocol code;
- driver code;
- HID debounce/ownership code.

If implementation requires those out-of-scope files to make the HUD truthful, STOP and return to design instead of expanding automatically.

## 10. Verification implications

Required deterministic tests:

1. `.streaming` with no receiver confirmation never yields green `recording`.
2. `AUDIO_FIRST` with no receiver confirmation never yields green `recording`.
3. confirmed external consumer + active voice session yields green `recording`.
4. consumer stop while local session still exists drops back from confirmed recording to a truthful non-green state.
5. unsupported observer never claims confirmed receiver listening.
6. non-voice HUD states remain unchanged.
7. Task 042 rapid-repress suites remain green.

Runtime acceptance:

- normal voice activation: yellow/blue -> green only when the receiver actually starts;
- rapid ignored re-open: HUD remains yellow/blue and never lies green;
- later successful re-open: green appears when the receiver starts;
- no regression to stuck waveform, waveform-without-audio, first-speech handling, or old/new session ownership.

## 11. Consequences and reversibility

CONSEQUENCES:

- user-visible state becomes more conservative but more truthful;
- newer macOS can show receiver-confirmed listening if the Core Audio process signal validates;
- older/unsupported systems retain local readiness information without claiming external listening.

REVERSIBILITY:

High. The observer is read-only and the HUD projection is separate from the voice state machine.

REVERSAL_TRIGGER:

If Core Audio process/device membership produces false listening or missed listening transitions on the target environment, disable receiver-confirmed projection and retain only local `等待输入法` / `音频已就绪` semantics. Do not alter the Task 042 audio path as compensation.

## 12. Task reconciliation

`TASK_RECONCILIATION_REQUIRED: YES`

Reason: Task 042 authorized voice-pipeline/runtime acceptance only; receiver readiness and HUD truth are a materially different engineering purpose.

This design is intended to become the authority for Task 043 before implementation.
