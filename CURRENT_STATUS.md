# CURRENT_STATUS

Last updated: 2026-10-09
State: TASK 035 ACTIVE / RUNTIME BASELINE RELEASE AUDIT AND PREPARATION
Repository: `Lost0rz/RemoteOrbit`

## Authoritative baseline before Task 035
- Web-verified remote `main`: `8e4bc7a06f2025d5b0abdfca82f68002df95ef7a`.
- Task 034 is closed and accepted.
- Remaining registered worktrees after Task 034: 9.
- Remaining local branches: 24.
- Remaining live remote `codex/*` branches: 25.
- The protected dirty/local-unique/forensic/UNKNOWN worktrees recorded by Task 034 remain protected and are out of scope for Task 035.

## Release intent
The user has frozen further product development for now and requested that the currently installed/running RemoteOrbit behavior be verified and promoted to a formal baseline release.

The current public release is `v0.2.13` / Build 42. Web verified that `v0.2.14` does not currently exist. Task 035 targets `v0.2.14` / Build 43 only if the installed runtime identity and source-equivalence gates pass.

Task 035 must not change accepted voice behavior. Release preparation is limited to release metadata, release notes, build/package validation, and a release-candidate branch/PR.

## Deferred known issue — preserve, do not fix in this release
Codex short-press mode intentionally enables the Mac/local-or-external microphone path for the short voice action. A classified remote long hold takes exclusive control of `RemoteOrbit Mic 2ch` and stops the local capture while remote audio is active. The product intent is to return to the preferred local/external microphone after the remote hold ends, but local microphone capture resumption after that handoff has not yet been independently accepted as a stable runtime contract.

Classification for Task 035: `KNOWN_DEFERRED / NOT A RELEASE BLOCKER FOR THE CURRENT ACCEPTED BASELINE / DO NOT MODIFY`.

A future single-click/Codex task may verify or correct that handoff. Task 035 must record this in release notes and must not alter the relevant audio or gesture code.

## Task 035 release gate
Before any release metadata change:
1. verify canonical repository identity and cleanliness;
2. verify installed `/Applications/RemoteOrbit.app` identity;
3. verify the running process identity if RemoteOrbit is running;
4. record bundle version/build, Bundle ID, `RemoteOrbitDiagnosticSourceHead`, executable SHA-256, architecture and code-signature identity;
5. prove that the installed runtime source HEAD is product-equivalent to the current accepted `main` product tree, allowing only later control/documentation-only commits;
6. if identity or product equivalence cannot be proven, STOP before release preparation.

If the gate passes, Task 035 may create exactly one release-candidate worktree/branch `codex/release-v0.2.14-baseline`, change only the version/build metadata and `RELEASE_NOTES_v0.2.14.md`, run the required validation/package build, and open a release PR. It must stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT` before merge, tag creation, GitHub Release publication, or replacement of the installed runtime.

No product source behavior change, driver installation/replacement, CoreAudio restart, TCC change, runtime replacement, hardware gesture testing, lifecycle cleanup, or protected-worktree mutation is authorized by Task 035.
