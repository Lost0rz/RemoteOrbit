# CURRENT_STATUS

Last updated: 2026-10-09
State: TASK 035 USER RELEASE AUTHORIZED / CONTROLLED MERGE AND PUBLICATION
Repository: `Lost0rz/RemoteOrbit`

## Accepted release baseline
- Installed/running product baseline: `/Applications/RemoteOrbit.app`, `0.2.13` / Build `42`, source stamp `f938b919e288a481f5eacaf9aad9c254dcf0cffe`.
- Installed runtime was proven product-equivalent to the accepted main product tree.
- Release candidate branch: `codex/release-v0.2.14-baseline`.
- Release candidate commit: `6208266122414db3f3caf5852585eb24ed1b1a71`.
- PR #21 passed independent Web audit.
- Candidate changes exactly `RELEASE_NOTES_v0.2.14.md` and `remote-orbit/Packaging/Info.plist`.
- Version/build target: `0.2.14` / `43`.
- Focused tests PASS; full Swift suite 394/394 PASS; self-tests 3/3 PASS.
- Packaged app identity/source stamp/Universal-2/codesign PASS.
- Bundled `RemoteOrbitAudio.driver` present, Universal 2 and codesign PASS.
- Product source changes: NONE. Test source changes: NONE.

## User authorization
The user explicitly confirmed that the release purpose is understood and that v0.2.14 may be normally published. This authorizes the controlled merge of PR #21 and subsequent creation of tag `v0.2.14` and GitHub Release using the already-audited release notes/artifact flow.

## Deferred known issue
Codex short Voice Chat local/external microphone capture resumption after remote LONG remains `KNOWN_DEFERRED / NOT FIXED / NOT INDEPENDENTLY ACCEPTED`. Do not alter or overstate it in v0.2.14.

## Release boundary
No new product/test changes are authorized. Merge must preserve the audited release commit semantics. Tag/release publication must reference the accepted merged release state. Installed app/driver replacement, RemoteOrbit/CoreAudio restart, TCC/settings/mapping changes, and additional lifecycle cleanup are not part of publication unless separately authorized.
