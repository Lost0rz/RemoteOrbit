# CURRENT_STATUS

Last updated: 2026-10-31
State: `RO-VOICE-PIPELINE-SIMPLIFICATION-042 — READY_FOR_HUMAN_RUNTIME_ACCEPTANCE`
Repository: `Lost0rz/RemoteOrbit`
Active branch: `codex/voice-pipeline-simplification-042`

## Current authority

- Corrective A source remains `3d7b55cc557e52e994ff5c5a6b4c2217189f2751`.
- Corrective B callback-ordering source is `b4904f2faf26535fd39ba97d3a5dd30440de13b9`.
- Pre-audit control handoff is `34f4b5892307355948660b9de7d2e2008119e036`.
- Independent Web `CODE_DIFF` audit of Corrective B: `PASS`.
- Human RC003 runtime acceptance for the newly audited source has not yet been run. The prior installed candidate remains a historical `FAIL` and is not reused as acceptance evidence.
- Fresh App-only runtime candidate prepared from control HEAD `a7e4a3c336938b84b6e8e555625916b0ba01ac91` on 2026-10-31. The package and installed app executable SHA-256 are both `9bf5faa5706a26699b614714573300c4944cfb8dd6770454aea8d1c4e52bc535`.
- Installed/running identity: `/Applications/RemoteOrbit.app`, Bundle ID `com.lost0rz.RemoteOrbit`, version `0.2.14`, build `43`, architectures `x86_64 arm64`, source-head provenance `a7e4a3c336938b84b6e8e555625916b0ba01ac91`, PID `95613`, executable path `/Applications/RemoteOrbit.app/Contents/MacOS/RemoteOrbit`.
- App-only package command `./remote-orbit/package-app.sh` and install command `./remote-orbit/install-app.sh` completed. Package signing verification and installed-app signing verification both passed. The package script reported that the driver was not built; no driver was included or replaced.
- Startup evidence in `/Users/ox_miles/Library/Logs/RemoteOrbit/RemoteOrbit.log` at `2026-10-31 01:38:23 +0000`: BLE ready; RemoteOrbit Mic IOProc started at 48 kHz stereo and restored as system default input; AX trusted/input/accessibility true; HID suppressor ready; RC003 connected/monitored. Fresh diagnostic evidence is in `/Users/ox_miles/Library/Logs/RemoteOrbit/voice-diagnostic-current.jsonl` with `RUN_START` PID `95613` and `HID_VERIFY result=MATCH`.
- Installed driver before/after evidence is unchanged: bundle file-set SHA-256 `6ace3ac1edbf27a8257d32ca5a50d741bd8f69188a43789a95e7d465c894a93d`; executable SHA-256 `d2c72d9e433e2f6ccdec50eb8298e3e36ddbbb0d0f72e13b728c17f6a48c5446`. No TCC mutation command was executed.
- Evidence/design authorities remain:
  - `docs/incidents/2026-10-30-042-host-mic-open-rapid-repress.md`
  - `docs/incidents/2026-10-31-042-rc003-runtime-owner-race.md`

## Independent source audit result

Corrective A remains source-level accepted and unchanged. The `noOptionEdge` pending-owner model still requires B mapped DOWN capture plus A terminal completion before promotion; no `main.swift` change exists in the latest corrective.

Corrective B now closes the previously blocking callback-ordering defect:

- product-source change is exactly one semantic condition in `BLEBridge.supersedeReleasedHostMicOpenGraceIfNeeded`: ordinary `notifyStreaming(false)` is emitted only when `oldSessionWasStreaming && !allowActiveDrain`;
- released HOST_MIC_OPEN active-drain replacement therefore uses the existing `onPhysicalTransportSuperseded` coordinator terminal boundary instead of first enqueueing an ordinary old-A `streaming=false` teardown;
- B is installed as `.preHIDPhysical` before the supersession callback reaches the main queue;
- the cross-component regression uses real `BLEBridge -> main queue -> VoicePressCoordinator -> AudioPipe` callbacks and proves B candidate/prebuffer remains `4 -> 4` through A terminal/output retirement;
- A still completes its terminal/output lifecycle;
- stale A grace/drain callbacks do not mutate B and MIC_CLOSE remains `0`;
- B remains adoptable as `voiceSession` and consumes the preserved prebuffer normally.

Source scope is bounded from `9907005054ff795df947b743dae15e6d9ad08671` through the implementation/control handoff to `BLEBridge.swift`, `BLEBridgeTests.swift`, `CURRENT_STATUS.md`, and `CURRENT_TASK.md`. The implementation commit itself changes only `BLEBridge.swift` and `BLEBridgeTests.swift`.

Reported implementation verification remains: focused suites 118/118 total across the listed Task 042 suites, full Swift 610/610, arm64 Release PASS, x86_64 Release PASS, ATVV self-tests 3/3, and `git diff --check` PASS. These execution results are implementation-context evidence; the independent Web verdict here is a source-level `CODE_DIFF` PASS.

## Preserved boundaries

- Normal 350 ms no-replacement tail unchanged.
- Generic 180 ms debounce unchanged.
- No Doubao post-processing delay/re-arm workaround.
- Candidate PCM isolation, transport epoch/generation protection, READY / strict READY, Gate C ring, Gate D 45 ms reserve, ATVV codec/framing unchanged.
- Driver/CoreAudio/TCC unchanged.
- No merge/tag/release/Gate F before fresh human RC003 acceptance.

## Runtime preparation receipt

- Product-source equivalence: `git diff --name-only b4904f2faf26535fd39ba97d3a5dd30440de13b9..a7e4a3c336938b84b6e8e555625916b0ba01ac91` is exactly `CURRENT_STATUS.md` and `CURRENT_TASK.md`; no product-source drift.
- Package artifact: `/Volumes/Jack-Dev/Projects/remoteorbit-voice-pipeline-simplification-042/remote-orbit/dist/RemoteOrbit.app`.
- Installed provenance: package and `/Applications/RemoteOrbit.app` executable hashes compare equal; Bundle ID/version/build/architectures/signature/source-head also compare equal.
- Runtime logs: `/Users/ox_miles/Library/Logs/RemoteOrbit/RemoteOrbit.log` and `/Users/ox_miles/Library/Logs/RemoteOrbit/voice-diagnostic-current.jsonl`. The existing `diagnostic-events-v1.jsonl` journal remains present but was not treated as fresh app-start evidence.
- Driver/CoreAudio/TCC boundary: driver file-set and executable hashes are unchanged; no driver install/reload, CoreAudio restart, or TCC reset was performed.

## Next

Stop for the user-owned RC003 hardware/runtime acceptance. Do not claim human acceptance, merge, tag, release, or create Gate F.

Human RC003 acceptance remains user-owned. Required retest includes normal holds, rapid re-press, extreme chained re-press, waveform-without-audio, stuck waveform, missing first speech, and old-session/new-session ownership crossover. If failure occurs, preserve the fresh app and logs before restart/reinstall.
