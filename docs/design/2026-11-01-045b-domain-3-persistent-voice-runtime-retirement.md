# Task 045B Domain 3 — Persistent Voice Runtime Retirement

Date: 2026-11-01
Audit basis: `main@e96f69b7e848a999757e423edd0cc72efd459a7c`
Status: `ACCEPTED DESIGN / IMPLEMENTATION NOT YET PERFORMED`

## Design question

Can the obsolete Persistent IME session runtime be removed as an independent bounded domain without deleting or weakening the current LONG-only trigger-ownership path or the still-frozen Dual Receiver runtime?

## Verified constraints

- Production RC003 microphone input already uses the Gate-A private LONG candidate/direct-session lifecycle; Persistent session mode is not consulted by that path.
- The coordinator still contains historical Persistent open/close state, deferred toggle state, configured/owner keys, and an audio-only remote-segment mode.
- Persistent-only behavior is interleaved with generic legacy classifier code, but the core LONG-only ownership path is separately represented by `LongOnlyCandidate`, direct-session state, short-discard tombstones, hardware/synthetic trigger ownership, rapid repress and output-drain barriers.
- The Dual Receiver runtime still uses classified hold/pending/holding/drain seams and must remain functional until its own later domain.
- Current LONG-only tests already directly cover SHORT discard, delayed mapped-edge suppression, suppression handoff, repeated SHORT prefixes followed by LONG, rapid re-press and drain ownership.

## Selected option

Retire **Persistent-only state and semantic branches now**, while preserving both:

1. the current Gate-A LONG-only ownership path; and
2. the Dual Receiver classified-hold runtime for a later bounded domain.

Persistent-specific state may be removed from shared structs/method signatures where doing so is behavior-neutral for retained callers. Shared suppression primitives are classified by actual retained use, not by historical symbol names.

### Runtime ownership consequences

Remove Persistent ownership/state:

- `VoiceSessionMode`;
- `PendingPersistentToggle`;
- Persistent configured key and open-session owner key;
- Persistent open/close semantic dispatch and deferred retry;
- Persistent-specific 300 ms wrapper (`persistentHoldActivationThreshold` / `isPersistentSessionLongPress`);
- Persistent audio-only segment state and completion/release diagnostics;
- AppController Persistent runtime key state, startup injection/configuration, reconfiguration method and callback bridges.

The historical `RemoteSegmentTriggerPolicy` exists only to distinguish ordinary momentary routing from Persistent audio-only routing. After the audio-only branch is removed, it may be removed rather than retained as a meaningless single-value state wrapper. Retained Dual/legacy classified paths should keep ordinary momentary ownership directly.

### Filter boundary

Remove only Persistent semantic wrappers proven to be Persistent-only, such as:

- `emitPersistentShortTap`;
- `emitDeferredPersistentShortTap`;
- Persistent-only audio-only suppression entrypoints.

Preserve generic bounded suppression/tombstone machinery used by current LONG-only behavior, including:

- `discardDeferredHardwareTrigger`;
- suppressed-owner release/quiet-window retirement;
- reset/invalidation safety;
- long-only suppression handoff;
- pending hardware repress;
- held mapped Option-up and replay acknowledgement.

A lower-level helper must not be deleted merely because its historical name contains `AudioOnly` if the LONG-only handoff still calls it.

### Test ownership

Persistent-only suites may be deleted after checking whether they contain generic safety claims. Generic claims already owned by current LONG-only suites should not be duplicated merely to preserve test count.

In particular, retained `VoicePressCoordinatorTests` own the current behavior for:

- private SHORT no-op plus bounded discard;
- late mapped edge swallowing;
- tombstone-to-LONG handoff;
- repeated SHORT prefix followed by promoted LONG;
- rapid LONG/release/LONG ownership;
- current direct drain and trigger balancing.

Dual Receiver runtime/safety tests remain untouched except compile-only adaptation required by removal of Persistent parameters/state.

## Rejected alternatives

### Delete the whole historical short/long classifier together with Persistent

Rejected for Domain 3. The classified hold/pending/holding lifecycle is still used by the frozen Dual Receiver runtime, and some generic ownership/drain seams coexist with current correctness. This would collapse multiple domains and make regression attribution poor.

### Defer Persistent removal until Dual Receiver retirement

Rejected. Persistent state is already product-dead, persistence authority is already retired, and its state/callback/audio-only branches are separable. Keeping it would prolong dead ownership complexity without providing production compatibility.

### Delete suppression primitives because they originated in Persistent behavior

Rejected. Current LONG-only SHORT tombstones and immediate SHORT→LONG handoff depend on the same bounded suppression owner. Actual current call ownership overrides historical naming.

## Compatibility / migration

No new user-data migration is required. Domain 2 already made old Persistent preference bytes inert. Domain 3 removes runtime interpretation of Persistent sessions, not stored user data.

`VoiceInputProfile`, profile persistence, generic/momentary rollback compatibility and mapping schema remain unchanged.

## Verification implications

A successful implementation must demonstrate both absence and preservation:

- Persistent session/open/close/audio-only code is absent from live production runtime;
- no AppController Persistent key/state/configuration remains;
- current LONG-only tests remain green without weakening assertions;
- Dual Receiver tests remain green;
- no shared suppression/repress/drain mechanism needed by retained paths is removed;
- full Swift, Release, durable self-hosted CI and Universal2 build-only packaging pass.

Human RC003/Doubao acceptance remains a separate user-owned gate.

## Consequences

- Coordinator complexity decreases without combining the later Dual retirement into the same change.
- Some non-Persistent historical classifier/local-short seams may remain temporarily; they are explicitly not evidence that Persistent is still supported.
- Historical lower-level symbol names may remain until a later cleanup if renaming would add unrelated churn.

## Reversibility

High. The retirement is source-only and reversible through Git history. No old Persistent UserDefaults bytes are deleted and no runtime installation is authorized in this domain.

## Reversal trigger

Reconcile before implementation if fresh source evidence proves that a proposed Persistent-only symbol is required by the current Gate-A LONG-only path or by the frozen Dual Receiver runtime in a way that cannot be preserved through a behavior-neutral compile adaptation.

`TASK_RECONCILIATION_REQUIRED: YES`

Reason: Domain 2 task authority prohibited Domain 3 mutation. Project Governance must advance `CURRENT_TASK.md` to this accepted bounded Domain 3 before implementation.

Durable document: `docs/design/2026-11-01-045b-domain-3-persistent-voice-runtime-retirement.md`