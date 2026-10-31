# RemoteOrbit Current Task

## RO-CI-SELF-HOSTED-RUNNER-MIGRATION-20261031 — Dedicated macOS ARM64 CI

Status: `REMOTE_SMOKE_PASS — DRAFT_PR_OPEN`
TASK_CLASS: `EXECUTION`
Repository: `Lost0rz/RemoteOrbit`
Canonical remote: `https://github.com/Lost0rz/remoteorbit.git`
Control baseline: `85061ab13ebe57ed485f06966f90275a6f53a6b9`
Implementation branch: `codex/ci-self-hosted-runner-migration-20261031`
Workspace: `/Volumes/Jack-Dev/Projects/remoteorbit`

## Authority and objective

The user explicitly authorizes this task to establish a repository-scoped GitHub
Actions self-hosted macOS ARM64 Runner on the current Mac mini and migrate
RemoteOrbit's durable automated source checks, Swift tests, and Release build to
that runner. This is CI/repository infrastructure work only. Task 043 product
runtime acceptance, BLE, ATVV, AudioPipe, HID, voice state, and HAL-driver
behavior remain outside scope and must remain untouched.

The durable target is one clear workflow, `.github/workflows/remoteorbit-ci.yml`,
triggered by pull requests and pushes to `main`, using:

```text
runs-on: [self-hosted, macOS, ARM64, remoteorbit]
```

The target runner identity is `remoteorbit-macmini` with custom label `remoteorbit`,
registered only for `Lost0rz/RemoteOrbit`. The runner must be installed outside the
repository, preferably under the existing shared convention
`/Users/ox_miles/CI/runners/remoteorbit`, with an isolated `_work` directory.

## Required work

1. Revalidate remote, branch, HEAD, worktree cleanliness, `origin/main`, open PRs,
   workflow inventory, host architecture, macOS, Xcode, and Swift before mutation.
2. Use the official `actions/runner` macOS ARM64 release. Obtain a one-time
   registration token only through the authenticated GitHub CLI/API; never place a
   token in source, task records, scripts, shell history, or logs.
3. Use the official unattended configuration and `svc.sh` macOS service mechanism;
   do not create a second custom daemon or plist. Verify installed/running service,
   live Listener process, GitHub online/idle state, and normal session persistence.
4. Add the durable workflow with bounded concurrency and a clean, reproducible
   checkout. It must record macOS, architecture, Swift, Xcode path, and runner
   name; verify the canonical Swift package paths; run the existing full Swift test
   command; and run the canonical Release build after confirming it.
5. Add packaging smoke only if it is demonstrably build-only and cannot install,
   replace, reload, or mutate the host. Otherwise document that it is intentionally
   omitted. Do not add the next-task Persistent/Dual Receiver retirement rules.
6. Classify all existing workflows as keep/migrate/retire/historical. Retire only
   completed task-specific workflows that can still trigger unwanted jobs; do not
   remove a workflow that still carries current authority without explicit evidence.
7. Use bounded runner/workspace hygiene. Do not read other worktrees or historical
   `/private/tmp` evidence, reuse user build artifacts, or delete unknown files.
8. Run at least one bounded remote smoke and preserve evidence that the job was
   picked up by `remoteorbit-macmini`, including test/build result and proof of no
   host runtime mutation.

The workflow is now implemented at `.github/workflows/remoteorbit-ci.yml`. Local
verification passed for protocol self-tests, full Swift tests (`623`, `0` failures),
native Release build, and build-only Universal2 packaging smoke. The packaging
smoke is safe because `package-app.sh` only writes checkout artifacts and temporary
build directories; it does not install the app or driver or mutate CoreAudio/TCC.

The runner is registered and online as `remoteorbit-macmini` (GitHub runner ID `21`)
with labels `self-hosted`, `macOS`, `ARM64`, and `remoteorbit`. The official service
is installed through `svc.sh` at the shared runner root, and `Runner.Listener` is
alive while idle. Implementation-head remote smoke run `41204522588` completed
successfully; job `124546780458` was picked up by `remoteorbit-macmini` and all
workflow steps passed. Follow-up control-only run `41204786216` also completed
successfully. GitHub reports the runner online and idle again afterward.

## Authorized repository changes

Only these paths may change:

- `CURRENT_STATUS.md` and `CURRENT_TASK.md` for this control transition and closeout;
- `.github/workflows/**`;
- CI-only helper scripts/documentation required by the workflow or runner.

Do not change `remote-orbit/Sources/RemoteOrbit/**`,
`remote-orbit-audio-driver/**`, or any BLE/ATVV/AudioPipe/HID/voice lifecycle
behavior. Do not install or replace the product app or audio driver, restart
`coreaudiod`, change TCC/Accessibility/Input Monitoring, change default devices,
run real RC003/Doubao acceptance, delete logs/recordings/configuration, or merge
to `main`.

## STOP boundaries

Stop and report without guessing if registration needs unavailable GitHub auth,
admin permission, a duplicate or unknown `remoteorbit-macmini`, another authoritative
RemoteOrbit self-hosted runner, any product/runtime host mutation, a product-code
change to make CI pass, or unknown local runner/worktree state whose cleanup could
lose data. Preserve local work and classify remote delivery as pending if push or
PR creation cannot be verified.

## Verification and delivery

Required evidence includes exact branch/HEAD and clean state, workflow syntax/source
contract checks, environment evidence, full Swift tests, Release build result,
runner registration/labels/online state, a remotely dispatched job picked up by this
runner, and host-runtime-mutation `NONE`. Verify the remote branch after pushing.

Commit the control transition and implementation on this branch, push only this
authorized branch, open a Draft PR for `Lost0rz/RemoteOrbit`, do not merge, and
stop with human/runtime acceptance of RemoteOrbit still separate.

The authorized outcome is complete for this task. PR #29 remains Draft and the
runner is intentionally left installed, service-managed, online, and idle for
future RemoteOrbit pull-request and `main` CI.
