# Task 045B Domain 6 — Local Microphone Capture & Temporary Input Lease Retirement

Date: 2026-11-01
Task: `RO-DIAGNOSTICS-LEGACY-RETIREMENT-045`
Domain: `LOCAL_MICROPHONE_CAPTURE`
Audit basis: merged `main@07c6f294e436a987d526a085d7386c7f15b830b1`

## Design question

How should RemoteOrbit retire its now-unreachable local/external microphone AVCapture pipeline without deleting the current user-facing system input selector or breaking remote LONG tail-drain and rapid-repress correctness?

## Verified facts / constraints

- The accepted product contract is remote-only for the microphone button: SHORT `<300 ms` is user-visible no-op; LONG `>=300 ms` promotes the Xiaomi ATVV remote microphone.
- Domain 5 removed the last production callers that requested local/external microphone capture.
- `AudioPipe.swift` still owns local microphone runtime: AVFoundation/CoreMedia capture imports, `AVCaptureSession`, permission state, `setLocalMicrophoneCaptureEnabled(...)`, start/stop capture, sample-buffer conversion and local scheduling.
- The menu-bar `输入设备` selector is a current documented product feature. It includes physical microphones and `RemoteOrbit Mic 2ch`, writes macOS default input and persists the user's stable preferred input identifier.
- `SystemAudioDeviceManager.selectRemoteOrbitInputForVoice()` intentionally selects the virtual microphone for voice without overwriting that preference.
- Current `AudioPipe.setRemoteActive(false)` restores preferred input only when the old local-capture request flag is true. With Domain 5 callers removed, a physical preference can be overwritten by the first remote LONG and not restored during the same run.
- Remote route deactivation precedes actual ring/output drain. A restore at transport stop would switch the system input while queued remote PCM is still part of the active voice lifetime.
- Direct rapid repress may hand A's ownership to B across A's output drain. Restoring physical input between A and B would add unnecessary route churn and risks interrupting the next remote voice opening.
- Packaged `NSMicrophoneUsageDescription` exists because the local AVCapture path requests microphone TCC. BLE remote PCM and the CoreAudio output/virtual-device path do not themselves require AVCapture microphone access.
- The realtime ring still supports mixed `.remote` / `.local` attribution. Removing that abstraction is not required to remove the actual local microphone capture owner.

## User / project decisions

- Keep the current system input/output selector and persisted input preference.
- Keep the current remote-only microphone-button contract and all LONG-only correctness mechanisms.
- Keep actual remote output drain as the lifetime boundary for releasing final voice ownership.
- Legacy retirement remains domain-bounded; unrelated realtime/data-plane cleanup belongs to a later audit.

## Selected option

Retire **local microphone capture ownership** while preserving **system input preference ownership** as a separate product capability.

Model the remote virtual microphone selection as a temporary system-input lease:

1. A promoted remote LONG acquires/retains `RemoteOrbit Mic 2ch` as the active system input using the existing temporary selection mechanism.
2. Transport stop deactivates remote sample production but does not restore the saved physical input.
3. The lease remains through actual AudioPipe output drain.
4. At post-drain direct-session completion, if an immediately pending direct successor owns the next session, transfer the lease to that successor without restoring physical input.
5. When the final direct session completes with no successor, restore `SystemAudioDeviceManager`'s persisted preferred input.
6. If the persisted preference is RemoteOrbit itself, restoration remains an idempotent no-op/equivalent selection.

Do not restore preferred input inside `AudioPipe.setRemoteActive(false)`.

## Why this option

It separates two concepts that historical code mixed:

- **capture source ownership** — obsolete local AVCapture logic and TCC lifecycle;
- **system default input preference** — current user-facing macOS device-selection feature.

Deleting both would remove a current product capability. Keeping both would preserve dead microphone capture/TCC complexity. Restoring input at transport stop would violate the proven output-drain lifetime. The temporary-lease model removes dead ownership while matching the current remote voice lifecycle.

## Rejected alternatives

### Delete the whole physical-input selector with AVCapture

Rejected. Current menu/UI, persistence code, README and setup authority all describe physical input selection as a supported general system-device feature. It is not dependent on RemoteOrbit capturing that microphone itself.

### Restore preferred input directly in `AudioPipe.setRemoteActive(false)`

Rejected. `setRemoteActive(false)` runs before queued remote PCM drains. This would switch system input before the current voice session has actually completed.

### Restore immediately at A drain, then reacquire RemoteOrbit for rapid B

Rejected. Direct rapid-repress is intentionally a bounded ownership handoff. Releasing/reacquiring the system input between sessions introduces avoidable route churn and weakens continuity.

### Remove all `.local` source attribution from the realtime ring in the same domain

Rejected as the default implementation strategy. That is a low-level data-plane simplification not required to remove AVCapture or TCC. It may be done only where compile-local and behavior-neutral; otherwise it remains frozen for Wave D.

## Ownership after Domain 6

### User preference owner

`SystemAudioDeviceManager`

Owns:
- enumerating supported input devices;
- persisting the preferred input stable identifier;
- user-initiated default input changes;
- startup/driver-reload preferred-input restoration.

### Temporary remote input owner

The direct remote voice lifecycle owns a temporary `RemoteOrbit Mic 2ch` lease from promoted route activation through final output drain/session completion. The implementation should use the smallest testable seam; it must not turn AudioPipe transport deactivation into preference restoration authority.

### Retired owner

`AudioPipe` no longer owns physical/external microphone capture, microphone permission requests or local PCM conversion/submission.

## Interface implications

The menu-bar `输入设备` submenu remains. Selecting a physical input continues to persist it and set it as macOS default while idle.

When remote voice starts, RemoteOrbit temporarily switches to `RemoteOrbit Mic 2ch`. After the final remote session fully drains, RemoteOrbit returns to the persisted user preference unless that preference is already RemoteOrbit.

A rapid direct repress keeps RemoteOrbit selected continuously across A→B.

No new user-facing control is required.

## Permission implications

After AVCapture local-microphone code is gone, RemoteOrbit must not request microphone TCC. Remove `NSMicrophoneUsageDescription` from the packaged plist and update current install/setup instructions accordingly.

Bluetooth, Input Monitoring, Accessibility and Apple Events permissions remain governed by their existing features and are outside this domain.

## Realtime/data implications

Keep the remote `AudioPipe` path intact:
- candidate/prebuffer;
- 16 kHz ATVV decode input and existing resampling/gain;
- fixed-capacity PCM ring;
- playout reserve;
- CoreAudio IOProc/render;
- remote queue accounting;
- output-drain signalling;
- diagnostics/recording gates.

Local-capture-specific realtime flags/branches may be removed when directly dead. Broader source-attribution cleanup is not required for Domain 6 and is frozen for Wave D if it would reshape the ring.

## Verification implications

Tests must prove ordering, not merely source deletion:

- no AVCapture microphone owner or permission request remains;
- current physical input enumeration/persistence remains;
- remote route temporarily selects RemoteOrbit without modifying the saved preference;
- transport stop does not restore the preferred input before output drain;
- final post-drain completion restores it;
- rapid A→B suppresses the intermediate restore and final B completion restores once;
- saved RemoteOrbit preference is idempotent;
- tests use injected/pure seams and do not mutate the host's real default input;
- remote audio, LONG-only and diagnostics regressions remain green.

## Consequences

RemoteOrbit no longer opens the Mac's physical microphone or requires microphone TCC. The existing system input selector remains useful as a general macOS preference and is no longer confused with an internal capture path.

The temporary remote-input lease becomes aligned with the actual remote voice lifetime rather than transport-active state.

Some generic mixed-source ring attribution may remain temporarily even though there is no production local producer. That residue is intentionally safer to assess during the final Wave D resource/regression audit.

## Reversibility

Moderate-high. The AVCapture deletion is recoverable from history and no user configuration schema is removed. Input preference persistence is retained. The new lifecycle seam is bounded to selecting/restoring the system input around an already-existing remote route.

## Reversal trigger

Reconsider only if a future accepted product requirement explicitly needs RemoteOrbit itself to capture a physical/external microphone again. Merely allowing the user to select a macOS default input is not such a requirement.

TASK_RECONCILIATION_REQUIRED: `YES`
REASON: Domain 5 is merged/closed and task authority must advance to the bounded Domain 6 implementation.
DURABLE_DOCUMENT: `docs/design/2026-11-01-045b-domain-6-local-microphone-capture-retirement.md`
