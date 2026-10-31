# RemoteOrbit Current Task

## RO-VOICE-PIPELINE-SIMPLIFICATION-042 — Final RC003 Runtime Acceptance

Status: `READY_FOR_HUMAN_RUNTIME_ACCEPTANCE`

Repository: `Lost0rz/RemoteOrbit`
Active branch: `codex/voice-pipeline-simplification-042`
Audited corrective A source: `3d7b55cc557e52e994ff5c5a6b4c2217189f2751`
Audited corrective B source: `b4904f2faf26535fd39ba97d3a5dd30440de13b9`
Pre-audit control handoff: `34f4b5892307355948660b9de7d2e2008119e036`
Evidence/design authorities:
- `docs/incidents/2026-10-30-042-host-mic-open-rapid-repress.md`
- `docs/incidents/2026-10-31-042-rc003-runtime-owner-race.md`

## Objective

Prepare and install one fresh App-only candidate containing the independently audited Task 042 source, then stop for user-owned RC003 hardware/runtime acceptance.

No further product-source corrective is authorized in this step.

## Independent Web source audit

Profile: `CODE_DIFF`
Verdict: `PASS`

Required claims are satisfied at source level:

1. Corrective A remains unchanged: production `noOptionEdge` B pending-owner creation/capture/promotion semantics are preserved and no latest `main.swift` diff exists.
2. Corrective B suppresses ordinary old-A `notifyStreaming(false)` only for the already-authorized released HOST_MIC_OPEN active-drain replacement path.
3. Active-drain replacement uses the existing `onPhysicalTransportSuperseded` terminal boundary; B is live `.preHIDPhysical` before that main-queue callback executes.
4. The production-shaped asynchronous regression proves B candidate/prebuffer survives A terminal/output teardown (`4 -> 4`), A completes normally, stale A grace/drain cannot mutate B, MIC_CLOSE remains zero, and B later adopts as `voiceSession` while consuming the prebuffer.
5. The supersession predicate remains narrow; normal 350 ms tail and generic 180 ms debounce are unchanged.

Implementation-context verification reported: focused Task 042 suites green, full Swift 610/610, arm64/x86_64 Release builds PASS, ATVV protocol self-tests 3/3, `git diff --check` PASS.

## Authorized runtime preparation

1. Fetch/reconcile the existing Task 042 branch.
2. Verify product source corresponds to audited source `b4904f2faf26535fd39ba97d3a5dd30440de13b9` plus control-only descendants. If any product-source drift exists after `b4904f2...`, STOP.
3. Build/package with the existing App-only packaging process.
4. Replace `/Applications/RemoteOrbit.app` using the existing install process.
5. Launch the fresh app.
6. Verify and record:
   - package/installed executable SHA-256 equality;
   - Bundle ID;
   - version/build;
   - architectures;
   - installed app path;
   - running PID/path;
   - source/control provenance;
   - BLE ready;
   - HID input/accessibility/RC003 monitored state;
   - RemoteOrbit Mic startup/default-input state;
   - runtime log path(s).
7. Driver must remain unchanged; do not reinstall/reload it. Record before/after driver hash if the existing runtime-preparation process already does so.
8. Do not reset TCC.
9. Update only the control receipt as necessary to `READY_FOR_HUMAN_RUNTIME_ACCEPTANCE`, push and verify remote delivery.
10. STOP for the user to perform hardware acceptance.

## Observed runtime preparation receipt

- Reconciled start control HEAD: `a7e4a3c336938b84b6e8e555625916b0ba01ac91`; product-source equivalence against audited source `b4904f2faf26535fd39ba97d3a5dd30440de13b9` is clean, with only `CURRENT_STATUS.md` and `CURRENT_TASK.md` in the range.
- Build/package: `./remote-orbit/package-app.sh` completed and produced `/Volumes/Jack-Dev/Projects/remoteorbit-voice-pipeline-simplification-042/remote-orbit/dist/RemoteOrbit.app`; the script reported no driver build and produced an App-only candidate.
- Install: `./remote-orbit/install-app.sh` completed to `/Applications/RemoteOrbit.app`; package and installed executable SHA-256 both equal `9bf5faa5706a26699b614714573300c4944cfb8dd6770454aea8d1c4e52bc535`.
- App identity: Bundle ID `com.lost0rz.RemoteOrbit`, version `0.2.14`, build `43`, architectures `x86_64 arm64`, source-head provenance `a7e4a3c336938b84b6e8e555625916b0ba01ac91`; code-sign verification passed for package and installed app.
- Running identity: PID `95613`; executable `/Applications/RemoteOrbit.app/Contents/MacOS/RemoteOrbit`.
- Fresh startup evidence: `/Users/ox_miles/Library/Logs/RemoteOrbit/RemoteOrbit.log` records BLE ready, RemoteOrbit Mic IOProc start/default-input restore, AX/input/accessibility readiness, HID suppressor readiness, and RC003 connected/monitored. `/Users/ox_miles/Library/Logs/RemoteOrbit/voice-diagnostic-current.jsonl` records PID `95613` `RUN_START` and `HID_VERIFY result=MATCH`.
- Driver freeze: before/after installed driver file-set SHA-256 `6ace3ac1edbf27a8257d32ca5a50d741bd8f69188a43789a95e7d465c894a93d`; executable SHA-256 `d2c72d9e433e2f6ccdec50eb8298e3e36ddbbb0d0f72e13b728c17f6a48c5446`. No driver/CoreAudio/TCC mutation was performed.

## Human RC003 acceptance focus

The user owns PASS/FAIL.

Exercise:

- normal press/speak/release baseline;
- natural rapid re-press;
- extreme chained press/release/re-press;
- no waveform-without-RemoteOrbit-audio;
- no stuck waveform after release;
- no missing first speech attributable to RemoteOrbit;
- no old-A teardown affecting new-B candidate/session;
- no `pending_hardware_repress_owner_missing`, lost candidate/prebuffer, stale drain retirement, or equivalent ownership crossover in fresh logs.

The user's separate observation that Doubao may be unavailable while its own text post-processing is still running remains unclassified. Do not add a Doubao cooldown in this task. If a failure occurs, preserve the current app and complete fresh logs before restart/reinstall so RemoteOrbit route/render evidence can be separated from IME readiness.

## Boundary

- No product-source mutation during runtime preparation.
- No new probe/instrumentation work.
- No Doubao delay/re-arm timer.
- No 350 ms drain change.
- No generic 180 ms debounce change.
- No driver/CoreAudio/TCC mutation.
- No merge/tag/release/Gate F before explicit fresh human RC003 acceptance.
- AI must not claim human acceptance.

If packaging/install requires a source change, provenance cannot be established, driver/TCC mutation appears necessary, or the audited source is not what is being built, STOP and return the blocker.

## Required return from runtime preparation

Return:

- governance route / skills / topology / subagents;
- reconciled start identity;
- final local/remote control identity;
- audited product-source equivalence proof;
- exact changed paths;
- packaging/install commands and result;
- package and installed executable SHA-256;
- bundle/version/build/architectures;
- app path and running PID/path;
- BLE/HID/audio startup evidence;
- runtime log paths;
- driver/TCC unchanged confirmation;
- remote-delivery verification;
- worktree cleanliness;
- blockers, if any;
- final state actually reached.

If successful, stop at `READY_FOR_HUMAN_RUNTIME_ACCEPTANCE`. Do not perform the user hardware test, merge, tag, release, or Gate F.
