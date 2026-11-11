# RemoteOrbit Project-Specific Engineering Rules

## Project authority and references

- This file owns only RemoteOrbit-specific product, hardware, macOS runtime, diagnostics and evidence constraints. The installed Engineering Governance plugin and its versioned global policy own reusable engineering routing, task authorization, approvals, Issue authoring, audits, verification selection, workspace/PR lifecycle, delivery and closeout. This project file cannot select or override those mechanisms or grant permissions.
- `README.md` owns the current product overview and voice contract; `SETUP_NOTES.md` owns installation and real-device validation; `docs/diagnostics/ADR-*.md` owns accepted diagnostic architecture. `docs/DOMAIN_MAP.md` is derived navigation, not an independent product/task authority. Historical releases and incident records do not revive retired voice behaviors. Do not silently redesign accepted product behavior.
- GitHub/cloud source evidence does not prove local app, driver, LaunchAgent, macOS permission, worktree, or running-process state.

## CI and machine-side safety

- `.github/workflows/remoteorbit-ci.yml` is the routine source/test/build CI entry point, with expected runner labels `[self-hosted, macOS, ARM64, remoteorbit]` unless explicitly changed by authorized project policy. Runner unavailability does not permit unapproved paid hosted-macOS fallback or mutation of the runner's product runtime.
- Routine CI is software build/test-only. It must not install/replace `/Applications/RemoteOrbit.app` or `RemoteOrbitAudio.driver`, restart `coreaudiod`, modify TCC/default audio devices, or claim scripted RC003/Doubao checks are human product acceptance.
- App installation/replacement, HAL or audio-driver changes, CoreAudio restart, TCC/Accessibility/Input Monitoring changes, LaunchAgent changes, device reassignment and running-product mutation are distinct authorized runtime side effects, not implied by source, test or documentation scope.
- During incident/forensic capture, preserve the observed app, driver, processes, permissions, LaunchAgents and diagnostic behavior unless the selected task expressly authorizes intervention. Do not stack speculative production changes on unresolved diagnostic or frozen experimental evidence.

## Runtime and hardware evidence

- Distinguish source checkout/HEAD, built executable, installed `/Applications/RemoteOrbit.app`, running process, installed `RemoteOrbitAudio.driver` and LaunchAgent configuration. Runtime claims need matching component/path/version/hash/process evidence; terminal/helper permissions do not establish the product process's TCC, Accessibility, Input Monitoring or event rights.
- Source/build/packaging tests alone do not prove RC003 BLE/ATVV continuity, audio delivery, HID or macOS event injection, Doubao IME acceptance, input text completeness or human-perceived latency. Real-device/runtime and applicable product-interface acceptance need separate hardware evidence and human-owned decisions. Material claims must distinguish FACT, INFERENCE, HYPOTHESIS, UNKNOWN and HISTORICAL; recovery/restart alone does not prove a cause.

## Durable RC003 voice and diagnostics invariants

- The RC003 microphone button has one user-visible voice mode: release before the accepted 300 ms hold boundary (`SHORT`) is a no-op. It must not replay/emit an IME shortcut or synthetic tap, toggle/open/close Persistent sessions, use local-microphone fallback, or show voice/readiness HUD.
- Holding across 300 ms (`LONG`) starts direct RC003 BLE/ATVV remote voice, with release following established remote capture, output-drain and close behavior. Persistent and dual-receiver microphone-button semantics are retired; neither historical symbols nor configuration can reactivate them without an authorized product-contract change.
- Retire obsolete voice modes by actual production authority, not symbol names. Remove their user-visible behavior, live configuration/runtime entry points and tests that assert retired semantics; retain shared mechanisms needed for correct LONG-only ownership, release, suppression, watchdog and transport until equivalently replaced with verification.
- Diagnostics-off optimization must not disable ownership, output-drain/release, suppression, watchdog or transport correctness. The accepted diagnostic ADR implementation remains the machine-readable evidence authority; raw audio recording is a separately controlled explicit opt-in.
