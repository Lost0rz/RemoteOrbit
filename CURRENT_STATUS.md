# CURRENT_STATUS

Last updated: 2026-10-31
State: `RO-CI-SELF-HOSTED-RUNNER-MIGRATION-20261031 — REMOTE_SMOKE_PENDING`
Repository: `Lost0rz/RemoteOrbit`
Control parent before this task: `85061ab13ebe57ed485f06966f90275a6f53a6b9`
Active branch: `codex/ci-self-hosted-runner-migration-20261031`
Authoritative workspace: `/Volumes/Jack-Dev/Projects/remoteorbit`

## Repository identity

- Canonical remote: `https://github.com/Lost0rz/remoteorbit.git` (`origin`)
- Fetched `origin/main`: `85061ab13ebe57ed485f06966f90275a6f53a6b9`
- Local branch was created from that exact fetched ref.
- Previous Task 043 corrective authority remains preserved on
  `codex/ime-readiness-stability-043` and its separate worktree; it is not being
  edited, merged, or used as the CI writer.
- Existing unrelated open PRs are #25, #26, and #28; none is this task.

## Current host evidence

- Host architecture: `arm64`
- macOS: `26.6.2` (`25G83`)
- Xcode developer directory: `/Applications/Xcode.app/Contents/Developer`
- Swift: `6.4.2`
- Existing runner convention: `/Users/ox_miles/CI/runners/<repository>` with the
  official `svc.sh` launchd service and an isolated `_work` directory.
- No local RemoteOrbit runner directory, process, launchd service, or GitHub
  registration was found at task start.
- Official actions/runner release observed: `v2.338.2`; the macOS ARM64 asset is
  available.
- Workflow authority added at `.github/workflows/remoteorbit-ci.yml`; no prior
  workflow existed on the fetched baseline.
- Local pure-software verification passed: protocol self-tests, full Swift tests
  (`623`, `0` failures), native Release build, and build-only Universal2 packaging
  smoke. No app/driver installation or CoreAudio/TCC mutation was performed.
- GitHub runner registration: ID `21`, name `remoteorbit-macmini`, status `online`,
  `busy=false`, labels `self-hosted`, `macOS`, `ARM64`, `remoteorbit`.
- Official service evidence: `.service` points to
  `/Users/ox_miles/Library/LaunchAgents/actions.runner.Lost0rz-RemoteOrbit.remoteorbit-macmini.plist`;
  `launchctl` reports the service loaded and `Runner.Listener` is alive. No
  `Runner.Worker` is present while idle.

## Active task

`RO-CI-SELF-HOSTED-RUNNER-MIGRATION-20261031` is the sole active writer for this
workspace. It is limited to repository CI infrastructure and the dedicated
repository-scoped self-hosted runner. The normal RemoteOrbit runtime and Task 043
acceptance remain separate and must not be changed or reinterpreted.

## Next

Push this branch, open a Draft PR, run a bounded remote smoke, verify the job was
picked up by this exact runner, then reconcile the final controls. Stop on token,
admin, duplicate-runner, host-mutation, product-code, or unknown-state boundaries.
