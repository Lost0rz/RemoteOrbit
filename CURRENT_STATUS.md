# CURRENT_STATUS

Last updated: 2026-10-31
State: `RO-IME-READINESS-PROMPT-SYNC-043 — READY_FOR_HUMAN_RUNTIME_UI_ACCEPTANCE`
Repository: `Lost0rz/RemoteOrbit`
Active branch: `main`
Merged main baseline: `8b76ee336d36e9dd58d072bd5ab1dae208b3a77f`
Accepted Task 043 source head: `b7b676fa23c17ff51b51dc9f4d42ecc3157829ab`

## Accepted implementation state

Task 043 receiver-readiness/HUD work passed independent Web CODE_DIFF audit with only a non-blocking false-negative follow-up. Task 042 remains CLOSED and frozen.

The owner explicitly accepts the remaining rapid-double-press boundary: if the previous IME session is still post-processing/cleaning up, a new physical press may still produce the RemoteOrbit press/HUD indication while Doubao does not reopen. No further optimization is requested for this behavior because truthful physical-button feedback and perfect IME-state synchronization conflict at this boundary.

## Final-stage verification

The reconciled Task 043 worktree was clean after fast-forwarding to control head
`9e25c2538aadd64393007cd0f170a479c695b169`; no owner-provided dirty icon file or
generated `dist/RemoteOrbit.icns` was present locally. The durable, source-controlled
icon input now observed on the Task 044 remote is
`remote-orbit/Brand/RemoteOrbitMark.svg` (SHA-256
`5af502da5e9a0ccfa299a1faf09288cd98279bb9cc3dee15b4aa517aaf2a0360`). The 043
closeout line uses that exact vector source for reproducible ICNS generation, the
Settings/About title bar reads `NSApp.applicationIconImage`, and the menu-bar
renderer is a single Template Mark.

Premerge evidence on the 043 worktree: canonical icon generation succeeded and
repeated generation was byte-identical (ICNS SHA-256
`0955a856d62d1a30b6226ab004a230d7b22f9240093bffb2cbd50be4778e7645`); 10 standard
ICNS sizes were verified by `iconutil`; focused readiness/Task 042 suites passed
(`13 + 39 + 34 + 12 + 51` tests); full Swift tests passed (`623`, `0` failures);
arm64 and x86_64 macOS 13 Release builds passed; protocol self-tests passed; and
`git diff --check` passed. The protected voice, BLE, AudioPipe, ATVV, HID, IME,
receiver-readiness, and HUD implementation files have no diff.

## Merge/package/runtime closeout evidence

The accepted 043 branch fast-forwarded into `main` at
`8b76ee336d36e9dd58d072bd5ab1dae208b3a77f`; no stale release branch was merged.
The unchanged driver build flow produced an embedded Universal2
`RemoteOrbitAudio.driver`, but the system driver was not installed, unloaded, or
reloaded. The canonical `./remote-orbit/package-app.sh` then built
`remote-orbit/dist/RemoteOrbit.app` from that exact source head.

Packaged App evidence: bundle `com.lost0rz.RemoteOrbit`, version `0.2.15`, build
`44`, architectures `x86_64 arm64`, source stamp
`8b76ee336d36e9dd58d072bd5ab1dae208b3a77f`, executable SHA-256
`59de94acd12aa3fa491fd9ffeefce94c16991f8d746a9491bb99225e3a86b908`, icon
SHA-256 `0955a856d62d1a30b6226ab004a230d7b22f9240093bffb2cbd50be4778e7645`, and
deep strict codesign verification passed. The App was installed with
`./remote-orbit/install-app.sh` at `/Applications/RemoteOrbit.app`; installed
executable and icon hashes exactly matched the packaged copies.

The installed App launched at PID `84580` with executable path
`/Applications/RemoteOrbit.app/Contents/MacOS/RemoteOrbit`. Startup logs report
BLE ready, RC003 connected (`VID 0x2717`, `PID 0x32B8`), HID input/accessibility
permissions and suppressor ready, `RemoteOrbit Mic 2ch` IOProc started and
restored as default USB input, and active log/journal writers. Read-only
diagnostic CLI `status` and `verify` succeeded. TCC and installed system driver
were not mutated; human hardware/runtime/UI acceptance remains pending.

DMG evidence: one-off staging produced
`/Users/ox_miles/Desktop/RemoteOrbit-0.2.15.dmg`, SHA-256
`43d276994a44e48a31c0d6d1adfcf9133b82b0c94e69c1934fe7b3d5adbbd890`. Its
read-only mounted App matched the packaged executable byte-for-byte, retained
the same bundle/version/build/source stamp and Universal2 architectures, and
passed deep strict codesign verification before detach.

## Current owner request

The owner has locally replaced the application icon and authorizes the final stage closeout:

1. audit the local icon change and ensure it is durable in the reproducible packaging path rather than only in `dist` or another generated artifact;
2. if needed, make only the smallest icon-packaging correction needed for the intended icon to survive `package-app.sh`;
3. preserve all accepted Task 042/043 product semantics;
4. verify the branch and merge the accepted stage into `main`;
5. carry forward the previously authorized release candidate identity `0.2.15 (44)` without merging the stale `codex/release-v0.2.15` branch wholesale;
6. build/package a Universal2 App from the exact merged `main`, install it at `/Applications/RemoteOrbit.app`, and launch it for owner testing;
7. create a local `RemoteOrbit-0.2.15.dmg`, verify its contents/provenance, and return the local artifact path plus hashes.

Historical `codex/release-v0.2.15` is stale/diverged and is reference-only. Do not merge/cherry-pick it wholesale.

## Boundaries

No further voice/HUD/receiver corrective is authorized unless a build/merge regression is proven. Do not change BLEBridge, AudioPipe, ATVV, HID ownership/timing, cooldown/retry behavior, driver source, TCC, or installed CoreAudio state. Building the unchanged driver artifact for packaging is allowed if the established App packaging flow requires it; reinstall/reload is not.

No tag or GitHub Release publication is authorized by this stage. Human runtime/UI acceptance remains owner-owned and pending after installation.

## Next

Push this control receipt to `main`, verify exact local/remote equality, and stop
for owner human runtime/UI acceptance. Do not claim acceptance from startup
checks, packaging, or the DMG.
