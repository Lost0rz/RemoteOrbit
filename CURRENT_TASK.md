# RemoteOrbit Current Task

## RO-DIAGNOSTICS-LEGACY-RETIREMENT-045 — Human Runtime Acceptance

Status: `READY_FOR_HUMAN_RUNTIME_ACCEPTANCE`
TASK_CLASS: `HUMAN-OWNED RUNTIME / UI ACCEPTANCE`
Repository: `Lost0rz/RemoteOrbit`
Human runtime/UI acceptance: `READY / USER-OWNED / NOT_YET_EXECUTED`

## Machine gate

The final whole-repository machine audit concluded `PASS_WITH_FOLLOWUPS` with no product-code blocker requiring another retirement Domain before human acceptance.

Completed machine evidence includes:

- Task 045A and 045B Domains 1–6: CLOSED;
- Wave D Domains 1–2: CLOSED;
- latest product merge CI run `41282571433`, job `124777309274`: SUCCESS including 504/504 Swift tests, Release and Universal2 packaging;
- control closeout CI run `41282783523`, job `124777921972`: SUCCESS;
- source/caller audit confirms retired Persistent/Dual/generic-short/local-mic/mixed-attribution/P1-A5 authorities are absent from current production ownership.

No Wave D Domain 3 is authorized. Do not create one merely to rename historical symbols or remove compatibility aliases.

## Acceptance authority

For this phase, this file is the acceptance authority. `README.md` / `SETUP_NOTES.md` contain some stale version and historical flow wording and must not override the contract below.

### Candidate identity requirement

Before human testing, record and preserve:

- fresh live `main` SHA;
- built app path;
- `CFBundleIdentifier = com.lost0rz.RemoteOrbit`;
- app version/build from the built Info.plist;
- embedded `RemoteOrbitDiagnosticSourceHead`, which must equal the source HEAD used to build the candidate;
- installed/running process identity after any owner-authorized app installation;
- installed `RemoteOrbitAudio.driver` / `RemoteOrbit Mic 2ch` identity when available.

A version string alone is not sufficient candidate identity.

### Preflight — no implicit system mutation

Human acceptance may proceed only when the existing machine already has a usable `RemoteOrbit Mic 2ch` and the product process has the required Bluetooth, Accessibility and Input Monitoring access.

If the driver/device is missing, the app requires driver repair, CoreAudio restart, TCC reset/change, or another privileged system mutation, STOP and request separate owner authorization. Do not perform those changes merely to make acceptance pass.

### User-visible voice contract

- SHORT: release before the accepted 300 ms hold boundary is an absolute user-visible no-op. It must not trigger Doubao, replay/synthesize the trigger, open a Persistent session, start local microphone capture, or leave a visible/stuck voice state.
- LONG: crossing the 300 ms boundary promotes into the direct RC003 remote-voice lifecycle.
- LONG release: no new remote input after release; queued PCM drains before final trigger release/session close.
- rapid LONG/release/LONG: the second held press is admitted through the bounded handoff without an intermediate stuck trigger or incorrect input restoration.
- no Persistent or Dual Receiver product semantics are accepted.
- no local/external microphone capture fallback is accepted.

## Human acceptance matrix

The owner performs the checks below on the actual installed candidate with the real Xiaomi RC003 and Doubao IME. Automation may collect evidence but may not declare these product behaviors accepted on the owner's behalf.

### A. Identity and readiness

1. Confirm the candidate identity fields above.
2. Confirm the menu/status reports the RC003 connected.
3. Confirm `RemoteOrbit Mic 2ch` exists and the intended input preference is visible.
4. Confirm the product process has required Bluetooth, Accessibility and Input Monitoring access; no macOS microphone permission should be required.

### B. SHORT no-op

Perform at least 10 clean taps clearly below 300 ms.

PASS only if all are true:

- Doubao is not triggered;
- no remote/local microphone session becomes user-visible;
- no stuck modifier/voice HUD/session remains;
- the next normal LONG still works.

### C. Normal LONG reliability

Perform at least 10 normal holds, preferably >= 0.5 s, speaking short distinct phrases.

Check:

- every valid LONG activates Doubao once;
- beginning words are not systematically clipped;
- no obvious middle drop/stall;
- final words are not systematically clipped;
- release closes normally after drain;
- no trigger/modifier remains stuck.

### D. Repeated SHORT prefix then LONG

Repeat at least 5 cycles of `SHORT → SHORT → LONG`.

PASS if both SHORT taps remain no-op and the final LONG activates normally without stale suppression blocking it.

### E. Rapid repress

Repeat at least 5 cycles of `LONG → release → immediate LONG`.

PASS if:

- the second LONG activates;
- there is no intermediate stuck Option/Control/Command state;
- no duplicate Doubao activation occurs;
- the final release closes cleanly.

### F. Input lease restoration

If the owner uses a physical microphone as the saved system input:

1. select that physical input;
2. perform a normal remote LONG;
3. verify RemoteOrbit temporarily routes through `RemoteOrbit Mic 2ch`;
4. verify the saved physical input is restored only after the final remote output drain;
5. repeat with rapid LONG/release/LONG and verify there is no intermediate physical-input restore between the two sessions.

If the saved preference is already `RemoteOrbit Mic 2ch`, verify the sequence is stable/idempotent.

### G. BLE/HID recovery

During a controlled test, disconnect/reconnect or power-cycle the RC003 once if practical.

PASS if the status recovers and a subsequent LONG works without restarting RemoteOrbit. Do not mutate drivers/TCC/CoreAudio to force recovery in this phase.

### H. Natural-use soak

Use the candidate naturally for a representative period with multiple voice sessions and normal mappings.

Observe:

- no unexplained stuck voice/input state;
- no repeated native-key leakage or macOS power prompt from the remote;
- no progressive latency or obvious resource runaway;
- no new recurring failure pattern.

If diagnostics are explicitly enabled by the owner, preserve the resulting log/evidence bundle after the soak.

## Failure handling

Any reproducible failure in B–H is a human-acceptance failure, not permission to patch opportunistically.

On failure:

1. preserve the candidate/runtime identity;
2. record the exact action sequence and approximate timestamps;
3. collect the existing RemoteOrbit log/diagnostic evidence without changing diagnostic architecture;
4. classify the fresh incident;
5. return to Web independent audit before authorizing a corrective.

## Pass gate

`HUMAN_RUNTIME_ACCEPTANCE = PASS` requires the owner to explicitly confirm the actual runtime behavior after performing the matrix above.

Machine CI, screenshots, simulated input, or an agent's assertion cannot substitute for this gate.

After owner PASS, the next permitted transition is final Task 045 closeout/release-readiness reconciliation. That later transition may reconcile stale docs and repository-hygiene items and decide PR #25/#26/#28 lifecycle. It does not automatically authorize tag/release.

## Non-blocking repository follow-ups

- PR #25: historical/diverged v0.2.15 soak candidate — `DO_NOT_MERGE` pending final cleanup decision.
- PR #26: historical/diverged Settings corrective — `DO_NOT_MERGE` pending final cleanup decision.
- PR #28: separate branding/icon task — independent from Task 045 voice acceptance.
- README/SETUP baseline/version and old first-PCM/classifier wording: reconcile before final release/tag.
- unnecessary `try` test warning: optional cleanup, not runtime acceptance scope.

## Authorized side effects now

This transition authorizes **human testing as a project phase**, but does not itself authorize an agent to install/replace the app or mutate system state.

Until the owner separately instructs installation/start of the candidate:

- no app install/replacement;
- no driver install/reload;
- no CoreAudio restart;
- no TCC reset/change;
- no default-device mutation by an agent;
- no PR close/merge cleanup;
- no tag/release.
