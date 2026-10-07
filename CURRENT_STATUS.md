# CURRENT_STATUS

Last updated: 2026-10-07
State: ARCHITECTURE DESIGN HOLD — DUAL-RECEIVER VOICE ROUTING
Repository: `Lost0rz/RemoteOrbit`

This file is the authority for mutable current project state. Historical detail remains preserved in Git history.

## Control-plane integrity

- Previous control HEAD: `841f31abbcd42c2300b9f0498cea47a1982a55ac`.
- Candidate branch remains `codex/disabled-short-classifier-regression-fix` at exact HEAD `172427957fd18a2b5827edd1cb1c4bddb6a5b7db`.
- Installed candidate remains the current hardware-test baseline unless a later task records otherwise.
- Candidate remains unmerged.
- No product source mutation is authorized by this design hold.

## Closed single-input-method finding

The prior fast-click Doubao anomaly is explained by receiver shortcut collision: Doubao's click/toggle mode and hold-to-talk mode were both bound to Left Option. Separating those receiver semantics removes that specific unwanted fast-click Session activation.

The independent PR #14 Disabled-SHORT classifier regression remains real; the candidate still correctly restores normal short/long classification.

## Current product requirement

The Xiaomi remote microphone itself only produces usable remote audio while the physical microphone button is held. Therefore two independent input receivers cannot be cleanly separated by assigning one receiver to a no-hold tap and the other to a hold if both must receive Xiaomi remote audio.

The product now needs two distinct **hold-capable** gestures for two independent receivers.

Candidate UX discussed by the user:

```text
Receiver A -> direct LONG
Receiver B -> double-tap, with the second press held LONG
```

An alternative lower-risk UX is a separate receiver-selection gesture/button followed by the same microphone LONG for audio.

## Current source architecture audit

### 1. One persistent owner, not two receivers

`VoicePressCoordinator` models only:

```text
VoiceSessionMode = idle | persistentOpen
RemoteSegmentTriggerPolicy = momentaryTrigger | audioOnly
```

When a gesture begins while `persistentOpen`, the policy is automatically `audioOnly`. LONG then suppresses the mapped momentary trigger and keeps the persistent receiver as owner. This architecture supports:

```text
SHORT opens receiver A persistent Session
LONG while A is open -> audio-only continuation into A
```

It does not model:

```text
LONG -> receiver A
alternate LONG gesture -> receiver B
```

or an explicit cross-receiver handoff.

### 2. External Session state is not authoritative

RemoteOrbit's persistent ownership is internal. The merged PR #13 contract explicitly records that RemoteOrbit cannot observe an IME voice UI manually closed outside RemoteOrbit. Therefore `persistentOpen` may remain true internally while the external receiver has already exited or changed state.

This makes the current persistent design vulnerable to visible/internal ownership drift and is a plausible architectural contributor to the historical symptom "tap opens Session, later LONG exits/changes it". Exact external cause still requires a concrete sample if that behavior remains relevant after redesign.

### 3. Persistent repeated holds have no external transaction boundary

Current persistent tests intentionally keep one external persistent trigger open across repeated LONG segments. Each LONG is `audioOnly`; no new receiver trigger edge is emitted per segment.

This means RemoteOrbit does not create an explicit ASR transaction boundary between segmented holds. That is a plausible contributor to historical duplicated/repeated committed text, but the current code cannot prove the receiver's text-commit semantics.

The abandoned/unmerged PR #16 attempted a different architecture: each Persistent LONG would own its own transaction and add structured per-segment transaction boundaries. Its existence is supporting design evidence, not an accepted fix.

### 4. Existing diagnostics are internally strong but externally incomplete

Current diagnostics can establish:

```text
raw HID down/up
short/long classification
internal persistent session mode
persistent owner key
momentary configured key
remoteSegmentTriggerPolicy
mapped/synthetic trigger edges
suppression/gate decisions
AUDIO_START / AUDIO_FIRST / drain / completion
```

They cannot authoritatively establish:

```text
which external IME currently owns a voice Session
whether an IME silently closed/reopened its Session
what text/composition transaction the IME committed
whether duplicate visible text came from receiver recomposition vs RemoteOrbit trigger duplication
```

The preferred architecture should therefore minimize dependence on unobservable external persistent-session state rather than add large diagnostic infrastructure first.

## Gesture infrastructure fact

The repository already has a generic `ButtonGestureRecognizer` supporting `singleTap`, `doubleTap`, `longPress`, and a second-tap LONG represented with `clickCount = 2`.

However the microphone button is explicitly excluded from that generic advanced-gesture path whenever remote microphone LONG is enabled. It is routed directly to `VoicePressCoordinator` instead.

Therefore `double-tap + hold-second` is conceptually supported by existing gesture machinery but is **not implemented for the microphone voice path**.

## Design options

### Option A — dual momentary receivers on one microphone button

```text
direct LONG -> Receiver A momentary transaction
double-tap + hold second -> Receiver B momentary transaction
```

No receiver remains persistently open between utterances. Each hold has one receiver owner and one balanced trigger transaction.

Benefits:
- aligns with the hardware constraint that useful audio requires a hold;
- eliminates persistent-session state drift from the dual-receiver workflow;
- eliminates shared persistent ASR composition across segmented holds;
- gives each utterance exactly one receiver owner.

Cost/risk:
- microphone voice path needs a new gesture router / extended coordinator;
- current device-scoped F5 -> one fixed trigger-key mapping is not sufficient by itself because receiver choice is known only after gesture classification;
- trigger-delivery ownership must be redesigned so the unselected receiver never sees a pre-classification mapped edge.

### Option B — select receiver first, then use one LONG

Use another remote button (preferred) or another safe non-voice gesture to choose Receiver A/B while idle. Reconfigure the momentary trigger key while no voice gesture owns the route. Then every microphone LONG uses the currently selected receiver.

Benefits:
- lowest implementation risk;
- preserves the proven physical/system-mapped trigger path;
- receiver identity is known before microphone down;
- no persistent external Session required.

Cost:
- one explicit mode-selection action when switching receivers;
- needs clear HUD/status feedback showing the selected receiver.

### Option C — keep Persistent A and hand off LONG to B

SHORT opens A; LONG closes/suspends A, runs B, then optionally restores A.

Not recommended as the default architecture because it depends on coordinating two external Session owners whose actual state RemoteOrbit cannot authoritatively observe. It also retains the historical duplicate/composition risk around a long-lived persistent receiver.

## Current recommendation

For reliability, prefer a **dual-momentary transaction model** and remove external Persistent Session ownership from the two-receiver workflow.

- If one-button UX is the priority: Option A (`LONG A`, `double-tap+hold B`).
- If minimum engineering risk and trigger reliability are the priority: Option B (receiver selector + microphone LONG).

Do not implement until the user chooses the interaction contract.
