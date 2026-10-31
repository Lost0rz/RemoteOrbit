# RemoteOrbit Current Task

## RO-IME-READINESS-PROMPT-SYNC-043 — Final Merge / Runtime / DMG Closeout

Status: `READY_FOR_HUMAN_RUNTIME_UI_ACCEPTANCE`

Repository: `Lost0rz/RemoteOrbit`
Active branch: `main`
Merged main baseline: `8b76ee336d36e9dd58d072bd5ab1dae208b3a77f`
Accepted Task 043 source head: `b7b676fa23c17ff51b51dc9f4d42ecc3157829ab`
Design authority: `docs/design/2026-10-31-043-ime-readiness-prompt-sync.md`

## Objective

Close the current accepted development stage without reopening voice behavior: audit the owner's local icon replacement, merge the accepted Task 043 stage into `main`, then produce and install the exact merged-main App candidate and create a verified DMG for owner testing.

## Owner-accepted runtime limitation

No further corrective is requested for the following edge case: while the previous external IME session is still processing/cleaning up, an immediate rapid/double press may still show RemoteOrbit's physical-press/HUD indication even though Doubao does not reopen. A later press works after IME cleanup. This is accepted for the current stage and must not trigger a new cooldown/retry/state-machine change.

## Icon audit authority

The owner reports a local application-icon replacement that may not yet be committed/pushed. Before merge:

- inspect the exact local diff and identify the durable source of the icon;
- generated `dist/RemoteOrbit.icns` alone is not sufficient because `remote-orbit/package-app.sh` regenerates the icon through `Packaging/generate-icon.sh` on every build;
- ensure the intended icon is represented in source-controlled packaging input/generator logic and that `Packaging/Info.plist` still resolves `RemoteOrbit.icns` correctly;
- allow only the minimum icon-related packaging correction needed to make the intended icon reproducible;
- reject/stop on unrelated local source changes rather than silently including them.

Human visual approval of the icon remains owner-owned.

## Reconciled icon and premerge evidence

The reconciled 043 worktree was clean at control head
`9e25c2538aadd64393007cd0f170a479c695b169`; no owner-provided dirty icon path or
generated `dist/RemoteOrbit.icns` was present locally. The durable source used for
this closeout is the verified Task 044 remote vector mark at
`remote-orbit/Brand/RemoteOrbitMark.svg`, SHA-256
`5af502da5e9a0ccfa299a1faf09288cd98279bb9cc3dee15b4aa517aaf2a0360`. Packaging
now consumes this source on every `generate-icon.sh` invocation, so the generated
ICNS is not a dist-only artifact. Settings/About uses
`NSApp.applicationIconImage`; all status-icon calls retain their existing state
selection but render the same Template Mark.

The isolated generator produced a valid ICNS with all 10 standard sizes and was
byte-identical across two runs (SHA-256
`0955a856d62d1a30b6226ab004a230d7b22f9240093bffb2cbd50be4778e7645`). Focused
tests passed: VoiceReceiverReadiness 13, VoicePressCoordinator 39,
VoicePipelineSimplification 34, AudioPipe 12, and BLEBridge 51. Full Swift tests
passed with 623 tests and 0 failures. Both `arm64-apple-macosx13.0` and
`x86_64-apple-macosx13.0` Release builds passed, protocol self-tests passed, and
`git diff --check` passed. No protected voice/BLE/AudioPipe/ATVV/HID/IME/receiver/
HUD implementation path changed.

## Merge/package/runtime closeout evidence

The accepted 043 branch fast-forwarded into `main` at
`8b76ee336d36e9dd58d072bd5ab1dae208b3a77f`; the stale release branch was not
merged. The existing driver build flow produced the bundled Universal2
`RemoteOrbitAudio.driver` only. No system driver install/unload/reload and no TCC
mutation occurred.

From exact merged-main source, `./remote-orbit/package-app.sh` produced
`remote-orbit/dist/RemoteOrbit.app` with bundle
`com.lost0rz.RemoteOrbit`, version `0.2.15`, build `44`, Universal2
`x86_64 arm64`, source stamp `8b76ee336d36e9dd58d072bd5ab1dae208b3a77f`,
executable SHA-256
`59de94acd12aa3fa491fd9ffeefce94c16991f8d746a9491bb99225e3a86b908`, icon
SHA-256 `0955a856d62d1a30b6226ab004a230d7b22f9240093bffb2cbd50be4778e7645`,
and successful deep strict codesign verification. `./remote-orbit/install-app.sh`
replaced only `/Applications/RemoteOrbit.app`; installed executable and icon
hashes matched the packaged copies.

The installed candidate launched with PID `84580` at
`/Applications/RemoteOrbit.app/Contents/MacOS/RemoteOrbit`. Startup-only evidence
reports BLE ready, RC003 connected (`0x2717/0x32B8`), HID input/accessibility
permissions and event suppressor ready, `RemoteOrbit Mic 2ch` IOProc started and
restored as the default USB input, and log/journal writers active. The installed
diagnostic CLI `status` and `verify` commands succeeded. These are not human
runtime or UI acceptance.

A one-off DMG was created and verified at
`/Users/ox_miles/Desktop/RemoteOrbit-0.2.15.dmg`, SHA-256
`43d276994a44e48a31c0d6d1adfcf9133b82b0c94e69c1934fe7b3d5adbbd890`. Read-only
mount verification proved the embedded App executable matched the packaged App
byte-for-byte, with the same bundle/version/build/source stamp, Universal2
architectures, and deep strict codesign result.

## Merge authority

After the icon audit and required verification pass, merge this same Task 043 branch into the live `main`. Preserve exact accepted history where practical. Re-read live `main` before merge; if it has advanced incompatibly, stop and reconcile instead of force-updating.

Task 043 product behavior already accepted by Web audit must not be redesigned during closeout.

## Release-candidate identity

Carry forward the existing repository release authorization for:

- marketing version `0.2.15`;
- build `44`;
- Universal2 `arm64 + x86_64`;
- bundle `com.lost0rz.RemoteOrbit`.

The historical branch `codex/release-v0.2.15` is stale/diverged from current main and MUST NOT be merged or cherry-picked wholesale. If current merged main still reports `0.2.14 (43)`, reapply only the release metadata needed for `0.2.15 (44)` on the current closeout line, preserving newer code/scripts. A current `RELEASE_NOTES_v0.2.15.md` may be created/updated if needed for artifact identity, but do not import stale product code.

## Build / install authority

Build from the exact merged `main` checkout using the established `remote-orbit/package-app.sh`; it is the canonical Universal2 App packaging path and regenerates `RemoteOrbit.icns`.

If that packaging flow expects the bundled HAL driver, rebuild the unchanged driver artifact from current merged source with the existing driver build script before App packaging. Do not reinstall/reload the system driver and do not mutate TCC/CoreAudio configuration.

Install using the established `remote-orbit/install-app.sh` to `/Applications/RemoteOrbit.app`, then launch the installed App. Verify source provenance, executable hash, bundle/version/build, architectures, codesign, path/PID, BLE/HID/accessibility readiness, virtual microphone/default input, and log writer. These startup checks are not human UI acceptance.

## DMG authority

Create a local DMG from the exact packaged App after main merge and App verification. If no current canonical `package-dmg.sh` exists, do not add a repository script solely for this closeout: use a one-off staging directory plus macOS `hdiutil` to create `RemoteOrbit-0.2.15.dmg`, preferably containing `RemoteOrbit.app` and an `/Applications` symlink.

Mount the produced DMG read-only and verify the contained App's executable SHA, version/build, bundle ID, architectures, and codesign match the intended packaged candidate before unmounting. Record DMG SHA-256 and final path.

## Required verification

Before merge: icon-diff audit, focused Task 043 tests, Task 042 regression suites, full Swift tests, both Release architectures, protocol self-tests, and `git diff --check`.

After merge/build: verify exact merged-main source stamp in the App, package-vs-installed executable SHA equality, version/build `0.2.15 (44)`, Universal2 architecture, codesign, icon resource presence/hash, and DMG-contained App identity.

## Boundaries

Do not add any new voice/HUD/receiver behavior, cooldown, retry/replay, trigger delay, admission gating, BLEBridge/AudioPipe/ATVV change, HID timing change, driver-source change, TCC reset, CoreAudio restart, tag, or GitHub Release publication.

No force-push to `main`. Do not delete unique local work. Do not merge the stale release branch.

## Completion

Push this control receipt to `main`, verify exact local/remote equality, then stop
at `READY_FOR_HUMAN_RUNTIME_UI_ACCEPTANCE`. Do not claim human acceptance from
build/startup checks or the DMG.
