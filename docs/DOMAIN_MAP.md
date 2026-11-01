# RemoteOrbit Domain Map

Status: `DERIVED_PROJECTION`
Last audited: 2026-11-01
Source snapshot used for route verification: `eac33e1583565e053335a39ec56427e4dc589765`

This file is a navigation map derived from current source and tests. It does **not** own product behavior, task authority, release state, or runtime facts. When this map conflicts with `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md`, current implementation authority, or fresh runtime evidence, the owning authority wins and this map must be refreshed.

## Authority and entry points

| Concern | Owner / entry point |
| --- | --- |
| Durable product and engineering rules | `AGENTS.md` |
| Mutable project state | `CURRENT_STATUS.md` |
| Active execution authorization | `CURRENT_TASK.md` |
| Product overview | `README.md` |
| Install / operator troubleshooting | `SETUP_NOTES.md` |
| App entry / top-level orchestration | `remote-orbit/Sources/RemoteOrbit/main.swift` |
| Package definition | `remote-orbit/Package.swift` |
| App metadata | `remote-orbit/Packaging/Info.plist` |
| Routine CI | `.github/workflows/remoteorbit-ci.yml` |
| Durable diagnostics decisions | `docs/diagnostics/ADR-*.md` |

## D1 — Voice interaction and lifecycle

**Purpose:** Own the current RC003 microphone-button path: SHORT no-op, LONG direct remote voice, trigger ownership, receiver readiness, release/drain coordination and remote input lease.

**Primary source routes**

- `remote-orbit/Sources/RemoteOrbit/main.swift` — orchestration and runtime seams.
- `VoiceOptionTrigger.swift` — trigger synthesis/ownership helper used by the current runtime.
- `VoiceTriggerKey.swift` / `VoiceInputProfile.swift` — current selected trigger/profile model.
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

## D5 — Settings, persistence and product surface

**Purpose:** Own user-facing Control Center/settings, persisted current preferences, product branding and launch-at-login behavior.

**Primary source routes**

- `AppStorage.swift`
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

- `remote-orbit/Packaging/`
- `remote-orbit/package-app.sh`
- `remote-orbit/install-app.sh`
- `remote-orbit-audio-driver/`
- `installer/`
- `package-dmg.sh`
- `InstallationSupport.swift`

**Boundary:** Packaging/install/release are distinct lifecycle actions. A source/doc/diagnostic task does not authorize installation, CoreAudio restart, tag, Release, or publication.

## D8 — Repository governance, CI and evidence lifecycle

**Purpose:** Keep one current project authority, route routine verification, and prevent historical plans/incidents from becoming live task or product authority.

**Primary routes**

- `AGENTS.md`
- `CURRENT_STATUS.md`
- `CURRENT_TASK.md`
- `.github/workflows/remoteorbit-ci.yml`
- `docs/README.md`
- `docs/incidents/README.md`

**Historical evidence routes**

- `docs/incidents/*.md`
- root `RELEASE_NOTES_v*.md`
- Git history for completed task plans/designs removed from the active documentation tree.

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
  D8 owns project/task/document authority boundaries
```

## Refresh rule

Refresh only the Domain routes materially affected by source/test/ownership changes. Do not rewrite this whole map simply to record that a check occurred. A source move, retired/added capability, changed owner, changed test route, changed runtime entry point, or contradiction with current source is a refresh trigger.
