# Task 043 — LONG-only Voice Gate Corrective

## Decision

The user-facing RC003 microphone interaction is one mode only:

- SHORT / quick tap: no user-visible action and no IME toggle/session.
- LONG / hold: direct remote voice input.
- Release after LONG: finish through the existing direct drain/close path.
- Persistent toggle, dual-receiver selection and SHORT replay are not product behaviors for this path.

This corrects the current production direct-session admission rule, which starts a voice session on every physical microphone DOWN. That rule removed the old Persistent classifier but still makes a quick tap create a very short voice session.

## Selected architecture

Use a dedicated LONG-only admission gate in front of the existing direct voice session. Do not restore the legacy SHORT/Persistent classifier.

### Physical DOWN

- Capture the session/profile/trigger identity.
- Arm the existing hardware Option gate before the hidutil-translated trigger can escape.
- Begin only bounded transport/audio prewarm that is already supported by the voice pipeline; prewarm must remain invisible to the IME/HUD.
- Start one hold timer using the existing 300 ms long-press boundary.
- Do not release the hardware trigger to the IME.
- Do not enter user-visible `opening/streaming` readiness/HUD state yet.

### Release before 300 ms

Treat as SHORT/no-op:

- cancel the hold timer;
- drop/suppress the captured hardware trigger, with no replay;
- cancel/close any prewarm candidate cleanly;
- return to idle;
- no Persistent toggle, no synthetic tap, no HUD/readiness activation, no green state.

### Hold reaches 300 ms

Promote exactly once into the existing direct session:

- release the already-captured hardware trigger via the existing gate, or begin the configured synthetic trigger fallback;
- preserve/carry forward the prewarmed transport/audio candidate where existing ownership allows it;
- enter the current direct `OPENING → STREAMING → DRAINING → IDLE` lifecycle;
- receiver-readiness monitoring begins only after promotion into the real voice lifecycle.

### Release after promotion

Use the current direct-session release/drain logic unchanged, including current transport-stop, output-drain and rapid-repress ownership rules unless a deterministic regression proves a narrow adjustment is required.

## Constraints

- `holdActivationThreshold` remains 300 ms unless measured evidence proves the existing boundary is unsafe.
- SHORT must never replay Option or toggle/open/close an IME session.
- Do not reintroduce `VoiceSessionMode.persistentOpen` as production authority.
- Do not route production microphone DOWN/UP back through the legacy general short/long/persistent classifier.
- Historical legacy seams may remain temporarily for tests/compatibility, but production microphone entry must not depend on them.
- Do not change BLE protocol, ADPCM decode, AudioPipe render semantics, driver/TCC, generic HID behavior for other buttons, or the receiver-readiness sampler architecture.
- The already accepted Doubao post-processing rapid-repeat limitation remains outside this corrective.

## Required verification

Deterministic tests must prove at least:

1. DOWN then UP before 300 ms produces no voice trigger delivery and no user-visible voice state.
2. A 300 ms hold promotes exactly once into the direct session.
3. Hardware Option is captured at DOWN and not released before LONG promotion.
4. SHORT/no-op cancels the captured Option without replay.
5. Synthetic fallback obeys the same LONG-only boundary.
6. Prewarm/candidate work from a SHORT is fully cleaned and cannot leak into the next gesture.
7. Stale hold timers cannot promote after release, disconnect, or a newer gesture.
8. Release after promoted LONG preserves current direct drain/output ownership.
9. Rapid LONG repress behavior remains bounded and preserves current accepted semantics.
10. Receiver-readiness/HUD does not activate for discarded SHORT and still functions for promoted LONG.
11. Other remote buttons are unchanged.
12. Full Task 043 readiness tests, voice-pipeline regression tests, full Swift tests, both Release architectures, protocol self-tests and `git diff --check` pass.

## Runtime sequencing

The currently installed `a881121f...` candidate is no longer eligible for final acceptance because it does not enforce SHORT=no-op. Its idle memory evidence remains useful evidence for the readiness architecture only.

After this source corrective:

1. independent Web source audit;
2. package/install exact audited source;
3. human quick-tap check: no-op;
4. human LONG check: direct voice works;
5. repeat memory/CPU runtime soak;
6. only then consider merge/release closeout.

## Task reconciliation

`TASK_RECONCILIATION_REQUIRED: YES`

Reason: runtime acceptance exposed a product-interaction semantic mismatch that requires source mutation beyond the previous readiness-only runtime-soak authorization.
