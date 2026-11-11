# RemoteOrbit Project-Specific Engineering Rules

## Product and technical references

- `README.md` describes the current RemoteOrbit voice behavior; `SETUP_NOTES.md` describes installation and real-device validation; `docs/diagnostics/ADR-*.md` records diagnostic architecture; `docs/DOMAIN_MAP.md` maps product subsystems to source and tests. Historical releases and incident records describe their captured versions, not current RC003 behavior.
- Source code and a completed build do not establish the identity or condition of the installed app, audio driver, LaunchAgent, macOS permissions or running process.

## CI and machine-side safety

- `.github/workflows/remoteorbit-ci.yml` builds and tests RemoteOrbit on `[self-hosted, macOS, ARM64, remoteorbit]`; the build environment is not a substitute for the macOS machine where the actual audio device and remote are installed.
- Routine CI is software build/test-only. It must not install/replace `/Applications/RemoteOrbit.app` or `RemoteOrbitAudio.driver`, restart `coreaudiod`, modify TCC/default audio devices, or claim scripted RC003/Doubao checks are human product acceptance.
- App replacement, HAL/audio-driver installation, CoreAudio restart, TCC/Accessibility/Input Monitoring changes, LaunchAgent changes, audio-device reassignment and running-process modification can alter the observed product runtime; source builds, documentation reads and tests must not silently perform those operations.
- During incident/forensic capture, preserve the observed app, driver, processes, permissions, LaunchAgents and diagnostic behavior before intervention. Avoid stacking speculative production changes on unresolved diagnostic or frozen experimental evidence.

## Runtime and hardware evidence

- Distinguish source checkout/HEAD, built executable, installed `/Applications/RemoteOrbit.app`, running process, installed `RemoteOrbitAudio.driver` and LaunchAgent configuration. Runtime claims need matching component/path/version/hash/process evidence; terminal/helper permissions do not establish the product process's TCC, Accessibility, Input Monitoring or event rights.
- Source/build/packaging tests alone do not prove RC003 BLE/ATVV continuity, audio delivery, HID or macOS event injection, Doubao IME acceptance, input text completeness or human-perceived latency. Real-device/runtime and applicable product-interface acceptance need separate hardware evidence and human-owned decisions. Recovery/restart alone does not prove the cause of a RemoteOrbit fault.

## Durable RC003 voice and diagnostics invariants

- The RC003 microphone button has one user-visible voice mode: release before the accepted 300 ms hold boundary (`SHORT`) is a no-op. It must not replay/emit an IME shortcut or synthetic tap, toggle/open/close Persistent sessions, use local-microphone fallback, or show voice/readiness HUD.
- Holding across 300 ms (`LONG`) starts direct RC003 BLE/ATVV remote voice, with release following established remote capture, output-drain and close behavior. Persistent and dual-receiver microphone-button semantics are retired; neither historical symbols nor configuration can reactivate them without a deliberate change to the RemoteOrbit product contract.
- Retired voice modes must have no live user-visible behavior, configuration/runtime entry points or tests asserting obsolete semantics; shared mechanisms still needed for LONG-only ownership, release, suppression, watchdog and transport remain necessary until their replacement is verified.
- Diagnostics-off optimization must not disable ownership, output-drain/release, suppression, watchdog or transport correctness. The accepted diagnostic ADR implementation remains the machine-readable evidence authority; raw audio recording is a separately controlled explicit opt-in.
