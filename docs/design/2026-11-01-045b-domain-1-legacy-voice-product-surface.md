# Task 045B Domain 1 — Legacy Voice Product Surface Retirement

Date: 2026-11-01
Task: `RO-DIAGNOSTICS-LEGACY-RETIREMENT-045`
Domain: `LEGACY_VOICE_PRODUCT_SURFACE`
Audit basis: merged `main@27357a8e6301507b712ef65e9a74e973786dd263`

## Design question

What is the smallest legacy-voice domain that can be retired now without mixing user-facing cleanup with Persistent/Dual runtime-state deletion?

## Verified constraints

- The durable product contract is SHORT no-op and LONG direct remote voice.
- Production microphone DOWN/UP already enters the Gate A direct path; application mappings and the historical microphone short/long classifier do not participate in that production path.
- `VoiceInputProfile` / `VoiceInputProfileStore` is the retained voice-trigger configuration authority. Persistent and Receiver-B preferences do not seed or compete with it.
- The current Settings microphone page already has a direct-transfer card, but the source still retains unused legacy state, callbacks, cards and runtime bridge code for Persistent, Receiver B and microphone SHORT configuration.
- `SettingsWindow` and `main.openKeyMapping` still carry callback plumbing solely to support those obsolete Settings controls.
- `KeymapOverlay` still shows obsolete microphone single-click semantics such as `输入法持续会话`.
- `ButtonBinding.voiceKeyDefault` is persisted in existing mapping data. Removing the enum case now would be a configuration-schema compatibility change, not merely a product-surface cleanup.
- AppStorage Persistent/Receiver-B keys and Persistent/Dual runtime state remain connected to historical runtime/test plumbing and require their own later audits.

## Selected option

Retire **only the Legacy Voice Product Surface** first.

This domain removes obsolete user-facing semantics and Settings-only wiring while deliberately retaining persistence/runtime compatibility internals for later domains.

### Why this option

It provides a clean, independently verifiable deletion boundary:

- user-facing product no longer advertises behavior that production intentionally does not support;
- current runtime ownership is unchanged;
- existing mapping files remain decodable;
- later audits can separately prove whether old preferences and state machines are truly removable without conflating UI cleanup with ownership changes.

Rejected alternative: delete UI + AppStorage + Persistent runtime + Dual runtime in one pass. That would combine presentation, persistence, mapping compatibility, HID reconfiguration, gesture recognition and voice ownership into one large change, making regression attribution weak and violating the requested domain-by-domain retirement process.

## Ownership after Domain 1

### Canonical retained authority

`VoiceInputProfile` / `VoiceInputProfileStore`

This remains the user-selected voice trigger configuration owner.

### Compatibility-only token

`ButtonBinding.voiceKeyDefault`

Keep its enum/Codable representation so existing mapping files continue decoding. Its product-facing text must no longer describe Persistent/SHORT behavior. Runtime/persistence removal of the token itself is not authorized in Domain 1.

### Retired product surface

The following cease to exist as Settings/product presentation concepts:

- Persistent-session activation-key selection;
- Receiver-B selection/configuration;
- microphone SHORT mode selection (Persistent IME vs Codex voice chat);
- microphone single-click behavior in the keymap overlay;
- Settings runtime bridge/callbacks dedicated only to those controls.

## Interface implications

### Settings

For the microphone button, keep the current direct-transfer explanation. Do not expose legacy single-click/Persistent/Receiver-B controls.

Voice-trigger profile selection remains through the existing retained profile authority/menu path; Domain 1 does not redesign that owner.

### Keymap overlay

The microphone is a fixed production semantic. Its presentation must not be derived from the legacy base binding's single-click meaning. Display only the retained remote LONG voice action.

### Mapping compatibility

Existing files containing `.voiceKeyDefault` must still decode/encode. Do not rewrite user mapping files solely for this retirement.

## KEEP / RETIRE / FROZEN matrix

### RETIRE

- `SettingsView` types/state/functions/messages dedicated to Persistent-session configuration;
- `SettingsView` types/state/functions/messages dedicated to Receiver B;
- `SettingsView` types/state/functions/messages dedicated to microphone SHORT configuration;
- `VoiceSettingsRuntimeBridge` if no retained Settings consumer remains;
- corresponding `SettingsWindow` parameters;
- corresponding `main.openKeyMapping` Settings-only closure wiring;
- stale KeymapOverlay microphone single-click presentation;
- stale Persistent wording in user-facing `.voiceKeyDefault` display text and default-mapping comments.

### KEEP

- `VoiceInputProfile` / store;
- normal direct voice-trigger reconfiguration used by the retained profile owner;
- `.voiceKeyDefault` Codable case;
- existing mapping schema and bytes;
- Gate A LONG-only production path;
- current correctness mechanisms.

### FROZEN FOR LATER DOMAIN

- Persistent and secondary preference keys/readers/writers/migration in `AppStorage`;
- AppController legacy current Persistent/secondary state;
- Persistent apply/configuration methods;
- Dual mode apply/configuration methods;
- `VoiceSessionMode`, `PendingPersistentToggle`, `RemoteSegmentTriggerPolicy`;
- `DualReceiverVoiceGestureRecognizer`, `DualReceiverVoiceMode`, `DualReceiverMappedTriggerState`;
- Persistent/Dual behavioral tests;
- shared suppression/tombstone/repress mechanisms.

## Verification implications

Domain 1 acceptance requires evidence that:

- no product-source Settings legacy surface remains;
- no stale keymap single-click voice semantics remain;
- mapping compatibility token still round-trips;
- profile authority remains intact;
- LONG-only regression is unchanged;
- full Swift/Release/Universal2 durable CI passes.

A focused source-contract test is appropriate to prevent the retired product strings/types from silently returning to Settings/Keymap presentation.

## Consequences

The repository will temporarily retain legacy persistence/runtime code that no longer has a product-facing configuration entry. This is intentional: those components are evidence targets for later domains, not hidden supported features.

## Reversibility

High. Domain 1 is primarily deletion of obsolete Settings/presentation wiring and text. Existing persisted mapping tokens and runtime state are left intact, so rollback does not require data migration.

## Next domains

After Domain 1 implementation is independently audited and merged, Web performs a fresh audit before selecting the next domain. Expected candidates, not pre-authorized order:

- legacy voice persistence/config plumbing;
- Dual Receiver runtime;
- Persistent session runtime;
- residual tests/docs/naming and final retirement verification.

No later domain is authorized by this document.

TASK_RECONCILIATION_REQUIRED: `YES`
REASON: Task authority must move from completed diagnostics gating to the bounded Domain 1 product-surface retirement.
DURABLE_DOCUMENT: `docs/design/2026-11-01-045b-domain-1-legacy-voice-product-surface.md`
