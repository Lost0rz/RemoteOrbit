# RemoteOrbit Domain Map

Status: `DERIVED_PROJECTION`
Last audited: 2026-11-25
Source routing baseline: merged Task 053 VirtualHID any-key voice shortcut architecture and current `main` governance.

This is a derived map of RemoteOrbit product capabilities to source, runtime and tests. Current implementation and product behavior take precedence over stale routes.

## RemoteOrbit source and operational entry points

| Concern | Owner / entry point |
| --- | --- |
| RemoteOrbit-specific durable product/runtime rules | `AGENTS.md` |
| Product overview | `README.md` |
| Install / operator troubleshooting | `SETUP_NOTES.md` |
| App entry / top-level orchestration | `remote-orbit/Sources/RemoteOrbit/main.swift` |
| Package definition | `remote-orbit/Package.swift` |
| App metadata | `remote-orbit/Packaging/Info.plist` |
| Routine CI | `.github/workflows/remoteorbit-ci.yml` |
| Durable diagnostics decisions | `docs/diagnostics/ADR-*.md` |

## D1 — Voice interaction and lifecycle

**Purpose:** Own the current RC003 microphone-button path: SHORT no-op, LONG direct remote voice, named voice shortcut configuration, pure-modifier/chord trigger ownership, receiver readiness, release/drain coordination and remote input lease.

**Primary source routes**

- `remote-orbit/Sources/RemoteOrbit/main.swift` — orchestration and runtime seams.
- `VoiceOptionTrigger.swift` — trigger synthesis/ownership helper used by the current runtime.
- `VoiceTriggerKey.swift` / `VoiceInputProfile.swift` — current selected trigger/profile model.
- `VoiceShortcutBinding.swift` — side-preserving pure modifiers, modifier-only chords, and modifier+primary-key chords; validated single snapshot, seed migration and settings projection.
- `VoiceShortcutEmitter.swift` — session-owned shortcut emitter compatibility layer and edge semantics.
- `VoiceShortcutHID.swift` / `VoiceShortcutHIDSecurity.swift` — VirtualHID keyboard report encoding, Unix domain socket IPC client (`VoiceShortcutHIDUnixSocketProvider`), helper interactions and peer identity checks.
- `remote-orbit/Sources/RemoteOrbitHIDBridge/` — native virtual-HID report bridge (`RemoteOrbitHIDBridge.cpp`) and pinned third-party headers.
- `remote-orbit/Sources/RemoteOrbitHIDHelper/` — VirtualHID session manager and authenticated Unix domain socket server (`RemoteOrbitHIDHelper.swift`, `RemoteOrbitHIDUnixSocketIPC.swift`).
- `remote-orbit/Sources/RemoteOrbitHIDHelperDaemon/main.swift` — root helper daemon hosting Karabiner VirtualHID connectivity for authenticated app clients.
- `VoiceReceiverReadiness.swift` — receiver/readiness coordination.
- `VoiceFocusTransactionTracker.swift` — bounded focus transaction tracking.
- `PostReleaseCaptureGrace.swift` — post-release/repress grace mechanism.

**Focused verification routes**

- `PrimaryVoiceRuntimeTests.swift`
- `VoicePipelineSimplificationTests.swift`
- `VoicePressCoordinatorTests.swift`
- `VoiceOptionTriggerTests.swift`
- `VoiceReceiverReadinessTests.swift`
- `VoiceTriggerKeyTests.swift`
- `VoiceShortcutBindingTests.swift`
- `VoiceShortcutEmitterTests.swift`
- `RemoteVoiceInputLeaseTests.swift`
- `VoiceBoundaryOrderingTests.swift`

**Retired semantic boundaries**

Persistent session, dual Receiver / Receiver B, local-microphone voice-button capture, and generic SHORT action are retired product semantics. Contract tests such as `LegacyVoiceProductSurfaceContractTests.swift`, `LegacyVoicePersistedPreferenceAuthorityContractTests.swift`, and `LocalMicrophoneCaptureRetirementContractTests.swift` protect their absence. Historical symbol names do not restore retired business authority.

## D2 — BLE / ATVV transport and protocol

**Purpose:** Connect RC003, negotiate/maintain ATVV transport, receive notifications, decode/reassemble remote audio, and recover transport connectivity.

**Primary source routes**

- `BLEBridge.swift`
- `ATVV/ATVVProtocol.swift`
- `ATVV/ADPCMDecoder.swift`
- `ATVV/ATVVKeepAliveTelemetry.swift`
- `ATVV/BridgeError.swift`

**Focused verification routes**

- `BLEBridgeTests.swift`
- `ATVVKeepAliveTelemetryTests.swift`
- protocol self-tests under `remote-orbit/SelfTests/`

**Boundary:** Transport readiness and protocol state do not by themselves prove receiver text success or input-method state.

## D3 — Audio data plane and device routing

**Purpose:** Deliver decoded remote PCM to `RemoteOrbit Mic 2ch`, own realtime buffering/playout/drain behavior, and coordinate audio-device selection.

**Primary source routes**

- `AudioPipe.swift`
- `AudioPipeRealtime.swift`
- `AudioPipePlayoutReserve.swift`
- `AudioPipeActivationTransition.swift`
- `AudioDeviceManager.swift`
- `remote-orbit-audio-driver/` — HAL driver source/build/install boundary.

**Focused verification routes**

- `AudioPipeTests.swift`
- `AudioPipeRealtimeTests.swift`
- `AudioPipePlayoutReserveTests.swift`
- `AudioDeviceManagerTests.swift`
- `AudioDataPlaneMeasurementBoundaryTests.swift`

**Boundary:** Driver install/reload and default-device mutation are operational side effects, not routine source-test actions.

## D4 — HID, gesture recognition, mapping and App integrations

**Purpose:** Observe RC003 HID input, recognize button gestures, suppress conflicting native events, resolve mappings/profiles, inject shortcuts, and route supported semantic commands to target Apps.

**Primary source routes**

- `KeyMapping/HIDMonitor.swift`
- `KeyMapping/ShortcutCaptureMonitor.swift` — physical recording and voice-only modifier-only combination capture result.
- `KeyMapping/ButtonDefinitions.swift`
- `KeyMapping/ButtonGestureRecognizer.swift`
- `KeyMapping/ButtonEdgeDebouncer.swift`
- `KeyMapping/EventSuppressor.swift`
- `KeyMapping/MappingStore.swift`
- `KeyMapping/KeyInjector.swift`
- `KeyMapping/AppTemplatePresets.swift`
- `KeyMapping/CodexCommandAdapter.swift`
- `KeyMapping/FloatTabsCommandClient.swift`
- `KeyMapping/GhosttyCommandAdapter.swift`
- `KeyMapping/ObsidianCommandAdapter.swift`

**Focused verification routes**

- `ButtonActionTests.swift`
- `ButtonGestureRecognizerTests.swift`
- `HIDButtonDownPolicyTests.swift`
- `EventSuppressorTests.swift`
- `MappingStoreRoutingTests.swift`
- `RemoteVoiceKeyMappingTests.swift`
- `ShortcutCaptureMonitorTests.swift`
- `VoiceShortcutEmitterTests.swift`

## D5 — Settings, persistence and product surface

**Purpose:** Own user-facing Control Center/settings, persisted current preferences, product branding and launch-at-login behavior.

**Primary source routes**

- `AppStorage.swift`
- `VoiceTriggerKey.swift` / `VoiceInputProfile.swift` — legacy seed adapter and active profile projection.
- `VoiceShortcutBinding.swift` — the versioned voice-only snapshot, modifier-only chord configuration and read-only invalid-data fallback.
- `ProductBranding.swift`
- `LaunchAtLogin.swift`
- `KeyMapping/SettingsView.swift`
- `KeyMapping/SettingsWindow.swift`
- `KeyMapping/KeymapOverlay.swift`

**Focused verification routes**

- `SettingsMappingNavigationTests.swift`
- `KeymapOverlayTests.swift`
- `LegacyVoiceProductSurfaceContractTests.swift`
- `LegacyVoicePersistedPreferenceAuthorityContractTests.swift`
- `VoiceShortcutBindingTests.swift`
- `ShortcutCaptureMonitorTests.swift`

**Boundary:** Historical persisted keys may remain as inert bytes for compatibility. Their presence in an old profile/defaults store does not make them current product authority.

## D6 — Diagnostics and long-term observability

**Purpose:** Provide one machine-readable diagnostic authority, bounded observation capture, read-only query/export surfaces and diagnostic hardening without taking ownership of product recovery decisions.

**Primary source routes**

- `Diagnostics/DiagnosticAuthority.swift`
- `Diagnostics/DiagnosticEvent.swift`
- `Diagnostics/JSONLinesDiagnosticJournal.swift`
- `Diagnostics/DiagnosticCLI.swift`
- `Diagnostics/DiagnosticExport.swift`
- `Diagnostics/LongTermObservability.swift`
- `Diagnostics/FrontmostApplicationDiagnosticsObserver.swift`
- `DiagnosticHardening.swift`
- `DiagnosticsRuntimeGate.swift`
- `AudioDataPlaneDiagnostics.swift`
- `VoiceDiagnosticLogger.swift`
- `WavRecorder.swift`

**Durable design routes**

- `docs/diagnostics/ADR-0001-single-diagnostic-authority.md`
- `docs/diagnostics/ADR-0002-read-only-diagnostic-cli.md`
- `docs/diagnostics/ADR-0003-long-term-observability.md`

**Focused verification routes**

- `DiagnosticAuthorityTests.swift`
- `DiagnosticCLITests.swift`
- `DiagnosticExportTests.swift`
- `DiagnosticHardeningTests.swift`
- `DiagnosticsRuntimeGateTests.swift`
- `LongTermObservabilityTests.swift`
- `LongTermObservabilityDocumentationTests.swift`
- `AudioDataPlaneDiagnosticsTests.swift`
- `VoiceDiagnosticLoggerTests.swift`
- `WavRecorderDiagnosticsTests.swift`

**Boundary:** Diagnostics can preserve evidence and classify anomalies; they do not establish receiver text, firmware/radio causality, or root cause by themselves. Diagnostics-off must not disable correctness mechanisms.

## D7 — Packaging, installation and distribution

**Purpose:** Build the menu-bar app and audio driver, package the DMG/pkg payload, install supported components and expose installation status.

**Primary routes**

- `remote-orbit/Packaging/` (includes `Karabiner-DriverKit-VirtualHIDDevice-8.6.0.pkg` and `Info.plist`)
- `remote-orbit/package-app.sh`
- `remote-orbit/install-app.sh`
- `remote-orbit-audio-driver/`
- `installer/`
- `package-dmg.sh`
- `InstallationSupport.swift` — bundled HAL audio driver repair, VirtualHID + `RemoteOrbitHIDHelperDaemon` installation/update diagnostics, and SHA-256 helper drift detection.

**Boundary:** Packaging and installation can replace the installed app or HAL driver and restart CoreAudio; these observable runtime effects are separate from building or inspecting source.

## Cross-domain runtime path

```text
RC003 HID press
  -> D4 HID / gesture boundary
  -> D1 SHORT/LONG classification and trigger ownership
  -> D2 BLE/ATVV transport and remote audio reception
  -> D3 decode/output supply -> RemoteOrbit Mic 2ch
  -> D1 receiver trigger/readiness + release/drain lifecycle

Meanwhile:
  D6 observes bounded evidence without owning the production state machine
  D5 owns user configuration/product surface
  D7 owns build/install/distribution boundaries
```

