# CURRENT_STATUS

Last updated: 2026-10-30
State: `RO-VOICE-PIPELINE-SIMPLIFICATION-042 — CORRECTIVE_CANDIDATE_PREPARED / READY_FOR_HUMAN_CORRECTIVE_RUNTIME_RETEST`
Repository: `Lost0rz/RemoteOrbit`

## Current authority

- Active branch: `codex/voice-pipeline-simplification-042`.
- Accepted corrective source: `b1736f2feedd7ed13e4520ecdfaa0c6bf6e9b332` — independent CODE_DIFF audit PASS.
- Installed candidate: `0.2.14 (43)`, packaged from the accepted product source with control-only drift at `5a14d381267d108724af2acb334ef1e366a72df9`.
- Incident record: `docs/incidents/2026-10-30-042-adopted-physical-grace-intent-race.md`.
- Frozen 041 observability baseline: `ac3132986197bfee4440bb8f388e3d2e5f478f03`.
- `AGENTS.md` remains durable repository authority.
- `CURRENT_TASK.md` is the sole active execution authorization.

## Independent Web audit result

The second bounded corrective is source-accepted.

Verified properties:

- adopted physical retirement state is created only after `preHIDPhysical -> voiceSession` adoption;
- no global UNKNOWN reclassification was introduced;
- retirement requires matching session ownership, physical release, healthy AUDIO_STOP drain completion, matching waiting grace, `micOpenRequested == false`, and stale `voiceInputRequested == true`;
- AUDIO_STOP before physical release records drain completion but does not retire intent until the later physical release transition;
- host-MIC_OPEN grace/MIC_CLOSE remains on the existing path;
- stale post-release callbacks remain generation/session guarded;
- Gate B READY, strict READY, Gate C ring, Gate D 45 ms reserve, ATVV codec/protocol, driver/TCC and trigger/tail/output-drain semantics are unchanged.

No source blocker was found in `74611c813887c9ccb489554cb452b390fb5bbff1..b1736f2feedd7ed13e4520ecdfaa0c6bf6e9b332`.

## Runtime boundary

Source audit PASS does not prove the high-frequency hardware failure is fixed. The accepted corrective must now be packaged and installed with exact provenance, then retested on RC003 under the same rapid open/close pattern.

Do not merge, tag, release or create Gate F before that human runtime retest.

## Corrective candidate preparation evidence

The live branch was reconciled to control HEAD
`5a14d381267d108724af2acb334ef1e366a72df9`. The range from accepted source
`b1736f2feedd7ed13e4520ecdfaa0c6bf6e9b332` contains only `CURRENT_STATUS.md`
and `CURRENT_TASK.md`; product source, tests, package scripts, driver code,
and version/signing behavior are unchanged.

Observed packaging used the established command
`./package-dmg.sh --reuse-driver`. Release builds completed for arm64 and
x86_64, and the resulting App is Universal2 (`x86_64 arm64`). The artifacts
are:

- App: `/private/tmp/remoteorbit-voice-pipeline-simplification-042/remote-orbit/dist/RemoteOrbit.app`
- DMG: `/private/tmp/remoteorbit-voice-pipeline-simplification-042/dist/RemoteOrbit-0.2.14.dmg`
- DMG SHA-256: `2e906bef34d7caf4c6a2d0e886f5d9be95929a73a2f3236b672114731e420ef8`
- App executable SHA-256: `ea55c09a7b5a936ef5bd0d0e0fc9ef30713747ef4e5e0ef79d527497a5b69910`
- Bundle ID/version/build: `com.lost0rz.RemoteOrbit` / `0.2.14` / `43`
- Signing: ad-hoc; deep strict verification and designated requirement passed.

The old candidate PID `8511` was quit cleanly. Only
`/Applications/RemoteOrbit.app` was replaced using the existing app installer.
Installed executable bytes and Bundle metadata match the packaged App exactly.
The installed driver remained unchanged: pre/post executable SHA-256
`d2c72d9e433e2f6ccdec50eb8298e3e36ddbbb0d0f72e13b728c17f6a48c5446`, Bundle
ID `audio.local.RemoteOrbitAudio2chXX`, version `0.7.1`, build `596`.
No driver reload/replacement or TCC reset was performed.

The candidate is running as PID `38260` from
`/Applications/RemoteOrbit.app/Contents/MacOS/RemoteOrbit`. RemoteOrbit Mic is
the default input with two channels and `Transport: USB`; the app log reports
its IOProc started. RC003 is connected over BLE with Vendor ID `0x2717` and
Product ID `0x32B8`; HID reports the same device and the app reports monitored
HID, event suppressor ready, and RC003 connected. The diagnostic CLI reports a
present read-only journal at
`/Users/ox_miles/Library/Logs/RemoteOrbit/diagnostic-events-v1.jsonl`, schema
1, size 58,900 bytes.

Human RC003 corrective runtime retest has not been performed.
