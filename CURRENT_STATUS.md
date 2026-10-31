# CURRENT_STATUS

Last updated: 2026-10-31
State: `RO-VOICE-PIPELINE-SIMPLIFICATION-042 — READY_FOR_HUMAN_RUNTIME_ACCEPTANCE`
Repository: `Lost0rz/RemoteOrbit`
Active branch: `codex/voice-pipeline-simplification-042`

## Current authority

- Source candidate under acceptance: `ef606a3f712304cf43da2e9fb849a87a0bb02a1b`.
- Independent Web `CODE_DIFF` audit of the final A-terminal/B-candidate corrective: `PASS`.
- Previous Web audit STOP at `f1b0f700fe618d744afdb0a3350b33cc87880d53` was reconciled by control commit `492b8a41b3e5655e8b960f94554920b58e6c56b4` and source corrective `ef606a3f712304cf43da2e9fb849a87a0bb02a1b`.
- Evidence/design authority: `docs/incidents/2026-10-30-042-host-mic-open-rapid-repress.md`.
- `AGENTS.md` remains durable repository authority; `CURRENT_TASK.md` is the sole active execution authorization.

## Accepted source model

The RC003 corrective now has independent source-audit acceptance for the complete rapid re-press ownership lifecycle:

- a distinct physical reason `0x03` / new stream ID can supersede an old physical `AUDIO_STOP` BLE ingress drain without shortening the normal 350 ms tail window;
- stale A drain callbacks cannot retire or mutate B;
- B pre-HID PCM is isolated from A's active route and its candidate/prebuffer survives A teardown;
- A receives an explicit physical-transport-supersession terminal boundary, then completes its existing output-drain and hardware trigger-UP/replay-ACK lifecycle;
- B remains serialized behind A and promotes only after A's terminal ownership retires;
- BLE-owned live candidate truth gates rapid admission/debounce; the generic 180 ms debounce remains unchanged otherwise;
- prior HOST_MIC_OPEN/MIC_CLOSE safety, READY semantics, Gate C ring, Gate D 45 ms reserve, ATVV codec/framing and driver/TCC behavior remain preserved.

Source verification reported by the implementation context: focused `96/96`, full Swift `604/604`, arm64/x86_64 Release PASS, ATVV self-tests `3/3`, `git diff --check` PASS. GitHub has no independent CI status attached to this commit; the accepted verdict is `CODE_DIFF`, not `CI`.

## Runtime state

The previously installed `0.2.14 (43)` candidate predates the final corrective and previously FAILED human RC003 extreme rapid-repress acceptance. Its result is not reused for `ef606a3f...`.

Runtime-preparation receipt (FACT, 2026-10-31): preparation started from local/remote control HEAD `82b6cd3a65c9835b38a4cf8be5c6eaef8008e7fe`; the range from accepted source `ef606a3f712304cf43da2e9fb849a87a0bb02a1b` to that preparation HEAD contained only `CURRENT_STATUS.md` and `CURRENT_TASK.md`. `./remote-orbit/package-app.sh` completed arm64 and x86_64 Release builds and produced `/Volumes/Jack-Dev/Projects/remoteorbit-voice-pipeline-simplification-042/remote-orbit/dist/RemoteOrbit.app`; the Universal2 executable SHA-256 is `2799d6a4b2b13a08f4304e00b75962c2dfaf95fd6d25e65894ae7e7ad30ee935`, with valid designated-requirement code signing. `./remote-orbit/install-app.sh` replaced only `/Applications/RemoteOrbit.app`; installed provenance matches the package by executable SHA, Bundle ID `com.lost0rz.RemoteOrbit`, version `0.2.14`, build `43`, architectures `x86_64 arm64`, and diagnostic source head `82b6cd3a65c9835b38a4cf8be5c6eaef8008e7fe`. The old app was quit before replacement; the fresh app is running at PID `31333` from `/Applications/RemoteOrbit.app/Contents/MacOS/RemoteOrbit`. Startup log `/Users/ox_miles/Library/Logs/RemoteOrbit/RemoteOrbit.log` records BLE ready, RemoteOrbit Mic 2ch IOProc start at 48000 Hz stereo/default input, HID permissions ready, RC003 waiting/connected monitored. The installed driver executable SHA-256 remained `d2c72d9e433e2f6ccdec50eb8298e3e36ddbbb0d0f72e13b728c17f6a48c5446` before and after; no driver mutation or TCC reset was performed. This factual correction is the direct successor control receipt and will be pushed/verified as the final control delivery.

Human acceptance remains user-owned. Required retest focus:

- normal press/release baseline;
- repeated rapid release/re-press;
- extreme chained press/release/re-press;
- no waveform remaining abnormally active after release;
- no waveform/input activation with missing speech transcription;
- no stuck session, missing first speech, or obvious ownership crossover.

If any failure occurs, preserve the fresh RemoteOrbit runtime and diagnostic logs before restart/reinstall and return them for incident analysis.

## Next

User performs the human RC003 hardware acceptance run against the fresh PID `31333` candidate. Preserve the fresh app and logs if any failure occurs. Do not merge, tag, release, reinstall the driver, reset TCC, or claim human acceptance.
