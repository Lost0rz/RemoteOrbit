# RemoteOrbit Current Task

## RO-DIAGNOSTICS-LEGACY-RETIREMENT-045 — Wave A diagnostics gating

Status: `WAITING_FOR_INDEPENDENT_WEB_AUDIT`
TASK_CLASS: `BOUNDED PRODUCT IMPLEMENTATION`
Repository: `Lost0rz/RemoteOrbit`
Audited base: `main@fb4f8fd34015bb7aee9b8700068fe9f51ffc76d9`
Control parent before execution: `fb4f8fd34015bb7aee9b8700068fe9f51ffc76d9`
Implementation branch: `codex/task045a-diagnostics-gating`
Workspace: `/Volumes/Jack-Dev/Projects/remoteorbit-task045a-diagnostics-gating`
Execution start HEAD: `fb4f8fd34015bb7aee9b8700068fe9f51ffc76d9`
Design authority: `docs/design/2026-10-31-045-diagnostics-gating-and-legacy-retirement.md`
Human runtime acceptance: `Task 043 still DEFERRED / USER-OWNED`

## Completed execution and handoff

This execution context was created from current live `main` and implemented **Wave A diagnostics gating only**.

The implementation preserves all current voice semantics and correctness owners while making ordinary diagnostics disabled mode near-zero overhead.

Implementation commit: `4720fbd2f6322e687281cdaf9c7db2ab6c10a098`.
Control handoff commit: `a47d05e7a03ec97ef1a0506090828cd1e00114d4`.
Draft PR: `https://github.com/Lost0rz/RemoteOrbit/pull/31`.
Remote branch and PR head were verified at the control handoff commit. Remote CI
run `41214027305` / job `124574698531` passed on `remoteorbit-macmini`: focused
source contracts, protocol self-tests, full Swift tests (`656/656`), native Release
build, and Universal2 build-only packaging smoke (`x86_64 arm64`).

## Required Wave A behavior

Introduce one cheap process-local effective diagnostics state whose logical authority is:

```text
AppStorage.loggingEnabled || REMOTE_ORBIT_DIAGNOSTICS == "1"
```

The hot disabled check must not read UserDefaults, serialize JSON, touch disk, or synchronously dispatch on each event.

### Gate these surfaces

1. `VoiceDiagnosticLogger`
   - do not create/open/truncate its file when diagnostics are disabled;
   - `log()` must return before timestamp/field/enqueue work disabled;
   - enabling/disabling at runtime must start/stop its run lifecycle safely.

2. `DiagnosticAuthorityService.emit`
   - disabled return before semaphore admission, clock capture, event construction, writer enqueue and journal append;
   - query/snapshot/export over existing evidence remain available.

3. `DiagnosticRuntimeHealthService`
   - no heartbeat timer disabled;
   - enabled lifecycle remains functional.

4. `VoiceAttemptDiagnostics` / `VoiceStartWatchdog`
   - preserve any bounded attempt/session identity needed so production callers do not change behavior;
   - no disabled diagnostic emission or recurring watchdog timer;
   - enabled watchdog should be bounded to active diagnostic attempts and cancel cleanly.

5. `VoiceTimingLogger` / long-term observability
   - disabled path must not persist summaries/traces or run diagnostic-only recurring work;
   - enabled behavior remains testable;
   - supersede ADR-0003's old `L1 summary always on` runtime-policy statement in documentation.

6. `AudioPipe` diagnostic lifecycle
   - do not start the per-session `MainQueueResponsivenessProbe` or realtime diagnostic capture when diagnostics are disabled;
   - do not alter AudioPipe transport, IOProc, buffering, gain, prebuffer, route or drain behavior.

7. Settings diagnostics toggle
   - user-visible ordinary logging toggle must update the effective diagnostics runtime as well as text logging;
   - environment override remains force-on.

### Keep independent

`AppStorage.recordingEnabled` remains the sole user opt-in for WAV/RAW capture. Recording OFF creates no WAV/RAW files. Recording ON must continue to work even if ordinary diagnostics are OFF; structured recording metadata may be suppressed by the diagnostics gate.

## Explicit non-goals / frozen code

Do NOT in Wave A:

- remove or refactor Persistent-session production state;
- remove Dual-Receiver source/callers/tests;
- remove microphone SHORT UI/configuration yet;
- rename/rewrite generic Option gate/tombstone/suppression mechanisms;
- change the 300 ms LONG-only contract;
- change rapid-repress, pre-HID, BLE READY/reuse, drain/tail/grace behavior;
- change receiver-readiness polling architecture;
- change HID mapping semantics/readback correctness;
- change ATVV commands/codec/sample rate/gain;
- install/replace `/Applications/RemoteOrbit.app`;
- install/reload the driver, restart CoreAudio, change TCC/default devices;
- tag/release or merge the implementation PR.

## Tests completed before handoff return

Add focused tests proving disabled-mode work is absent at the relevant ownership seam. Prefer explicit counters/test seams over timing-only assertions.

At minimum establish:

- `VoiceDiagnosticLogger`: disabled has no active file/writer run and no queued record work; enabled still writes/flushes valid JSONL;
- `DiagnosticAuthority`: disabled `emit` performs zero producer admission/enqueue/journal append; enabled behavior unchanged;
- runtime health: disabled owns zero heartbeat timer; enabled owns at most one and stops cleanly;
- voice-start watchdog: disabled owns zero recurring timer; enabled attempt owns bounded timer and cancels on completion/end;
- `AudioPipe`/long-term diagnostics: disabled session starts no main-queue responsiveness timer/persistent summary path; enabled remains functional;
- recording OFF creates no WAV/RAW; existing recording ON tests remain green;
- current LONG-only regression tests remain unchanged and green.

The durable machine gate ran on `remoteorbit-macmini`:

1. focused changed-boundary tests;
2. full `swift test`;
3. native Release build;
4. Universal2 build-only packaging smoke through the durable CI workflow if a PR is opened.

## Delivery shape

Use this one fresh branch/worktree and one Draft PR for Wave A. `CURRENT_STATUS.md` and
`CURRENT_TASK.md` were updated atomically when this execution branch was established;
update them atomically again for the final handoff state as required by governance.

Stop after push/PR + machine verification at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`. Do not merge.

Independent web audit is now the next authorized control-plane step. Human UI/runtime
acceptance remains user-owned and pending. No installation, driver/CoreAudio/TCC
mutation, tag, release, or merge was performed.

## Return evidence

Return:

- governance route / capability actually used;
- start and final branch/HEAD/worktree identity;
- exact changed paths;
- effective gate ownership and runtime-toggle behavior;
- focused test results;
- full Swift/Release/package results;
- Draft PR identity and remote-head match;
- explicit confirmation that no Persistent/Dual retirement, install, driver/CoreAudio/TCC mutation, release or merge occurred;
- observed blockers/uncertainty, if any.
