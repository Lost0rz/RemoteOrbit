# RemoteOrbit Current Task

## Task identity

- **Task:** INCIDENT MODE — PRE-GATE EVENTTAP CONTRACT TEST + OWNERSHIP ARCHITECTURE REVIEW
- **Incident family:** PERSISTENT-LONG / EXTERNAL-IME PREMATURE SESSION STOP
- **Phase:** Step 6 — deterministic pre-gate mapped-event test
- **Status:** AUTHORIZED
- **Task authority:** this file
- **Product behavior changes:** FROZEN
- **Root cause:** UNKNOWN
- **Construction Gate:** BLOCKED
- **Fresh capture:** NOT AUTHORIZED

## Evidence baseline

Frozen from Step 5:

```text
CONTROL_HEAD_PARENT: b5dc23911de0f4c76e3f6a121b103310074d06cf
PROBE_HEAD: 28824d9dc167f57e3163ef0844aec1b672717d8f

TIMEBASE_NUMER: 125
TIMEBASE_DENOM: 3

TARGET_LONG:
52AE0F3E-3273-482D-9E92-8092EABCF165

ORIGINAL_MAPPED_EVENT_PRE_GATE: YES
CG_EVENT_MINUS_GATE_BEGIN_MS: -8.117083
EVENT_TAP_CALLBACK_PRE_GATE: NO
CALLBACK_MINUS_GATE_BEGIN_MS: 17.777417
GATE_STATE: deferring
ACTION: defer_down

B3_RESULT: OBSERVED_FOR_THIS_ATTEMPT
B4_RESULT: PARTIAL
FRESH_INCIDENT_DIRECT_SUPPORT: NO
ROOT_CAUSE: UNKNOWN
```

The bounded capture did not reproduce the failure. The observed timing window is a
real boundary fact, not historical root-cause proof.

## Single objective

Determine, with a deterministic test, what the current product does when the mapped
voice-trigger EventTap callback is delivered **before** the Option gate becomes
active.

Then decide whether the current ownership contract allows a mapped hardware-derived
voice trigger to escape before RemoteOrbit has acquired gesture ownership.

## Required audit

Read the exact current code paths for:

1. raw HID microphone down;
2. `beginVoicePress`;
3. Option gate begin;
4. mapped-trigger EventTap callback;
5. `optionDeferralActive`;
6. discarded/suppressed ownership;
7. fallback `VK.voiceKey` handling;
8. synthetic event exclusion.

Produce an explicit state/order diagram for:

```text
A. mapped callback after gate begin
B. mapped callback before gate begin
```

## Deterministic test requirement

Add the minimum test seam necessary to invoke the mapped-trigger decision logic
without posting a real system CGEvent.

The test must not depend on:

- wall-clock sleeps;
- actual hidutil;
- Accessibility/TCC;
- real EventTap timing;
- BLE;
- Doubao;
- installed app state.

At minimum cover:

### Test A — control

```text
gate active
+ mapped physical trigger down
=> deferred/suppressed
=> not forwarded
```

### Test B — pre-gate candidate failure

```text
gate inactive
+ mapped physical trigger down
+ voice-key mapping active
=> record exact current decision
```

If current behavior forwards/passes the event, the test should encode that as a
failing acceptance against the candidate contract, not silently change production
behavior.

### Candidate contract

Evaluate this contract:

```text
A mapped trigger originating from the RemoteOrbit-owned physical voice button must
not be externally forwarded before RemoteOrbit has resolved gesture ownership for
that physical press.
```

Do not accept this contract automatically. Audit whether the codebase has enough
identity to distinguish:

- remote-owned mapped event;
- real keyboard Option;
- synthetic RemoteOrbit event;
- unrelated physical Option.

If the identity is insufficient, record that as an ownership-model gap rather than
guessing a fix.

## Required output

```text
CURRENT_PRE_GATE_DECISION:
PASS / SUPPRESS / DEFER / OTHER

REMOTE_OWNED_EVENT_IDENTIFIABLE_PRE_GATE:
YES / NO / PARTIAL

CANDIDATE_OWNERSHIP_CONTRACT:
ACCEPT / REJECT / NEEDS_REFINEMENT

PRE_FIX_FAILING_ACCEPTANCE:
ESTABLISHED / NOT_ESTABLISHED

SPECIFIC_BROKEN_BOUNDARY:
<boundary or NONE>

BROKEN_CONTRACT:
<contract or NONE>

MINIMAL_FIX_SCOPE:
<scope or NOT_ESTABLISHED>

CONSTRUCTION_GATE_RECOMMENDATION:
READY_FOR_REMOTE_REVIEW / BLOCKED

ROOT_CAUSE:
UNKNOWN
```

## Allowed mutations

Only:

- test-only seam/refactor needed to expose existing decision logic;
- tests;
- architecture/audit documentation;
- control-plane updates after results.

A test seam must preserve production behavior byte-for-byte in semantics.

## Forbidden

- no production behavior fix;
- no change to `optionDeferralActive` semantics;
- no suppression/replay behavior change;
- no Persistent behavior change;
- no timing threshold change;
- no BLE/audio change;
- no real capture/reproduction;
- no install;
- no merge/release.

## Stop conditions

Stop and return for review if:

- the required test seam would necessarily change production behavior;
- mapped event provenance cannot be determined from current state;
- the candidate contract conflicts with preserving real keyboard Option behavior;
- branch/head authority drifts.

## Completion gate

Step 6 is complete when:

1. current pre-gate behavior is deterministically proven;
2. remote-owned-event identifiability is classified;
3. candidate contract is accepted/rejected/refined;
4. pre-fix failing acceptance is either established or explicitly impossible;
5. no behavior fix has been applied;
6. Construction Gate remains blocked pending remote review.

## Next authorized action

Perform the deterministic pre-gate EventTap contract test and ownership architecture
review. No real-world capture or behavior fix is authorized.
