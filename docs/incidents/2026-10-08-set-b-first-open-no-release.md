# RemoteOrbit Set-B Incident

Date: 2026-10-08
Task: RO-DUAL-RECEIVER-SYSTEM-MAPPED-IMPLEMENTATION-023
State: ROOT CAUSE UNKNOWN / READ-ONLY CAPTURE

## User-observed symptom

During the first authorized Set-B attempt:

- Receiver B opened successfully on quick-first-tap + second-LONG.
- Releasing the remote did not close Receiver B.
- Subsequent attempts could not open the receiver path normally.

## Immediate interpretation boundary

This proves the B admission/open path can work at least once. It does not yet prove the failure layer.

The failure is currently bounded to one or more of:

- physical second-UP not reaching the B hardware gate;
- mapped B UP retained or discarded incorrectly;
- VoicePressCoordinator release/tail ownership not closing;
- output drain not completing;
- B->A mapping restore not starting or not completing;
- runtime entering a locked/unavailable phase after the first B transaction;
- external receiver/session behavior diverging from internal ownership.

No causal classification is authorized before read-only evidence.

## Freeze

Do not perform further remote gestures, change settings or mapping, restart RemoteOrbit, rebuild/reinstall, modify source/tests, or merge until the incident capture is audited.

## Required evidence

Capture the exact first Set-B attempt and the immediate failed follow-on attempts if already present. Preserve all relevant sequence numbers and monotonic timestamps for:

- raw first tap DOWN/UP;
- A->B mapping apply start/end and FIRST_UP_TO_SECONDARY_READY_MS;
- second physical DOWN/UP;
- second_down_ready_before_edge;
- mapped Right Option DOWN/UP capture/replay/discard;
- HardwareOptionGate ownership transitions;
- B classification and first PCM;
- AUDIO_START/AUDIO_STOP;
- VoicePressCoordinator release/tail/output-drain ownership;
- MOMENTARY_COMPLETE or its absence;
- B->A restore request/apply/filter update/readback;
- runtime lock/unavailable transitions;
- final F5 mapping, filter target, mapping phase and active transaction.

Root cause remains UNKNOWN until Web audits the capture.
