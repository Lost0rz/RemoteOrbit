# CURRENT_STATUS

Last updated: 2026-10-30
State: `RO-VOICE-PIPELINE-SIMPLIFICATION-042 — READY_FOR_HUMAN_RUNTIME_ACCEPTANCE`
Repository: `Lost0rz/RemoteOrbit`

## Current authority

- Active branch: `codex/voice-pipeline-simplification-042`.
- `AGENTS.md` remains durable repository authority.
- `CURRENT_TASK.md` is the sole active execution authorization.
- Frozen 041 observability baseline: `ac3132986197bfee4440bb8f388e3d2e5f478f03`.

## Accepted semantic lineage

- Gate A: `50b1d9efabe15f04d5479b39af227d0e6f43a4e3` — CLOSED / INDEPENDENT AUDIT PASS.
- Gate B: `ae0bf10874d34ce556b4b73a506b22f6a9a1a412` — CLOSED / INDEPENDENT AUDIT PASS.
- Gate C: `9abdebc21a1e03c79ab0ac960bf2d9902c24b1d5` — CLOSED / INDEPENDENT AUDIT PASS.
- Gate D: `9cdbf6f5190d9ed453d7f15cf2e8192973cc62ad` — CLOSED / INDEPENDENT AUDIT PASS.
- Gate E / final source candidate: `2d09b6d77f9f75aa46bb4a13838cd22d5589f524` — CLOSED / INDEPENDENT SOURCE AUDIT PASS.

## Final source acceptance

The 042 source construction is complete. The accepted production model is:

```text
VOICE DOWN
→ capture one VoiceInputProfile / trigger identity
→ trigger DOWN immediately; no classifier/PCM/render gate
→ strict-READY ATVV MIC_OPEN
→ AUDIO_START / decode / PCM submit
→ fixed 45 ms one-shot playout reserve
→ realtime ring-backed CoreAudio playout

VOICE UP / terminal transport loss
→ deterministic retirement
→ BLE/audio-stop tail retirement when available
→ remote route inactive
→ reserve tail bypass when still waiting
→ actual ring empty / output drain
→ same captured trigger UP at most once
→ IDLE
```

Gate E source audit accepted the bounded failure-retirement correction: transport loss can retire a direct session even without a later physical UP; pre-READY voice intent loss reaches the same connection-loss owner; no-AUDIO_START MIC_CLOSE emits the existing streaming-retired signal; stale output-drain callbacks remain session-ID guarded. No Gate A-D architecture, 45 ms default, ring capacity, BLE queue/strict READY, ATVV protocol, driver, or runtime policy changed.

Executor evidence at the Gate E semantic head recorded focused Gate E/regression suites `144/144`, full Swift `563/563`, arm64/x86_64 Release builds, protocol self-tests `3/3`, and `git diff --check` passing. Independent Web audit accepts source semantics only; installed/hardware/Air/natural-use acceptance is still pending.

## Candidate preparation receipt

Candidate preparation completed on the canonical writer after fast-forwarding the
live branch to control head `2762d584b505c85b7cc319db1b188177120f4500`.

- Accepted semantic source head: `2d09b6d77f9f75aa46bb4a13838cd22d5589f524`.
- The accepted-to-live range contains only `CURRENT_STATUS.md` and `CURRENT_TASK.md`;
  the non-governance diff is empty.
- Worktree was clean before preparation; the tracked worktree remains clean after
  preparation. Local and `origin/codex/voice-pipeline-simplification-042` were equal
  at the audited control head before this receipt commit.
- Established flow: `./package-dmg.sh` (including its existing driver build,
  `remote-orbit/package-app.sh`, `pkgbuild`, `productbuild`, and `hdiutil` steps).
  Release app and DMG/package production returned success. Xcode emitted existing
  CoreDevice/CoreSimulator plugin warnings, but the driver and app build steps
  completed successfully.
- App artifact: `/private/tmp/remoteorbit-voice-pipeline-simplification-042/remote-orbit/dist/RemoteOrbit.app`.
  DMG: `/private/tmp/remoteorbit-voice-pipeline-simplification-042/dist/RemoteOrbit-0.2.14.dmg`.
  DMG SHA-256: `0e6e91e665505c618c29f2fc3082b1c35fffe681dc28e97c47aeae6a331c4ad5`.
- Candidate identity: Bundle ID `com.lost0rz.RemoteOrbit`, version `0.2.14`, build
  `43`, architectures `x86_64 arm64`. App `codesign --verify --deep --strict`
  passed with the ad-hoc designated requirement; no Team ID is present by policy.
  The app plist source stamp is the live control head.
- Installation: the existing RemoteOrbit process was quit cleanly, then the exact
  candidate was installed at `/Applications/RemoteOrbit.app`. The installed app's
  executable, Info.plist, and complete regular-file SHA-256 manifest matched the
  packaged checkout app; installed code-sign verification passed. This is app-bundle
  provenance, not a claim that DMG container bytes equal the installed bundle.
- Runtime: PID `80225`, executable
  `/Applications/RemoteOrbit.app/Contents/MacOS/RemoteOrbit`; PID remained stable
  during the readiness check. App log recorded version/build, audio IOProc startup,
  `RemoteOrbit Mic 2ch`, Bluetooth ready, HID input/accessibility permissions,
  event suppressor readiness, and monitored RC003 connection.
- `RemoteOrbit Mic 2ch` was present as the default input with 2 channels, 48 kHz,
  and USB transport. Bluetooth system evidence showed the connected Xiaomi remote
  with VID `0x2717`, PID `0x32B8`, and BLE service. Existing diagnostic CLI status
  reported the v1 journal present, and `diagnostics verify` returned `{"ok":true,
  "schema_version":1}`.
- No product source, package script, installed driver, driver reload, TCC reset,
  merge, tag, release, or publication was performed. The established package flow
  did create the ignored candidate driver build artifact; the installed driver was
  not replaced and its executable hash remained
  `d2c72d9e433e2f6ccdec50eb8298e3e36ddbbb0d0f72e13b728c17f6a48c5446`.

## Current phase — Human runtime acceptance

No Gate F exists. The next authorized phase is candidate preparation for runtime acceptance.

Candidate source identity is frozen at:

`2d09b6d77f9f75aa46bb4a13838cd22d5589f524`

Local execution may build/package/install exactly this accepted product source (plus control-only descendants whose product-source diff is empty), verify artifact provenance, launch the candidate, and prepare bounded diagnostics for human natural-use testing.

Source/product changes are not authorized in this phase. If packaging or runtime preparation appears to require a product-code change, stop and report the dependency instead of repairing it.

## Stop / next

Candidate preparation is complete. Stop at `READY_FOR_HUMAN_RUNTIME_ACCEPTANCE`.
The user owns the subsequent hardware/natural-use exercise and any diagnostic
export; do not simulate, self-approve, merge, tag, release, publish, reset TCC,
change the audio driver, or create Gate F.
