# RemoteOrbit v0.2.15

## Baseline

This release freezes the current accepted RemoteOrbit product baseline at:

- Version: `0.2.15`
- Build: `44`
- Source baseline: `7f1c763e60db8c9ecc4a696f4246d3ee9eaaea1a`
- Distribution: Universal 2 (`arm64` + `x86_64`)

## Voice interaction simplification

- The RC003 microphone button now has one production voice contract.
- A quick SHORT tap is a no-op.
- A held LONG press crosses the accepted 300 ms boundary and enters the direct remote-voice lifecycle.
- Persistent-session, Dual Receiver / Receiver-B, local-microphone voice-button and legacy generic-short product semantics have been retired from production authority.
- Persisted legacy voice preferences no longer seed the active voice profile.

## Voice stability and responsiveness

- Hardened the LONG voice pipeline around rapid repress, physical-key ownership, receiver-readiness and release/drain ordering.
- Tightened the direct remote-input lifecycle so the remote ATVV path remains the authoritative voice source.
- Added bounded ownership and post-release handling for cases where a fast follow-up press arrives near the prior session boundary.
- Added focused regression coverage for voice boundary ordering, primary runtime behavior, remote-input leasing and pipeline simplification.

## Audio pipeline

- Split realtime AudioPipe responsibilities into clearer activation, realtime and playout-reserve boundaries.
- Expanded audio data-plane accounting and delivery diagnostics while keeping correctness mechanisms separate from optional diagnostics.
- Retained the dedicated `RemoteOrbit Mic 2ch` HAL route and hardened remote PCM delivery/drain behavior.
- Packaging continues to build the app as Universal 2 and bundles the independently built RemoteOrbitAudio driver.

## Diagnostics and observability

- Established a single machine-readable diagnostic authority and read-only diagnostic CLI surface.
- Added bounded long-term voice observability with L1 session summaries and anomaly-only L2 traces.
- Added bounded diagnostic export with runtime provenance and checksum evidence.
- Diagnostics are now gated by the user logging setting or the explicit `REMOTE_ORBIT_DIAGNOSTICS=1` operator override; diagnostics-off operation does not disable correctness/safety mechanisms.
- Legacy diagnostic experiments and retired front-edge instrumentation no longer define current product behavior.

## Product surface and maintenance

- Simplified Settings around the current direct-transmission voice model and removed retired Persistent/Dual Receiver controls.
- Refreshed RemoteOrbit product branding/icon assets.
- Added the repository-scoped self-hosted macOS ARM64 CI baseline.
- Rebuilt the project Domain Map and documentation authority so current product contracts are separated from historical incident/release evidence.

## Release verification

The v0.2.15 publication workflow is required to pass, against the exact source baseline above:

- protocol self-tests;
- full Swift tests;
- pinned RemoteOrbitAudio driver build;
- Universal 2 application packaging;
- DMG packaging;
- version/build metadata verification;
- code-signature verification;
- SHA-256 generation for the published DMG.

This release does not claim a new root cause for historical receiver-side failures, and it does not substitute CI for user-owned real-hardware/runtime acceptance.
