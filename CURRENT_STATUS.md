# CURRENT_STATUS

Last updated: 2026-10-09
State: TASK 035 PR MERGED / TAG AND GITHUB RELEASE PUBLICATION PENDING
Repository: `Lost0rz/RemoteOrbit`

## Accepted merge
- User authorized normal publication of v0.2.14.
- Publication authorization control commit: `9142855063b3f594bc549e5d5930060f229226f0`.
- PR #21 release head: `6208266122414db3f3caf5852585eb24ed1b1a71`.
- Controlled merge commit: `46dc94f58e67d5da38420047f009d3f311321108`.
- Merge parents: publication-control commit + exact audited release commit.
- PR #21 is now CLOSED / MERGED.
- Merged release payload remains limited to `RELEASE_NOTES_v0.2.14.md` and `remote-orbit/Packaging/Info.plist` in addition to control-plane history.
- Release target remains `v0.2.14` / Build `43`.

## Validation carried forward
- focused voice suites: PASS;
- full Swift suite: 394/394 PASS;
- self-tests: 3/3 PASS;
- package build: PASS;
- packaged app identity/version/build/source-stamp: PASS;
- app Universal 2 and codesign: PASS;
- bundled `RemoteOrbitAudio.driver`: present, Universal 2, codesign PASS;
- product source changes in release commit: NONE;
- test source changes in release commit: NONE.

## Tag target
The canonical release tag target is the controlled merge commit:
`46dc94f58e67d5da38420047f009d3f311321108`.

Tag `v0.2.14` and the GitHub Release remain pending. Publication should use `RELEASE_NOTES_v0.2.14.md` and attach the normal `RemoteOrbit-0.2.14.dmg` artifact produced from the exact tagged release state.

## Deferred known issue
Codex short Voice Chat local/external microphone capture resumption after remote LONG remains `KNOWN_DEFERRED / NOT FIXED / NOT INDEPENDENTLY ACCEPTED`.

## Boundary
No product/test edits, installed-app/driver replacement, RemoteOrbit/CoreAudio restart, TCC/settings/mapping changes, or lifecycle cleanup are authorized as part of final publication.
