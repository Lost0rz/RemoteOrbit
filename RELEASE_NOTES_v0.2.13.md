# RemoteOrbit v0.2.13

## Audio transport / stability

- Add bounded ATVV v1.0 frame reassembly using negotiated `frameSize`.
- Correctly handle partial, exact and multi-frame BLE notifications.
- Reset frame accumulation correctly on stream and `AUDIO_SYNC` boundaries.
- Preserve existing voice activation, Option ownership and tail behavior.

## Diagnostics

- Add P0/P1 audio data-plane diagnostics.
- Add BLE notification/decode telemetry.
- Add AudioPipe render/underrun accounting.
- Add P1-A4 lifecycle correlation telemetry.
- Add P1-A5 front-edge diagnostics.
- Diagnostic functionality remains non-required for normal use.

## Hardware validation

P1-A5:

- 15/15 independent sessions completed.
- first packet: 15/15
- first decode: 15/15
- first submit: 15/15
- first render: 15/15
- decode rejects: 0
- visible start loss: not reproduced
- visible mid loss: not reproduced
- visible tail loss: not reproduced

Known observation:

- micro playout underruns remain observable
- sustained startup starvation was not observed
- underrun → text loss correlation was not established

## Explicitly excluded

- Adaptive Playout
- BLE queue experiments
- silence padding
- additional stop/drain timing changes
- Option timing experiments
- P1A5 Observer runtime dependency

## Version

RemoteOrbit 0.2.13
Build 42
Universal 2
