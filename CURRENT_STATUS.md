# CURRENT_STATUS

Last updated: 2026-10-04
State: FOUNDATION GOVERNANCE — A3 TARGETED FRESHNESS REFRESH ACTIVE / B3 ACCEPTED / C CLOSED
Repository: `Lost0rz/RemoteOrbit`

This file is the authority for mutable project state. If local evidence disagrees
with this file, stop product mutation, reconcile read-only, and update this file
before continuing.

## Evidence labels

- **FACT** — directly verified by current evidence.
- **INFERENCE** — strongly supported but not directly observed.
- **HYPOTHESIS** — plausible explanation requiring more evidence.
- **UNKNOWN** — not established by available evidence.
- **HISTORICAL** — previously reported context not verified as current.

## Remote baseline

- **FACT — Default branch:** `main`
- **FACT — Remote main HEAD:** `5def97bac0f8d4e2896cbb0ee0ee56d0810aff2d`
- **FACT — Main HEAD message:** merge PR #19, single diagnostic Authority skeleton.
- **FACT — Latest published release:** RemoteOrbit `v0.2.13` / Build 42.
- **UNKNOWN — Installed/running build:** GitHub cannot establish local runtime identity.
- **FACT — Current open PRs:** PR #17 and PR #18.
- **FACT — PR #17:** OPEN + Draft + unmerged; its branch is the control-plane authority.
- **FACT — PR #18:** OPEN + Draft; `codex/persistent-long-boundary-probes-v1` at `71ef0e65117f2def4e30d5447ca55246c4d18434`; B3 external-boundary probe audit accepted.
- **FACT — PR #19:** MERGED + CLOSED; source head `ee4effd0b6435b5198a258fa9c9f063717f69136`; merge commit `5def97bac0f8d4e2896cbb0ee0ee56d0810aff2d`. Lane C is CLOSED.
- **FACT — Final closeout snapshot base:** live control-plane HEAD `8a09a80411fd3f19c37332a4d2e7799773cf5182`; the final status/task snapshot correction is a direct child of this audited HEAD and is pushed to the active control-plane branch.
- **FACT — Out-of-band PR metadata drift:** #9 and #16 were closed during earlier closeout and reopened at 2026-10-03T12:40:25Z / 12:40:27Z; #17 was closed at 12:40:31Z.
- **RULE — PR state is not task authority:** these metadata changes do not advance or replace CURRENT_TASK.

## PR lifecycle closeout

This closeout inventory predates the active Step 5 PR #18 line recorded above.

| PR | Title | Lifecycle | Remote state | Reason / successor |
| --- | --- | --- | --- | --- |
| #19 | diagnostic Authority skeleton | **MERGED / CLOSED** | CLOSED merged | merged as `5def97bac0f8d4e2896cbb0ee0ee56d0810aff2d`; Lane C accepted and closed |
| #17 | development control plane | **ACTIVE** | OPEN Draft, unmerged | sole current control-plane PR and task authority |
| #16 | persistent voice segment transaction isolation | **ABANDONED** | CLOSED Draft, unmerged | re-closed under explicit repository-closeout authorization; diff/discussion preserved |
| #15 | preserve Mac media keys | **MERGED** | CLOSED merged | merged into `main` 2026-10-01 |
| #14 | microphone short-action bypass | **MERGED** | CLOSED merged | merged into `main` 2026-09-29 |
| #13 | configurable voice trigger key | **MERGED** | CLOSED merged | merged into `main` 2026-09-30 |
| #12 | P1 closure / telemetry trim | **MERGED** | CLOSED merged | accepted P1 closure |
| #11 | release v0.2.13 | **MERGED** | CLOSED merged | accepted release line |
| #10 | P1 stage merge candidate | **MERGED** | CLOSED merged | accepted P0/P1 diagnostics + ATVV reassembly line |
| #9 | P0 audio data-plane audit | **SUPERSEDED** | CLOSED Draft, unmerged | re-closed under explicit repository-closeout authorization; purpose preserved by #10/#12 |
| #8 | release v0.2.12 | **MERGED** | CLOSED merged | accepted release line |
| #7 | consolidated v0.2.11 voice corrective | **MERGED** | CLOSED merged | accepted corrective |
| #6 | disabled-short classifier branch | **SUPERSEDED** | CLOSED Draft, unmerged | #7 consolidated accepted behavior |
| #5 | physical Option race diagnostic | **SUPERSEDED** | CLOSED Draft, unmerged | #7 explicitly excluded diagnostic-only line |
| #4 | single-owner synthetic Option architecture | **SUPERSEDED** | CLOSED Draft, unmerged | #7 explicitly rejected/excluded this architecture |
| #3 | release v0.2.11 | **MERGED** | CLOSED merged | accepted release line |
| #2 | voice recovery from known-good baseline | **MERGED** | CLOSED merged | accepted recovery line |
| #1 | verified integration baseline | **MERGED** | CLOSED merged | accepted baseline |

### PR state transition history

- **FACT:** PR #9 was given a SUPERSEDED closure comment and closed at 12:32, then reopened out-of-band at 12:40:25Z.
- **FACT:** PR #16 was given an ABANDONED closure comment and closed at 12:32, then reopened out-of-band at 12:40:27Z.
- **FACT:** PR #17 was closed out-of-band at 12:40:31Z without changing the control-plane branch.
- **FACT:** no explanatory PR comment accompanied the reopen/close sequence.
- **FACT:** under explicit repository-closeout authorization, PR #9 was re-closed as SUPERSEDED and PR #16 was re-closed as ABANDONED; both received fresh closeout comments.
- **FACT:** PR #17 has been reopened under the current RemoteOrbit closeout task; #9/#16 remain closed. Lifecycle counts remain ACTIVE 1 / MERGED 11 / SUPERSEDED 4 / ABANDONED 1.
- **RULE:** lifecycle classification and task authority are not inferred from PR open/closed state.

## Remote branch cleanup

This closeout inventory predates the active Step 5 probe branch recorded above.

Pre-deletion inventory: 18 branches. Final live inventory after closeout is listed below.

| Branch | Related lifecycle | Cleanup | Reason / blocker |
| --- | --- | --- | --- |
| `main` | ACTIVE baseline | **KEEP** | default branch |
| `codex/project-agents-control-plane-v1` | ACTIVE / PR #17 | **KEEP** | current control-plane authority |
| `codex/audio-data-plane-p0-audit` | SUPERSEDED / #9 | **DELETED** | PR preserves diff/history |
| `codex/configurable-voice-trigger-key` | MERGED / #13 | **DELETED** | no unique active authority |
| `codex/media-key-suppression-isolation` | MERGED / #15 | **DELETED** | no unique active authority |
| `codex/mic-disabled-bypass-short-classifier` | MERGED / #14 | **DELETED** | no unique active authority |
| `codex/p1-a6-long-duration-telemetry` | MERGED / #12 | **DELETED** | no unique active authority |
| `codex/p1-stage-merge-closure` | MERGED / #10 | **DELETED** | no unique active authority |
| `codex/persistent-segment-transaction-isolation` | ABANDONED / #16 | **DELETED** | PR preserves diff/history |
| `codex/release-v0.2.13` | MERGED / #11 | **DELETED** | release/PR preserve history |
| `codex/v0211-disabled-short-classifier` | SUPERSEDED / #6 | **DELETED** | closed PR preserves diff/history |
| `codex/v0211-option-race-audit` | SUPERSEDED / #5 | **DELETED** | closed PR preserves diff/history |
| `codex/voice-recovery-from-good` | MERGED / #2 | **DELETED** | accepted via merged PR |
| `codex/voice-single-owner-option` | SUPERSEDED / #4 | **DELETED** | closed PR preserves diff/history |
| `fix/v0211-final-voice-corrective` | MERGED / #7 | **DELETED** | accepted via merged PR |
| `release/v0.2.12` | MERGED / #8 | **DELETED** | accepted via merged PR |
| `codex/persistent-duplicate-audio-forensics` | no PR; unique forensic commits | **KEEP** | two unique post-main diagnostic commits; no PR preserves their review context |
| `codex/voice-single-owner-session` | no PR; historical unique commits | **KEEP** | unique unmerged commits with no PR; preserve pending a separate evidence-disposition decision |

Already absent before the confirmed remote deletion:

- PR #1 branch `codex/test-baseline-remoteorbit-20260901`
- PR #3 branch `release/v0.2.11`

Their PRs remain the durable merged history.

### Remote deletion status — complete

- **FACT:** the user gave final authorization to delete exactly the 14 candidate refs listed above.
- **FACT:** each ref was checked against its approved live SHA, deleted individually with `git push origin --delete <branch>`, and immediately verified absent with `git ls-remote --heads origin <branch>`.
- **FACT:** all 14 deletions succeeded and all 14 post-delete checks returned empty. There were zero already-absent candidates and zero unresolved delete failures.
- **FACT:** the first delete attempt for `codex/voice-recovery-from-good` failed with a transient `SSL_ERROR_SYSCALL`; a read-only check confirmed its expected SHA was unchanged, and one retry then deleted and verified the ref.
- **FACT:** after `git fetch origin --prune`, the live `ls-remote --heads origin` inventory contained exactly these four KEEP refs:

| Branch | Live SHA | Retain reason |
| --- | --- | --- |
| `main` | `7129ef72949eca956b1d0daddce707d5e417eeed` | default branch |
| `codex/project-agents-control-plane-v1` | this final status/task commit (direct child of `8a09a80411fd3f19c37332a4d2e7799773cf5182`) | sole control-plane authority / PR #17 |
| `codex/persistent-duplicate-audio-forensics` | `d0a1ab06d8fafa0e9a8a1ae3b79cbc0d299a07be` | unique forensic commits |
| `codex/voice-single-owner-session` | `cd96b2f937d2e4b0bdfb67111714a77ce77e78c6` | unique unmerged historical commits |

FACT: no retained worktree branch was named for a deletion candidate. The dirty P0 experiment worktree's HEAD `80ec3adfe065eac90547f7a76c58f0b510c639b9` remains preserved by its local branch and PR #6.

## Local worktree closeout — live owning-Mac census

FACT: The fresh census started from 23 registered entries: 13 live worktrees and 10 missing paths. After evidence review, four clean worktrees were removed, all ten verified-missing registrations were pruned, and a new clean control-plane worktree was created from the live branch for this documentation update. The current count is 10 live worktrees, zero missing registrations: nine retained worktrees from the initial census plus the active control-plane worktree.

### Live worktree final state

| Path | HEAD | Lifecycle | Delete result | Retain reason |
| --- | --- | --- | --- | --- |
| /Volumes/Jack-Dev/Projects/remoteorbit | 48a6d54ffa1a2798ac9ac760673d6406cec6bf12 | SUPERSEDED | RETAINED | One tracked edit in HIDMonitor.swift; no untracked files. The dirty change is preserved. |
| /private/tmp/remoteorbit-cross-mode-flight-recorder-minimal | 01eeddaecd0dff596b7e0fd31cd4b1862360bc9f | SUPERSEDED | RETAINED | Its local-only recorder commit is not on a remote or tag; the same checkpoint is held by the retained Flight Recorder worktree. |
| /Users/jack7788/.codex/visualizations/2026/09/23/01a0cbbc-b1be-7780-8508-4a842edbad0c/remoteorbit-audio-data-plane-p0-audit | af028a4f090ddc6278e43c18875a08d5e7299865 | SUPERSEDED | REMOVED | Clean and fully remote/PR-preserved; #9 is superseded by #10/#12. |
| /Users/jack7788/Documents/Code/remoteorbit-p0-voice-experiment | 80ec3adfe065eac90547f7a76c58f0b510c639b9 | SUPERSEDED | RETAINED | Eight tracked edits and three untracked files; base matches the closed #6 line. |
| /Users/jack7788/Documents/Code/RemoteOrbit-v0211-final-corrective | 2653c7207b22347ace3be33449bb3573770afe65 | MERGED | REMOVED | Clean; merged PR #7 preserves the accepted line. |
| /Users/jack7788/Documents/Code/RemoteOrbit-v0212-release | 415dec838553a53eb609eecaa7a069d7c21b40a1 | MERGED | REMOVED | Clean; merged PR #8 preserves the release line. |
| /Users/jack7788/Documents/Code/remoteorbit-voice-p0-final | 48a6d54ffa1a2798ac9ac760673d6406cec6bf12 | SUPERSEDED | RETAINED | Eight tracked edits and three untracked files; dirty evidence preserved. |
| /Volumes/Jack-Dev/Projects/remoteorbit-audio-p0 | 86beaf1c4707dc08fa234739c5aee2a301d3c62e | SUPERSEDED | RETAINED | One local-only P1-A1 commit; no remote ref preserves it. |
| /Volumes/Jack-Dev/Projects/remoteorbit-audio-p1-a3 | dba2b278b7ffbff5c2931cd83d002f6af412b87d | ABANDONED | RETAINED | One local-only experimental commit; no remote ref preserves it. |
| /Volumes/Jack-Dev/Projects/remoteorbit-audio-p1-a4 | f8e6b680b7c60da94f8befeb388fefb3b50f5fcb | MERGED | RETAINED | P1-A4 purpose is included in #10, but its three-commit local history is not on a remote ref. |
| /Volumes/Jack-Dev/Projects/remoteorbit-audio-p1-a5 | 8befb031eb54b461675e95adb706f73721339479 | MERGED | RETAINED | P1-A5 purpose is included in #10; four local-only commits and three untracked observer files are preserved. |
| /Volumes/Jack-Dev/Projects/remoteorbit-audio-p1-a6 | ab25e9d46e65afa02b284f2c26856f94024d6b9c | MERGED | REMOVED | Clean and remote/PR-preserved; merged PR #12. |
| /Volumes/Jack-Dev/Projects/RemoteOrbit-flight-recorder | 01eeddaecd0dff596b7e0fd31cd4b1862360bc9f | ACTIVE | KEEP | Frozen product-evidence worktree. Its clean detached checkpoint is unique local forensic evidence. No product debugging is authorized. |
| /private/tmp/remoteorbit-control-plane-closeout | Final closeout status/task commit; direct child of 8a09a80411fd3f19c37332a4d2e7799773cf5182 | ACTIVE | KEEP | Sole active control-plane checkout for PR #17 and this closeout. |

### Registered-but-missing entries pruned

All ten paths were absent on disk, and the dry run listed exactly these stale registrations. Their recorded HEADs were preserved by fetched remote refs, main, or the retained forensic branch.

| Registered path | HEAD | Lifecycle | Result | Evidence |
| --- | --- | --- | --- | --- |
| /private/tmp/remoteorbit-configurable-voice-trigger-key | 4a30a165d37b17e4933135fc8b501f9e1c8c67e2 | MERGED | PRUNED | PR #13 and its remote branch preserve the commit. |
| /private/tmp/remoteorbit-cross-mode-voice-flight-recorder | d0a1ab06d8fafa0e9a8a1ae3b79cbc0d299a07be | SUPERSEDED | PRUNED | Same HEAD remains on retained remote forensic branch. |
| /private/tmp/remoteorbit-historical-a-7129 | 7129ef72949eca956b1d0daddce707d5e417eeed | MERGED | PRUNED | Accepted main. |
| /private/tmp/remoteorbit-media-key-suppression-20261001 | b5b3620c1b4cf92b2df1109c7a4220e450e908a8 | MERGED | PRUNED | PR #15 and remote branch preserve the commit. |
| /private/tmp/remoteorbit-mic-disabled-bypass-short-classifier | b96ffe8c30279d9509dc5b703a763009e81334c0 | MERGED | PRUNED | PR #14 and remote branch preserve the commit. |
| /private/tmp/remoteorbit-p1-stage-merge | 7f6f703fadd5e89c087059d3167c0c4c5253fd6b | MERGED | PRUNED | Ancestor of accepted main. |
| /private/tmp/remoteorbit-persistent-duplicate-audio-forensics | d0a1ab06d8fafa0e9a8a1ae3b79cbc0d299a07be | SUPERSEDED | PRUNED | Stale registration removed; KEEP remote forensic branch remains. |
| /private/tmp/remoteorbit-persistent-voice-ab-clean | d0a1ab06d8fafa0e9a8a1ae3b79cbc0d299a07be | SUPERSEDED | PRUNED | Its HEAD remains on the retained remote forensic branch. |
| /private/tmp/remoteorbit-prewarm-failed-copy | 48a6d54ffa1a2798ac9ac760673d6406cec6bf12 | ABANDONED | PRUNED | HEAD is preserved by accepted main/history. |
| /private/tmp/remoteorbit-v0211-baseline | 48a6d54ffa1a2798ac9ac760673d6406cec6bf12 | MERGED | PRUNED | Accepted v0.2.11 baseline in main/history. |

### Local branch closeout

- FACT: 15 local branches were deleted after their worktrees were removed or stale registrations pruned.
- Deleted local branches: codex/audio-data-plane-p0-audit, codex/configurable-voice-trigger-key, codex/media-key-suppression-isolation, codex/mic-disabled-bypass-short-classifier, codex/p1-a6-long-duration-telemetry, codex/p1-stage-merge-closure, codex/release-v0.2.13, codex/v0211-disabled-short-classifier, codex/v0211-option-race-audit, codex/voice-single-owner-option, fix/v0211-final-voice-corrective, release/v0.2.11, release/v0.2.12, codex/cross-mode-voice-flight-recorder, codex/persistent-duplicate-audio-forensics.
- 13 branches were removed with git branch -d.
- Two required -D after Git refused -d: release/v0.2.11 (PR #3 is merged and preserves its exact head commit f28fee26d099157c144233c7a07578bd3fde970a) and codex/cross-mode-voice-flight-recorder (its exact commit is preserved by the retained origin/codex/persistent-duplicate-audio-forensics branch; no commit was unique to this local ref).
- FACT: retained local-only commits are 01eedda, 86beaf1, dba2b27, 63e4ca2, f8e6b68, and 8befb03; they remain reachable from retained worktree branches.
- FACT: retained local branches are codex/audio-p1-a3-adaptive-playout, codex/audio-p1-a4-receiver-finalization, codex/audio-p1-a5-front-edge, codex/cross-mode-flight-recorder-minimal, codex/p1-a1-ble-queue-isolation, codex/project-agents-control-plane-v1, codex/v0211-nonseize-hid-audit, codex/v0211-p0-voice-experiment, codex/v0211-voice-p0-final, and main.
- FACT: exactly one control-plane line is ACTIVE: codex/project-agents-control-plane-v1 / PR #17. The Flight Recorder is the only ACTIVE evidence worktree and is frozen.

## Incident mode

### Incident family

`PERSISTENT-LONG / EXTERNAL-IME PREMATURE SESSION STOP`

### Problem statement

RemoteOrbit has an unresolved incident in which the external IME / voice collection
session can stop unexpectedly around a Persistent LONG interaction, before the
intended LONG-classified voice transaction has been conclusively established.

This is now an **incident investigation**, not a bug-fix task.

### Root-cause status

**ROOT CAUSE: UNKNOWN**

The following must not be promoted to root cause without a fresh incident that
directly supports them:

- pre-classification trigger leakage or an early trigger edge;
- Option/F5 event ordering;
- WindowServer / foreground-application switching;
- BLE/audio transport behavior;
- Doubao/external-IME behavior;
- any timing race inferred from source inspection.

### Historical evidence boundary

Previous evidence is retained as context only:

- **HISTORICAL FACT:** a prior Persistent LONG incident showed the external
  collection session stopping shortly after physical press and before LONG
  classification completed.
- **HISTORICAL FACT:** that capture did not directly record an actual Option event
  that proved a pre-classification trigger leak.
- **HISTORICAL FACT:** a WindowServer foreground switch was observed in the same
  time region.
- **UNKNOWN:** whether either observation caused the session stop.
- **RULE:** restart/recovery/stability after restart is recovery evidence, not causal
  proof.

Historical captures may guide what to inspect, but they do not satisfy the fresh
incident gate.

### Incident-mode constraints

Until a fresh incident is captured and reviewed:

- no product behavior changes;
- no speculative fix;
- no opportunistic/refactor cleanup;
- no new logging, telemetry, probes, or instrumentation;
- no threshold/timing changes;
- no trigger/Option ownership changes;
- no BLE/audio algorithm changes;
- no build/install/release/runtime replacement merely to "make testing easier";
- no expansion into adjacent symptoms.

Existing evidence worktrees and existing diagnostics may be read and used as-is.

### Remote incident audit — verified findings

The 2026-10-03 remote read-only audit narrowed the next verification boundary without
establishing root cause.

#### Confirmed facts

- **FACT:** Persistent-open LONG uses the same 300 ms short/long classifier as the
  normal voice gesture.
- **FACT:** after LONG classification, the Persistent segment contract is
  `audio_only`; the segment must not intentionally emit a new external trigger edge.
- **FACT:** when a mapped trigger reaches `VoiceKeyFilter` while
  `optionDeferralActive == true`, the existing gate can record/capture/suppress it.
- **FACT:** when a mapped trigger reaches the event tap while no gate owns it, the
  current code has a pass-through path. Therefore a pre-gate mapped-trigger race is
  statically possible.
- **FACT:** current focused tests validate behavior after the gate has been armed;
  they do not reproduce the cross-layer ordering race between the hidutil-translated
  CGEvent and the HIDMonitor callback that arms the gate.
- **FACT:** existing diagnostics already record the key first-layer decision markers:
  `VOICE_PRESS_ENTRY` (for the retained forensic build),
  `OPTION_GATE_BEGIN`, `OPTION_GATE_CAPTURE`, `MAPPED_TRIGGER_EVENT`,
  `GESTURE_CLASSIFIED`, and Persistent segment lifecycle events.
- **FACT:** no new instrumentation is required to test the first hypothesis.
- **FACT:** the retained forensic branch
  `codex/persistent-duplicate-audio-forensics` at
  `d0a1ab06d8fafa0e9a8a1ae3b79cbc0d299a07be` adds richer correlation but is not
  zero-observer-effect; it performs additional diagnostic logging/bookkeeping.
- **FACT:** `main` and that forensic branch both identify as RemoteOrbit 0.2.13 /
  Build 42 and carry an unstamped diagnostic source head in source. Version/build
  alone cannot bind a fresh incident to an exact source revision.
- **FACT:** `VoiceDiagnosticLogger.startRun()` truncates
  `~/Library/Logs/RemoteOrbit/voice-diagnostic-current.jsonl` at application launch.
  A fresh incident's current JSONL must therefore be preserved before any restart.
- **FACT:** RemoteOrbit does not directly observe a Doubao/external-IME semantic
  `OPEN/STOPPED` state. The target stop must be anchored by the actual user-visible
  failure or another already-existing external/system evidence source.

#### Hypothesis under test

**HYPOTHESIS — PRE-GATE MAPPED-TRIGGER LEAKAGE**

A hidutil-translated mapped modifier event may reach the CGEvent tap before the
HIDMonitor path has entered `beginVoicePress()` and armed `OPTION_GATE_BEGIN`.
If that happens, the mapped trigger can take the existing pass-through path.

This is the **single first hypothesis to test**. It is not root cause.

#### Construction status

- **ROOT CAUSE:** UNKNOWN
- **CONSTRUCTION GATE:** BLOCKED
- **NEW INSTRUMENTATION GATE:** BLOCKED / NOT REQUIRED FOR FIRST TEST
- **NEXT VERIFICATION:** one fresh incident using the current installed/running
  runtime and existing observability only.

### Fresh incident evidence conditions

A fresh incident is authoritative for this audit only when:

1. the exact installed/running runtime is bound read-only by app path, running PID,
   executable path, executable hash, version/build, and any available diagnostic
   source-head marker;
2. no code/build/install/config/permission/driver/runtime mutation occurs after that
   identity capture and before the incident;
3. the actual target symptom is observed during a normal bounded reproduction;
4. the same evidence window contains the relevant mapped-trigger/gate/classifier
   markers;
5. the current diagnostic JSONL and any correlated evidence are copied/preserved
   **before** any RemoteOrbit restart or relaunch.

### First-layer decision matrix

| Fresh evidence | First-layer interpretation |
| --- | --- |
| `MAPPED_TRIGGER_EVENT action=pass` or equivalent unowned pass occurs before `OPTION_GATE_BEGIN`, in the same incident window as the target external-session stop | Strong direct support for the pre-gate leakage hypothesis. Root cause still requires causal review before construction. |
| `OPTION_GATE_BEGIN` precedes the mapped edge and all relevant mapped events are `defer_*` / `suppress`, while the target stop still occurs | This incident does not support pre-gate leakage; move the next audit boundary away from the gate rather than fixing it. |
| No mapped trigger event is present around the target stop | This incident does not establish an Option/mapped-trigger leak. Preserve it and return for review. |
| Runtime identity cannot be bound, evidence is mutated/overwritten, or the external stop is not actually observed | Fresh Incident Gate is BLOCKED; do not diagnose or construct from the capture. |

### Immediate stop / preservation conditions

Stop the local capture immediately when any one of these occurs:

- the first qualifying target incident occurs;
- the bounded normal capture completes without reproduction;
- runtime identity cannot be proven before capture;
- any prohibited mutation occurs;
- the evidence window cannot be preserved reliably.

On a qualifying incident, preserve the current JSONL and correlated evidence before
any restart/relaunch. Do not perform a recovery experiment first.

### Fresh-incident gate

A capture qualifies as a **fresh incident** only if:

1. it occurs after this incident-mode transition;
2. the exact installed/running RemoteOrbit identity is recorded read-only before or
   at capture time;
3. no code, diagnostics, permissions, driver, LaunchAgent, CoreAudio, packaging, or
   runtime configuration is changed between identity capture and the incident;
4. the failure is observed in normal reproduction flow rather than induced by a new
   experiment;
5. the evidence window includes enough existing data to establish the ordering of
   the physical interaction, classification/session lifecycle, and the observed
   external-session stop;
6. the incident is assigned a fresh timestamp/incident identifier and its evidence
   window is preserved.

If the failure does not reproduce in the bounded capture attempt, record
`NO_FRESH_INCIDENT` and stop. Do not compensate by changing the system.

## Fresh incident result

### Authoritative incident

- **FACT — Fresh Incident Gate:** PASS.
- **FACT — Incident ID:** `fresh-incident-20261003T225236+0800-afudfY`.
- **FACT — Target gesture:** `3F288F28-81AD-4CC3-96EA-E4B9665D2198`.
- **FACT — VOICE_PRESS_ENTRY:** 2026-10-03 22:50:13.993 +0800.
- **FACT — OPTION_GATE_BEGIN:** 2026-10-03 22:50:13.994 +0800.
- **FACT — GESTURE_CLASSIFIED:** `hold` at 22:50:14.306 +0800, `held_ms=313`.
- **FACT — User-visible target symptom:** the already-open external Doubao/Persistent
  voice session exited during this LONG interaction.
- **FACT — ATVV_AUDIO_STOP_RX:** 22:50:15.168 +0800; this is a BLE/ATVV transport
  fact and is not independently equivalent to the Doubao semantic session stop.
- **FACT — Mutation during capture:** NO.
- **FACT — Raw incident evidence was copied and SHA-256 sealed before restart/relaunch.
- **FACT — Runtime source marker:** `01eeddaecd0dff596b7e0fd31cd4b1862360bc9f`.
- **FACT — Running executable SHA-256:**
  `df27b16ff41dcc35191c4699700cbbe522bfd576cbfba7c376712821c58388c2`.
- **FACT — Installed/running path:** `/Applications/RemoteOrbit.app`;
  version `0.2.13`, build `42`, PID `4001` at capture.
- **FACT — PRE_GATE_LEAK_HYPOTHESIS:** INCONCLUSIVE. No mapped-trigger record was
  correlated to this gesture; later pass events are not attributed to it.
- **UNKNOWN — Root cause:** still unknown.
- **BLOCKED — Construction Gate:** remains blocked.

### Remote/runtime source limitation

- **FACT:** GitHub cannot resolve runtime source marker
  `01eeddaecd0dff596b7e0fd31cd4b1862360bc9f`; it is local-only evidence.
- **RULE:** remote source audit may define architecture and probe gaps, but must not
  claim line-for-line identity with the installed incident binary until the local
  checkpoint is reconciled read-only.

## Current authority

Exactly one remote control-plane line is ACTIVE:

```text
branch: codex/project-agents-control-plane-v1
task: INCIDENT MODE — MINIMUM BOUNDARY PROBE DELTA
PR #17: OPEN + Draft control-plane PR
```

Product behavior changes, runtime experiments, packaging, installation, release,
TCC, HAL, LaunchAgent, and CoreAudio mutation remain frozen. The active Step 5 task
authorizes only the bounded diagnostic probe and validation work recorded below.

Repository closeout and the Step 4 diagnostic-gap audit are complete. The active
Step 5 probe task and its current review boundary are defined in `CURRENT_TASK.md`.

## Step 4 — diagnostic gap audit

The remote read-only gap audit is frozen in
`docs/incident-diagnostics/PERSISTENT_LONG_DIAGNOSTIC_ARCHITECTURE.md`.

### Remote-audit conclusions

- **FACT:** the project already has substantial internal gesture/gate/BLE/audio
  diagnostics. Adding more internal state-machine log volume is not the current
  priority.
- **FACT:** the highest-value gaps are cross-process and boundary observations.
- **FACT:** RemoteOrbit's `voiceSessionMode == persistentOpen` is an internal
  command-derived belief. It is committed after trigger dispatch succeeds; there is
  no Doubao semantic ACK proving the external IME session is actually open.
- **FACT:** this creates two distinct state machines:
  1. RemoteOrbit persistent-session intent/belief;
  2. external Doubao/IME actual session state.
  They can diverge, and the second is not authoritative inside RemoteOrbit today.
- **FACT:** existing `MAPPED_TRIGGER_EVENT` observes the CGEvent-tap decision, but
  main does not bind it to the original HID report sequence or retain the original
  CGEvent timestamp as a first-class correlation field.
- **FACT:** abandoned PR #16 contains tested diagnostic prototypes for
  `RAW_HID_MIC_STATE`, `HID_MIC_EDGE_EMITTED`, report sequence and input-source
  tagging. Those are design evidence only; PR #16 is ABANDONED and none of that may
  be treated as current production capability without local/runtime verification.
- **FACT:** retained forensic branch `d0a1ab06...` adds structured audio-route,
  input-selection, ATVV and press/release correlation. It is an observation build,
  not a zero-observer-effect baseline.
- **FACT:** repository source contains no Doubao-specific or InputMethodKit/TIS
  semantic session observer.
- **FACT:** repository source contains no tracked source for
  `target-text-observer-current.jsonl` or `voice-flight-recorder-current.jsonl`;
  their exact capabilities belong to the local-only evidence line and must be
  reconciled locally before deciding that a new probe is required.

### Probe priority

- **P0 — external IME semantic session boundary:** establish an authoritative,
  read-only OPEN/LISTENING/STOP transition if the existing local observer already
  has one; otherwise this is the highest-value missing probe.
- **P0 — HID report → mapped CGEvent correlation boundary:** correlate physical
  microphone report/edge with mapped CGEvent using source sequence/time, without
  expanding gesture-internal logging.
- **P0 — cross-process clock/correlation anchor:** every boundary observer must
  carry enough wall-clock + monotonic/process identity to join one incident safely.
- **P1 — WindowServer/frontmost/focus boundary:** observe application activation /
  frontmost transition around the incident independently of RemoteOrbit's own focus
  intent.
- **P1 — CoreAudio consumer boundary:** distinguish "RemoteOrbit requested/default
  input changed" from "the target process actually opened/stopped consuming the
  virtual input".
- **P1 — ATVV/remote boundary:** current structured ATVV lifecycle is largely
  sufficient; prefer correlation improvements over more event volume.
- **P2 — PCM/internal queue detail:** existing audio diagnostics are already rich;
  add nothing unless a later evidence-backed hypothesis specifically requires it.

### Diagnostic strategy

Boundary-first order:

```text
runtime identity
→ actual external session state
→ physical HID edge
→ hidutil / mapped CGEvent delivery
→ gate ownership decision
→ WindowServer / focus state
→ ATVV transport
→ CoreAudio target consumption
→ internal PCM details only if still needed
```

No probe implementation is authorized by this audit.

## Local evidence package required before Construction Gate review

The remote audit cannot complete Step 4 without a local-only capability and evidence
reconciliation.

### Required local-only inputs

The local Agent must read-only establish all of the following:

1. **Runtime source reconciliation**
   - inspect checkpoint `01eeddaecd0dff596b7e0fd31cd4b1862360bc9f`;
   - record whether it contains the relevant HID, mapped-trigger, Persistent-session,
     Flight Recorder, target-text observer and focus/audio observation code;
   - compare only the incident-relevant paths against remote `main`,
     `d0a1ab06...`, and PR #16 prototypes;
   - report exact divergences that affect B1-B9 evidence capability.

2. **Existing observer capability inventory**
   - `voice-flight-recorder-current.jsonl`;
   - `voice-flight-recorder-incident.jsonl`;
   - `target-text-observer-current.jsonl`;
   - any existing observer source/config that produces those artifacts.

   For each observer, record:
   - source path / binary path / source HEAD if available;
   - process identity;
   - timestamp model: wall clock / monotonic / both;
   - correlation keys;
   - observed boundary;
   - what it can prove;
   - what it cannot prove;
   - whether it observes another process/system boundary or only RemoteOrbit state.

3. **Sealed incident hash verification**
   - verify the preserved evidence files against the recorded SHA-256 list before
     analysis;
   - any mismatch is BLOCKED.

4. **Boundary classification**
   Classify B1-B9 from
   `docs/incident-diagnostics/PERSISTENT_LONG_DIAGNOSTIC_ARCHITECTURE.md` as:
   `OBSERVED`, `PARTIAL`, `MISSING`, or `NOT_RELEVANT_TO_THIS_INCIDENT`.

5. **Fresh-incident forensic correlation**
   Using only the sealed incident, produce one ordered timeline for the target
   gesture and external stop.
   Do not substitute file-write order for event occurrence time.

6. **Construction evidence assessment**
   Explicitly answer:
   - `SPECIFIC_BROKEN_BOUNDARY`
   - `BROKEN_CONTRACT`
   - `FRESH_INCIDENT_DIRECT_SUPPORT`
   - `ADJACENT_BOUNDARIES_RULED_ENOUGH`
   - `PRE_FIX_FAILING_ACCEPTANCE`
   - `MINIMAL_FIX_SCOPE`

### Evidence standard

Construction review may advance only if the local evidence package proves all of:

```text
SPECIFIC_BROKEN_BOUNDARY = one named B1-B9 boundary
BROKEN_CONTRACT = one falsifiable expected-vs-observed rule
FRESH_INCIDENT_DIRECT_SUPPORT = YES
ADJACENT_BOUNDARIES_RULED_ENOUGH = YES
PRE_FIX_FAILING_ACCEPTANCE = defined and demonstrably FAILING before fix
MINIMAL_FIX_SCOPE = one bounded behavior boundary
```

If any item is UNKNOWN, PARTIAL, inferred only from static source, inferred only from
RemoteOrbit internal belief, or cannot be joined to the sealed incident, then:

`CONSTRUCTION_GATE = BLOCKED`

### Local update responsibility

After the read-only local audit, the local Agent is explicitly authorized to update
`CURRENT_STATUS.md` and `CURRENT_TASK.md` **together in one control-plane commit**
with:

- the local checkpoint reconciliation result;
- observer capability inventory;
- B1-B9 classification;
- sealed-incident correlation summary;
- exact remaining evidence gap, if any;
- Construction Gate result: `BLOCKED` or `READY_FOR_REMOTE_REVIEW`.

The local Agent must **not** set Construction Gate to PASS on its own.

`READY_FOR_REMOTE_REVIEW` means only that all required evidence fields are present
for a final gate decision.

No product code, probe implementation, rebuild, install, restart, or new reproduction
is authorized while producing this package.

## Local evidence handoff result

### Gate result

- **LOCAL_EVIDENCE_GATE:** PASS — all nine sealed incident files matched the
  recorded SHA-256 values.
- **CONSTRUCTION_GATE_RECOMMENDATION:** BLOCKED.
- **SPECIFIC_BROKEN_BOUNDARY:** NONE ESTABLISHED.
- **BROKEN_CONTRACT:** NONE PROVEN.
- **FRESH_INCIDENT_DIRECT_SUPPORT:** PARTIAL — the user-observed external session
  exit is real and the same LONG gesture has RemoteOrbit/ATVV shutdown evidence,
  but there is no machine-readable external semantic `STOPPED` event or exact stop
  timestamp.
- **ADJACENT_BOUNDARIES_RULED_ENOUGH:** NO.
- **PRE_FIX_FAILING_ACCEPTANCE:** NONE ESTABLISHED.
- **MINIMAL_FIX_SCOPE:** NOT ESTABLISHED.
- **ROOT CAUSE:** UNKNOWN.
- **CONSTRUCTION GATE:** BLOCKED.

Hash integrity proves preservation only; it does not complete causal evidence.

### Runtime checkpoint reconciliation — `01eedda...`

The local-only incident runtime was successfully inspected read-only.

| Capability | Result |
| --- | --- |
| raw HID microphone transition / equivalent | PARTIAL — HIDMonitor maintains current usage/down state and edge uptime, but no raw report timeline |
| HID report sequence | MISSING |
| mapped CGEvent observation | OBSERVED — `MAPPED_TRIGGER_EVENT` records mapped key/event/flags/gate/action |
| original CGEvent timestamp | MISSING — logger capture time is not original CGEvent timestamp |
| voice-press source tagging | OBSERVED — e.g. `source=hid_monitor` |
| Persistent internal state | OBSERVED — RemoteOrbit belief/owner/audio lifecycle only |
| WindowServer/frontmost incident observation | MISSING — only limited routing-time `NSWorkspace.frontmostApplication` reads |
| Target Text Observer in checkpoint | MISSING — separate observer |
| external IME semantic session observation | MISSING |
| target-process CoreAudio consumer observation | MISSING |

### Existing observer capability inventory

#### VoiceFlightRecorder

- **Source:** local checkpoint `01eedda...`;
  `remote-orbit/Sources/RemoteOrbit/VoiceFlightRecorder.swift`.
- **Runtime:** in-process in `/Applications/RemoteOrbit.app/Contents/MacOS/RemoteOrbit`.
- **Clock model:** `mach_continuous_time`-based monotonic nanoseconds + wall
  timestamp + recorder sequence.
- **Correlation:** gesture UUID, interaction epoch, callback/work, BLE generation,
  stream session ID.
- **Can prove:** RemoteOrbit-observed internal interaction/async/audio/transport
  ordering and ownership.
- **Cannot prove:** raw HID report → mapped CGEvent ordering; Doubao trigger
  acceptance; actual WindowServer state; external IME semantic session state;
  target-process CoreAudio consumption.
- **Observer effect:** non-zero in-process lock/ring-buffer/delayed-write overhead.

#### Target Text Observer

- **Source/Binary:** source head unavailable; historical binary path no longer
  exists.
- **Observed copy:** 43 records from 2026-10-02 22:06:08–22:22:25 +0800, before the
  fresh incident.
- **Clock fields:** wall clock + monotonic/uptime fields are present; implementation
  cannot be verified because source is unavailable.
- **Can prove:** historical AX/frontmost/text metadata sampled in that old window.
- **Cannot prove:** this incident's Doubao `OPEN/LISTENING → STOPPED`, this
  incident's focus/text state, or semantic external-session closure.
- **Coverage mismatch:** observed target bundles were Chrome/Codex, not the fresh
  incident's Doubao semantic session.

### Cross-observer correlation result

A reliable wall-clock + monotonic + PID + shared-incident/gesture join does not
exist across all observers.

RemoteOrbit internal logs can correlate by gesture ID and dual clocks; Unified Log
has system time/PID but no shared gesture/session key; the Target Text Observer copy
does not cover the incident window.

### B1-B9 local classification

| Boundary | Result | Evidence result |
| --- | --- | --- |
| B1 physical remote → IOHID | PARTIAL | physical LONG plus HIDMonitor-derived press, but no raw HID report record |
| B2 IOHID report → HIDMonitor edge | PARTIAL | press entry/edge timing exists; raw report sequence/timestamp missing |
| B3 hidutil → mapped CGEvent | MISSING | no mapped-trigger event correlated to target gesture; later unowned pass events are not attributable |
| B4 mapped CGEvent → Doubao trigger acceptance | MISSING | no receiver/semantic acceptance evidence |
| B5 RemoteOrbit persistent belief → actual Doubao session | PARTIAL | internal `persistent_open` plus user-reported exit; no machine-readable external state or exact stop time |
| B6 ATVV/audio → HAL/CoreAudio route | PARTIAL | ATVV/audio/route events exist; target consumer state is not observed |
| B7 HAL/CoreAudio → target process consumption | MISSING | no Doubao PID/client consumption evidence |
| B8 focus intent → WindowServer actual state | MISSING | no incident-correlated independent frontmost/focus observer |
| B9 external IME → target text/session state | PARTIAL | user reports exit; available Target Text Observer copy is stale and not Doubao-session evidence |

### Sealed incident correlation

Target LONG gesture `3F288F28-81AD-4CC3-96EA-E4B9665D2198`:

```text
22:50:13.993  VOICE_PRESS_ENTRY
22:50:13.994  OPTION_GATE_BEGIN
22:50:14.306  GESTURE_CLASSIFIED hold (313 ms)
22:50:14.308  ATVV_MIC_OPEN_TX
22:50:14.313–14.351  audio route / AUDIO_START / persistent segment activity
22:50:15.168  ATVV_AUDIO_STOP_RX
22:50:16.223  ATVV_MIC_CLOSE_TX
22:50:16.859  TRANSPORT_STOP
```

No `MAPPED_TRIGGER_EVENT` is correlated to this gesture. The user reports the
external Persistent/Doubao session exited during the gesture, but the exact semantic
stop instant is not machine-observed.

### Evidence-gap conclusion

The local handoff is complete and confirms the remote gap audit:

- the system has enough internal state-machine detail;
- the remaining blockers are boundary observations;
- current evidence cannot name one broken B1-B9 boundary;
- current evidence cannot define a falsifiable minimal behavior fix;
- current evidence cannot define a same-cause pre-fix failing acceptance.

Therefore Construction Gate remains BLOCKED.

## Step 5 — minimum boundary probe delta

The user explicitly authorized continuing from the completed gap audit toward a
testable/construction-ready state.

### Scope freeze

This phase authorizes **diagnostic boundary probe implementation only**.

Primary scope:

- **B3:** physical HID microphone transition → hidutil-translated mapped CGEvent;
- **B5/B9:** external IME/session evidence sufficient to timestamp or independently
  anchor the actual external voice-session transition, if a reliable read-only
  mechanism can be implemented without pretending an inference is a semantic ACK.

Secondary scope is allowed only if required to interpret those probes:

- **B8:** independent frontmost/application activation boundary.

Out of scope:

- behavior fixes;
- Option/gate semantics changes;
- Persistent-session behavior changes;
- BLE/audio buffering or routing changes;
- timing/threshold changes;
- broad internal log expansion.

### Active Step 5 implementation line

```text
branch: codex/persistent-long-boundary-probes-v1
base: main @ 7129ef72949eca956b1d0daddce707d5e417eeed
purpose: diagnostic boundary probes only
PR: #18 OPEN + Draft
behavior fixes: NOT AUTHORIZED
```

### Required probe acceptance

Before a new capture is authorized, the probe branch must prove:

1. transition-only instrumentation;
2. no behavior-path branching based on probe output;
3. B3 records raw HID microphone transition identity/sequence/time and mapped CGEvent
   original timestamp/observation/gate action in a joinable clock domain;
4. any B5/B9 observer clearly distinguishes:
   - direct external observation;
   - proxy observation;
   - inference;
5. focused tests prove diagnostic payload and no semantic behavior change;
6. diff audit confirms only diagnostic/test/support files changed.

### Gate semantics

- **PROBE IMPLEMENTATION GATE:** AUTHORIZED.
- **DIAGNOSTIC TEST GATE:** PASS after exact corrective-HEAD local validation.
- **NEW CAPTURE GATE:** READY_FOR_REVIEW; no capture performed.
- **CONSTRUCTION GATE:** BLOCKED until a new probe-enabled incident proves one
  broken contract and a pre-fix failing acceptance.

## Step 5 implementation result — remote phase

### Probe line

```text
branch: codex/persistent-long-boundary-probes-v1
base: main@7129ef72949eca956b1d0daddce707d5e417eeed
head: f3e852bb0d9d6358a62141dcb4f4e483257772d0
PR: #18 OPEN + Draft
```

### Implemented diagnostic delta

**B3 HID → mapped CGEvent**

- transition-only `RAW_HID_MIC_STATE`;
- monotonically increasing `hid_report_sequence`;
- `HID_MIC_EDGE_EMITTED` / `HID_MIC_EDGE_SUPPRESSED` carry report sequence and
  HID callback uptime;
- `MAPPED_TRIGGER_EVENT` carries original `CGEvent.timestamp` as
  `cg_event_timestamp_ns` plus seconds form and observer uptime;
- raw voice-key records carry the same CGEvent timestamp fields;
- `VOICE_PRESS_ENTRY` / `VOICE_RELEASE_ENTRY` identify
  `hid_monitor` vs `voice_key_filter_fallback`.

### Focused test delta

Added:

- `HIDMonitorDiagnosticsTests`;
- `VoiceBoundaryDiagnosticsTests`;
- `VoiceInputSourceDiagnosticsTests`.

The tests define the required pre-capture contract for transition-only HID records,
original CGEvent timestamp retention, source correlation, and absence of ownership
mutation from diagnostic logging.

### Remote static diff audit

- branch is two commits ahead of main, zero behind;
- changed production files:
  - `HIDMonitor.swift`;
  - `main.swift`;
- changed test files: three diagnostic test files;
- no trigger suppression/replay decision, Persistent session transition, classifier
  threshold, BLE path, audio route, or timing contract was intentionally changed;
- static diff review found diagnostic-field/logging additions only in behavior
  seams.

### External-session probe decision

No B5/B9 semantic observer was implemented in this remote phase.

Reason:

- no reliable direct external API/ACK has been established for Doubao
  `OPEN/LISTENING → STOPPED`;
- inventing a window/text proxy and naming it semantic session state would violate
  the evidence contract.

B5/B9 therefore remain PARTIAL/MISSING and must stay explicitly labeled that way.

### Gate state

- **PROBE IMPLEMENTATION GATE:** PASS for the diagnostic-only implementation.
- **DIAGNOSTIC TEST GATE:** PASS after focused and full local validation at
  `28824d9dc167f57e3163ef0844aec1b672717d8f`.
- **NEW CAPTURE GATE:** READY_FOR_REVIEW; independent timing-path review is pending,
  and no capture has been performed.
- **CONSTRUCTION GATE:** BLOCKED.
- **ROOT CAUSE:** UNKNOWN.

The repository has no GitHub Actions workflow for this Swift/macOS package, so remote
GitHub cannot establish a truthful test PASS. Local macOS validation is required.

## PR #18 observer-effect corrective revalidation — current result

Live authority was fetched and matched at validation start:

```text
AUTHORITY_FETCH: PASS
AUTHORITY_GATE: PASS
MAIN_HEAD: 7129ef72949eca956b1d0daddce707d5e417eeed
CONTROL_HEAD_AT_VALIDATION: 9bbc52095194dd6d59321d128a3a7e724ae370d7
START_PROBE_HEAD: f3e852bb0d9d6358a62141dcb4f4e483257772d0
```

The corrective was committed and fast-forward pushed only after confirming the live
probe branch still matched the expected start head. GitHub now reports PR #18 OPEN +
Draft at the pushed head:

```text
FINAL_PROBE_HEAD: 28824d9dc167f57e3163ef0844aec1b672717d8f
REMOTE_PROBE_HEAD: 28824d9dc167f57e3163ef0844aec1b672717d8f
PR_18: OPEN + Draft
```

Validation worktree:

```text
VALIDATION_WORKTREE: /Users/jack7788/Documents/Code/remoteorbit-pr18-observer-corrective
WORKTREE_HEAD: 28824d9dc167f57e3163ef0844aec1b672717d8f
WORKTREE_CLEAN: YES
```

Focused validation:

```text
HID_MONITOR_DIAGNOSTIC_TESTS: PASS (3)
VOICE_BOUNDARY_DIAGNOSTIC_TESTS: PASS (1)
VOICE_INPUT_SOURCE_TESTS: PASS (1)
VOICE_KEY_FILTER_REGRESSION: PASS (10)
VOICE_PRESS_REGRESSION: PASS (28)
PERSISTENT_REGRESSION: PASS (15)
FULL_SWIFT_TEST: PASS
TEST_TOTALS: 266 passed
FAILING_COUNT: 0
FULL_SWIFT_TEST_EXIT_CODE: 0
```

Static timing-path audit:

```text
RAW_REPORT_TIMESTAMP_CAPTURE: reportObservedUptime immediately after sequence capture
PRE_EDGE_DIAGNOSTIC_SERIALIZATION: NONE
PRE_EDGE_DIAGNOSTIC_ENQUEUE: NONE
EDGE_CALLBACK_ORDER: BASELINE_EQUIVALENT
SUPPRESSED_CALLBACK_ORDER: BASELINE_EQUIVALENT
HID_EDGE_TIMING_ANCHOR: BASELINE_EQUIVALENT
BEHAVIOR_DIFF_AUDIT: PASS
BEHAVIOR_CHANGE_FOUND: NO
```

The raw transition dictionary and `raw_hex` are now built after behavior callbacks;
records retain the captured raw occurrence uptime and HID report sequence. The
behavioral `now` is still sampled at the baseline location and remains the value used
by the 180 ms edge debouncer. No change was found to HardwareOptionGate ownership,
Option suppression/replay, Persistent open/close, the 300 ms classifier, BLE
activate/stop, AudioPipe routing/buffering, tail/drain, or synthetic-trigger
ownership.

No app install, fresh capture, incident reproduction, merge, release, or product
behavior change occurred. The original primary checkout's dirty `HIDMonitor.swift`
was preserved.

Current gates:

```text
DIAGNOSTIC_TEST_GATE: PASS
INDEPENDENT_TIMING_PATH_REVIEW: PENDING
NEW_CAPTURE_GATE: READY_FOR_REVIEW
CONSTRUCTION_GATE: BLOCKED
ROOT_CAUSE: UNKNOWN
```

## PR #18 independent timing-path review — PASS

Independent review of probe HEAD
`28824d9dc167f57e3163ef0844aec1b672717d8f` is complete.

Verified:

- the observer-effect corrective is one commit over
  `f3e852bb0d9d6358a62141dcb4f4e483257772d0` and changes only
  `HIDMonitor.swift`;
- raw HID report sequence and occurrence uptime are captured near report callback
  entry;
- full raw-transition field construction and logger enqueue occur only after the
  existing behavior callbacks;
- emitted and suppressed HID edge callbacks execute before their corresponding
  diagnostic logger calls;
- behavioral edge/debounce `now` remains at the baseline sampling location;
- on the mapped Option event-tap path, the gate/suppression branch is decided before
  `MAPPED_TRIGGER_EVENT` logging;
- local validation remains 266 passed / 0 failed with behavior diff audit PASS.

The independent review finding is recorded on PR #18 discussion comment
`5975576700`.

Current gates:

```text
INDEPENDENT_TIMING_PATH_REVIEW: PASS
DIAGNOSTIC_TEST_GATE: PASS
NEW_CAPTURE_GATE: AUTHORIZED_FOR_ONE_BOUNDED_CAPTURE
CONSTRUCTION_GATE: BLOCKED
ROOT_CAUSE: UNKNOWN
```

This authorizes exactly one probe-enabled fresh incident capture. It does not
authorize a product behavior fix, merge, release, or Construction Gate transition.

## Prior PR #18 local validation finding and corrective

Local validation of probe HEAD
`8e8ba2f8ff30584fd9e8b5f72e4673a0a247fe5d` produced:

```text
AUTHORITY_GATE: PASS
WORKTREE_CLEAN: YES
FOCUSED_DIAGNOSTIC_TESTS: PASS
FOCUSED_REGRESSION_TESTS: PASS
FULL_SWIFT_TEST: PASS
TEST_TOTALS: 266 passed
FAILING_COUNT: 0
BEHAVIOR_DIFF_AUDIT: FAIL
```

The behavior audit found one diagnostic observer effect:

- the probe sampled HID report uptime before parsing;
- that timestamp was then reused as the pre-existing edge/debounce timestamp;
- baseline sampled the behavioral edge timestamp after parsing/state update;
- therefore acceptance near the 180 ms debounce boundary could shift.

No user-visible failure was reproduced and no other behavior-path change was found.

A bounded corrective was pushed to PR #18:

```text
OLD_PROBE_HEAD:
8e8ba2f8ff30584fd9e8b5f72e4673a0a247fe5d

CORRECTIVE_PROBE_HEAD:
f3e852bb0d9d6358a62141dcb4f4e483257772d0
```

Corrective scope:

- raw-report diagnostics keep an independent `reportObservedUptime`;
- the production edge/debounce `now` is restored to the baseline sampling point;
- only `HIDMonitor.swift` changed in the corrective commit;
- no gate, Persistent, BLE, audio, classifier, replay or suppression semantics were changed.

Current gates:

```text
DIAGNOSTIC_TEST_GATE: PASS
NEW_CAPTURE_GATE: READY_FOR_REVIEW
CONSTRUCTION_GATE: BLOCKED
ROOT_CAUSE: UNKNOWN
```

## Prior quality-audit result

The three-file control plane completed three consecutive PASS rounds on live branch
HEAD `9b9a544e102539602facbdd761564ca8d488b8db` before this user-authorized phase
transition.

## Remote closeout result

- **PR classification:** COMPLETE — all 17 PRs classified.
- **Obsolete PR closure:** COMPLETE — #9 and #16 closed with preserved history.
- **Remote branch classification:** COMPLETE — 18 branches classified.
- **Remote branch deletion:** COMPLETE — exactly 14 authorized refs were deleted individually and post-verified; no unresolved failures.
- **Remote branches retained:** `main`, `codex/project-agents-control-plane-v1`, `codex/persistent-duplicate-audio-forensics`, `codex/voice-single-owner-session`.
- **Final remote inventory:** PASS — exactly four branches remain.
- **Local worktree closeout:** COMPLETE — 10 live worktrees and zero registered-but-missing paths; the dirty primary checkout and retained evidence worktrees remain preserved.
- **PR #17:** OPEN + Draft + unmerged; it remains the sole control-plane review artifact.

## Closeout disposition

Repository closeout is COMPLETE.

The user has now explicitly authorized the next task transition into INCIDENT MODE.
Product development remains FROZEN. No repair work is authorized.

## Previous next action — completed 2026-10-04

The one authorized probe-enabled capture from
`28824d9dc167f57e3163ef0844aec1b672717d8f` completed and was sealed. The current
next action is `SEALED_CAPTURE_CAUSAL_REVIEW`, recorded in the current-state section
below. No second attempt is authorized.


## PR #18 bounded probe capture — current state (2026-10-04)

The single authorized probe-enabled capture completed on exact probe HEAD
`28824d9dc167f57e3163ef0844aec1b672717d8f` and was sealed at
`2026-10-04T11:07:34+0800`.

```text
CONTROL_HEAD_AT_CAPTURE: 1df75c7bd33d53f61be6bcc76b5fae4de16cac24
BOUNDED_CAPTURE_ATTEMPTS: 1
INCIDENT_RESULT: NOT_REPRODUCED
SECOND_CAPTURE_AUTHORIZED: NO
EVIDENCE_SEAL: PASS
RUNTIME_PID: 25802
RUNTIME_IDENTITY_MATCH: YES
RUNTIME_EXECUTABLE_SHA256: 2eeb2e6ac43bf92698a44be9a1297792e5bc35daadd9f8ded4e767a1b494df8e
BUILD_EXECUTABLE_SHA256: 2eeb2e6ac43bf92698a44be9a1297792e5bc35daadd9f8ded4e767a1b494df8e
```

Evidence directory:

`/Users/jack7788/Library/Logs/RemoteOrbit/incidents/fresh-incident-20261004T102216+0800-pr18-probe`

The seal contains current `voice-diagnostic-current.jsonl`, `RemoteOrbit.log`,
relevant unified log, process snapshots, runtime identity, context, analysis, and
checksums. `target-text-observer-current.jsonl` and both Flight Recorder JSONL
files were excluded and marked missing because their source mtimes predated this
probe runtime; no historical copies were used as fresh evidence.

The short that opened Persistent was gesture
`9BB5AC9D-E1C3-40E9-80EC-0BDF5654E54C`. The distinct target LONG was
`52AE0F3E-3273-482D-9E92-8092EABCF165`. For the LONG, raw HID report sequence 3
and emitted edge occurred at approximately `11:03:02.7843 +0800`; voice press
entry was `11:03:02.790974`, gate begin was `11:03:02.792270`, and the mapped
event observer callback was `11:03:02.810047`. It carried original CG timestamp
`2251759486203 ns`, gate state `deferring`, action `defer_down`. Same-process
observer time places that callback 17.777 ms after gate begin. The original CG
timestamp cannot be directly compared with `ProcessInfo.systemUptime` using the
available clock calibration, so original-event occurrence ordering remains
unestablished. No trigger edge was emitted for the Persistent segment.

The user reported normal single-click start and normal Persistent LONG input,
with no premature external IME stop. RemoteOrbit recorded segment completion
with `session_remains_open=true`. A later Doubao AVFoundation/CoreAudio stop
appears as a proxy transition, not a semantic IME acknowledgement.

```text
B3: PARTIAL — raw report, edge, press, gate, and mapped event observed; original-CG cross-clock ordering unresolved.
B4: PARTIAL — internal defer/suppress decision observed; no external acceptance acknowledgement.
B5: PARTIAL — Persistent intent remains open internally; no external semantic acknowledgement.
B8: MISSING — no independent WindowServer/frontmost transition observer.
B9: PARTIAL — user observation and AVFoundation/CoreAudio proxy evidence; no semantic IME state observer.
PRE_GATE_LEAK_HYPOTHESIS: NOT ESTABLISHED — callback decision was after gate and deferred; original occurrence ordering is unresolved and forwarding before gate is not proven.
SPECIFIC_BROKEN_BOUNDARY: NONE ESTABLISHED
BROKEN_CONTRACT: NONE PROVEN
FRESH_INCIDENT_DIRECT_SUPPORT: NO — target failure did not reproduce
PRE_FIX_FAILING_ACCEPTANCE: NONE ESTABLISHED
MINIMAL_FIX_SCOPE: NOT ESTABLISHED
DIAGNOSTIC_TEST_GATE: PASS
NEW_CAPTURE_GATE: CONSUMED
CONSTRUCTION_GATE: BLOCKED
ROOT_CAUSE: UNKNOWN
NEXT_ACTION: SEALED_CAPTURE_CAUSAL_REVIEW
```

Do not authorize another capture or begin construction from this normal control-like
result. The original CG event clock relationship and the external IME semantic state
remain unresolved.


## Sealed-capture causal review — clock-basis reconciliation required

The bounded probe capture is sealed and no second capture is authorized.

A remote review identified that the current analysis may be overly conservative in
treating the original `CGEvent.timestamp` as an unrelated clock basis.

Apple documents `CGEventTimestamp` as elapsed nanoseconds since system startup.
The captured mapped-trigger record already contains both:

- `cg_event_uptime_seconds` derived from the original CGEvent timestamp;
- `observer_uptime` captured by RemoteOrbit at the event-tap callback.

The same diagnostic stream records monotonic uptime for
`OPTION_GATE_BEGIN`.

Therefore the sealed evidence should first be reconciled numerically before any new
instrumentation or reproduction is considered.

Required read-only calculation for target LONG
`52AE0F3E-3273-482D-9E92-8092EABCF165`:

```text
CG_EVENT_UPTIME_SECONDS
MAPPED_CALLBACK_OBSERVER_UPTIME
OPTION_GATE_BEGIN_UPTIME
VOICE_PRESS_ENTRY_UPTIME

CALLBACK_MINUS_CG_EVENT
CG_EVENT_MINUS_GATE_BEGIN
CALLBACK_MINUS_GATE_BEGIN
```

Also sample multiple ordinary mapped CGEvent records in the same run. If
`observer_uptime - cg_event_uptime_seconds` is consistently a small event-delivery
latency rather than a large/variable clock offset, classify the two values as
comparable for this run and use original CG occurrence time for B3 ordering.

Do not infer global clock equivalence across boots/sleep states beyond what the
sealed run and platform contract support.

Current gates remain:

```text
NEW_CAPTURE_GATE: CONSUMED
SECOND_CAPTURE_AUTHORIZED: NO
CONSTRUCTION_GATE: BLOCKED
ROOT_CAUSE: UNKNOWN
```

## Sealed-capture clock-basis reconciliation result — 2026-10-04

Read-only reconciliation completed for target LONG gesture
`52AE0F3E-3273-482D-9E92-8092EABCF165` from CONTROL_HEAD_START
`a3a1fa98c2af40cc1624701e23e5153710af062a`. The user-reported remote authority was
confirmed by the three exact local commit objects; no fetch was performed in this
continuation. The sealed capture manifest was rechecked and all nine listed SHA-256
entries returned OK. The capture directory remains unchanged.

Post-seal analysis artifact (outside the immutable capture package):
`/Users/jack7788/Library/Logs/RemoteOrbit/incidents/fresh-incident-20261004T102216+0800-pr18-probe-review/clock-basis-reconciliation.txt`

```text
CLOCK_CROSSCHECK_SAMPLE_COUNT: 34 non-synthetic mapped events
DELTA_MIN_MS: 91344320.889304
DELTA_MAX_MS: 91747341.767472
DELTA_MEDIAN_MS: 91479176.178486
DELTA_SPREAD_MS: 403020.878168
CLOCK_SCALE_COMPATIBILITY: NOT_ESTABLISHED
```

Across this run, `cg_event_uptime_seconds` is around 2246–2256 seconds while
`observer_uptime` is around 93590–94003 seconds; the calculated delivery deltas
are neither small nor stable. The target event has original timestamp
`2251759486203 ns` (`2251.759486203 s`). Its raw arithmetic against the gate and
press uptimes is not a valid ordering comparison under this failed compatibility
check.

Target process-uptime ordering through callback: accepted HID edge for raw report
sequence 3 at `93823.31207008334`, voice press at `93823.31876504167`, gate begin at
`93823.32004220833`, and mapped callback observer uptime at `93823.33781962501`.
The callback was `17.777417 ms` after gate begin, with `gate_state=deferring` and
`action=defer_down`; subsequent target handling recorded suppression. The sibling
post-seal artifact SHA-256 is
`7f79ae347b60464584d7929554fd23d2f36f804e5a3f9068177d4701fefd090a`.

```text
ORIGINAL_CG_EVENT_BEFORE_GATE_BEGIN: UNRESOLVED
MAPPED_CALLBACK_AFTER_GATE_BEGIN: YES
CALLBACK_AFTER_GATE_BEGIN: YES (17.777417 ms)
EVENT_TAP_DECISION_PRE_GATE: NO
FORWARDED_BEFORE_GATE: NOT_PROVEN
PRE_GATE_LEAK_HYPOTHESIS: NOT ESTABLISHED
B3: PARTIAL — original CG occurrence cannot be placed on process uptime basis
B4: PARTIAL — no external trigger acceptance acknowledgement
B5: PARTIAL
B8: MISSING
B9: PARTIAL
SPECIFIC_BROKEN_BOUNDARY: NONE ESTABLISHED
BROKEN_CONTRACT: NONE PROVEN
FRESH_INCIDENT_DIRECT_SUPPORT: NO
PRE_FIX_FAILING_ACCEPTANCE: NONE ESTABLISHED
MINIMAL_FIX_SCOPE: NOT ESTABLISHED
SECOND_CAPTURE_AUTHORIZED: NO
NEW_CAPTURE_GATE: CONSUMED
CONSTRUCTION_GATE: BLOCKED
ROOT_CAUSE: UNKNOWN
NEXT_ACTION: WAIT_FOR_NEW_AUTHORIZED_TASK
```

The earlier callback-level conclusion is narrowed: this attempt has no observed
pre-gate callback decision, but raw CG occurrence ordering and external forwarding
before the gate are not established. No B4/B5/B8/B9 upgrade follows from this
reconciliation. No second capture, construction, product change, merge, or release
is authorized.


## Mach timebase reconciliation — B3 upgraded for this attempt

A read-only follow-up established the local Mach timebase as:

```text
TIMEBASE_NUMER: 125
TIMEBASE_DENOM: 3
```

Direct runtime cross-check showed Mach-converted time, Dispatch uptime and
`ProcessInfo.systemUptime` agreeing within microseconds. Reinterpreting the captured
`CGEvent.timestamp` field as raw Mach absolute-time ticks and applying the
`125/3` conversion reconciles all 34 non-synthetic mapped-event samples onto the
same uptime scale.

Same-run mapped-event callback latency:

```text
SAMPLE_COUNT: 34
DELTA_MIN_MS: 0.699375
DELTA_MAX_MS: 57.200625
DELTA_MEDIAN_MS: 1.823271
DELTA_SPREAD_MS: 56.501250
32_OF_34_SAMPLES_UNDER_10_MS: YES
```

Target LONG `52AE0F3E-3273-482D-9E92-8092EABCF165`:

```text
CG_EVENT_RAW: 2251759486203
CG_EVENT_CONVERTED_UPTIME: 93823.311925125
RAW_HID_EDGE_UPTIME: 93823.31207008334
VOICE_PRESS_ENTRY_UPTIME: 93823.31876504167
OPTION_GATE_BEGIN_UPTIME: 93823.32004220833
MAPPED_CALLBACK_UPTIME: 93823.33781962501

CG_EVENT_MINUS_RAW_HID_MS: -0.144958
CG_EVENT_MINUS_VOICE_PRESS_MS: -6.839917
CG_EVENT_MINUS_GATE_BEGIN_MS: -8.117083
CALLBACK_MINUS_CG_EVENT_MS: 25.894500
CALLBACK_MINUS_GATE_BEGIN_MS: 17.777417
```

Result:

```text
CLOCK_SCALE_COMPATIBILITY: ESTABLISHED_FOR_THIS_RUN
ORIGINAL_MAPPED_EVENT_PRE_GATE: YES
EVENT_TAP_CALLBACK_PRE_GATE: NO
GATE_STATE: deferring
ACTION: defer_down
FORWARDED_BEFORE_GATE: NO for this captured gate path
B3_RESULT: OBSERVED_FOR_THIS_ATTEMPT
B4_RESULT: PARTIAL
```

This materially strengthens the race-boundary finding:

- the system-mapped CGEvent can be generated before RemoteOrbit establishes the
  Option gate;
- on this normal attempt, EventTap delivery happened late enough that the gate
  already existed and the event was deferred/suppressed;
- same-run delivery latency is variable and frequently below the approximately
  8.117 ms pre-gate generation window observed for the target gesture.

Therefore the design has an empirically observed timing window in which correct
containment depends on EventTap delivery latency. This establishes a real B3/B4 race
condition boundary, not the root cause of the historical incident.

The capture did not reproduce the target failure and there is still no external IME
acceptance acknowledgement. Therefore:

```text
SPECIFIC_BROKEN_BOUNDARY: NOT YET ESTABLISHED AS INCIDENT CAUSE
BROKEN_CONTRACT: NOT YET PROVEN AGAINST FAILING INCIDENT
FRESH_INCIDENT_DIRECT_SUPPORT: NO
PRE_FIX_FAILING_ACCEPTANCE: NONE ESTABLISHED
MINIMAL_FIX_SCOPE: NOT ESTABLISHED
SECOND_CAPTURE_AUTHORIZED: NO
NEW_CAPTURE_GATE: CONSUMED
CONSTRUCTION_GATE: BLOCKED
ROOT_CAUSE: UNKNOWN
```



## Step 6 authorization — pre-gate EventTap contract test

The user explicitly authorized the next investigation step after the Mach-reconciled
B3 result.

Step 6 objective:

- deterministically exercise the case where a mapped voice-trigger EventTap callback
  arrives before `OPTION_GATE_BEGIN`;
- determine the exact current forwarding/suppression behavior;
- define the candidate ownership contract at the HID → mapped CGEvent → gate
  boundary;
- establish whether a deterministic pre-fix failing acceptance can be written
  without changing production behavior.

This step is test/architecture work only.

Current frozen facts:

```text
ORIGINAL_MAPPED_EVENT_PRE_GATE: YES for the bounded normal capture
EVENT_TAP_CALLBACK_PRE_GATE: NO for that attempt
GATE_STATE: deferring
ACTION: defer_down
B3_RESULT: OBSERVED_FOR_THIS_ATTEMPT
B4_RESULT: PARTIAL
FRESH_INCIDENT_DIRECT_SUPPORT: NO
CONSTRUCTION_GATE: BLOCKED
ROOT_CAUSE: UNKNOWN
```

Allowed:

1. read-only audit of current trigger/gate ownership code;
2. add deterministic tests or test seams that simulate mapped EventTap delivery
   before gate activation;
3. characterize pass/defer/suppress behavior under that ordering;
4. define a falsifiable candidate ownership contract;
5. report whether a pre-fix failing acceptance exists.

Forbidden:

- no product behavior fix;
- no change to gate semantics;
- no threshold/timing changes;
- no BLE/audio changes;
- no reinstall or real-world reproduction;
- no second capture;
- no PR #18 merge/release.

The next gate is architecture/test evidence only. Construction remains blocked.



## Parallel foundation lanes — A / B / C

**FACT — User authorization:** on 2026-10-04 the active project scope was explicitly
split into three concurrent, isolated foundation lanes. This supersedes the prior
single-line Step 6 execution model as the current orchestration model. Historical
Step 6 evidence remains valid evidence; it is not deleted or promoted to root-cause
proof.

### Lane A — repository/worktree governance

- **Purpose:** inventory, freeze, and classify repository branches, PRs, and local
  worktrees.
- **Authority:** PR #17 / `codex/project-agents-control-plane-v1`.
- **Allowed mutation:** control-plane documentation needed to record verified state.
- **Forbidden:** diagnostic/product source edits; branch deletion; worktree
  removal/prune; PR close/merge; runtime/install/package changes.
- **Disposition vocabulary:** ACTIVE / MERGED / SUPERSEDED / ABANDONED /
  FORENSIC-RETAINED / UNKNOWN-BLOCKED.
- **Rule:** this lane is the sole writer of `CURRENT_STATUS.md` and
  `CURRENT_TASK.md` while A/B/C execute in parallel.

### Lane B — boundary probes and incident capture completeness

- **Purpose:** make the next incident causally discriminating at missing boundaries;
  "next time it fails, the boundary can be seen".
- **Current implementation authority:** PR #18 /
  `codex/persistent-long-boundary-probes-v1`.
- **Allowed:** diagnostic-only boundary probes, focused tests, capture correlation,
  incident diagnostic documentation.
- **Forbidden:** product behavior fixes; trigger/gate semantic changes; BLE/audio
  behavior changes; CLI work; Settings/UI exposure; release/install.
- **Isolation:** Lane B must not edit the control-plane files and must not define a
  competing durable diagnostic authority/schema.

### Lane C — single diagnostic Authority contract + schema skeleton

- **Purpose:** define one durable diagnostic authority, event envelope/schema,
  ownership/interface contracts, and focused contract tests.
- **Starting point:** fresh isolated branch/worktree from verified `main`.
- **Allowed:** new authority/schema/interface source files, tests, and architecture
  documentation required to prove the contract compiles and is internally coherent.
- **Forbidden:** full call-site wiring; HID/EventTap behavior changes; incident probe
  expansion; CLI work; Settings/UI exposure; release/install.
- **Isolation:** Lane C must not edit Lane B's active probe call sites or the
  control-plane files.

### Shared concurrency rule

A/B/C may execute concurrently only while their write sets remain disjoint. If two
lanes require the same production file or the same semantic owner, both stop at that
boundary and return the conflict to Lane A for control-plane disposition. No lane may
silently absorb another lane's scope.

Product-behavior Construction Gate remains **BLOCKED**. Parallel foundation work does
not authorize a fix, merge, release, install, or cleanup deletion.


## Lane A fresh remote governance census — 2026-10-04

### Remote result

**FACT — Remote census complete:** read-only GitHub audit found exactly 18 pull
requests (#1–#18) and exactly five live remote branches.

PR lifecycle freeze:

- **ACTIVE:** #17 control plane; #18 boundary-probe line.
- **MERGED:** #1, #2, #3, #7, #8, #10, #11, #12, #13, #14, #15.
- **SUPERSEDED:** #4, #5, #6, #9.
- **ABANDONED:** #16.

No other open PR exists.

Remote branch freeze:

| Branch | HEAD | Classification | Current evidence |
| --- | --- | --- | --- |
| `main` | `7129ef72949eca956b1d0daddce707d5e417eeed` | ACTIVE | accepted default baseline |
| `codex/project-agents-control-plane-v1` | `b18439cf994a19a75fbaf9d4f9e5bf8dd68ab9e2` at audit start | ACTIVE | A-line / PR #17 control-plane authority |
| `codex/persistent-long-boundary-probes-v1` | `28824d9dc167f57e3163ef0844aec1b672717d8f` | ACTIVE | B-line / PR #18 diagnostic-only probe authority |
| `codex/persistent-duplicate-audio-forensics` | `d0a1ab06d8fafa0e9a8a1ae3b79cbc0d299a07be` | FORENSIC-RETAINED | 2 commits ahead of main containing unique diagnostic/forensic source and tests |
| `codex/voice-single-owner-session` | `cd96b2f937d2e4b0bdfb67111714a77ce77e78c6` | FORENSIC-RETAINED | diverged: 9 commits ahead / 50 behind main; unique historical unmerged implementation remains reachable only through this ref |

Branch relationship facts:

- control-plane branch: 47 ahead / 0 behind main; diff is documentation/control-plane only;
- PR #18 branch: 4 ahead / 0 behind main; diff is bounded diagnostic probe/test scope;
- persistent duplicate-audio forensic branch: 2 ahead / 0 behind main;
- voice-single-owner-session: 9 ahead / 50 behind main.

**FACT — No remote cleanup mutation authorized or performed.** No branch was deleted,
no PR was closed/merged, and no diagnostic/product source was changed by Lane A.

### Local freshness gate

The previous owning-Mac closeout recorded 10 live retained worktrees and zero missing
registrations after an earlier cleanup. That record is now **HISTORICAL**, not a fresh
Lane A fact.

Lane A cannot finish until the owning Mac revalidates:

- registered worktree paths and exact HEADs;
- live vs missing state;
- branch/detached identity;
- clean/dirty/untracked state;
- upstream and ahead/behind state where applicable;
- local-only commits and untracked evidence that make a line non-disposable.

Until that fresh local census is returned, every historical retained local worktree
is **UNKNOWN-BLOCKED for cleanup**. No worktree removal, prune, branch deletion,
reset, clean, stash, or history rewrite is authorized.


## Lane A1 acceptance — fresh local census

**Remote independent audit result: ACCEPTED.**

The owning-Mac fresh census has now satisfied the Lane A repository/worktree
classification gate. This section supersedes the earlier "WAITING FOR FRESH
OWNING-MAC CENSUS" freshness gate.

### Fresh local facts

- **FACT — control remote authority:** live
  `codex/project-agents-control-plane-v1` was
  `817529ef2ff10441aebe077d58ad5c405cae3ae4` at the census boundary.
- **FACT — local control checkout:** clean at
  `2d8f8ac1a15039ec03ad5f8e17d8206e97075a67`, 0 ahead / 4 behind the
  verified control upstream. This is a known stale checkout, not an authority
  conflict because no local control write was performed.
- **FACT — origin/canonical root:** origin resolves to Lost0rz/RemoteOrbit and the
  canonical root is `/Volumes/Jack-Dev/Projects/remoteorbit`.
- **FACT — remote branch set:** matches the frozen five-branch remote inventory.
- **FACT — worktrees:** 14 registered / 14 live / 0 missing registrations.
- **FACT — local branches:** 11.
- **FACT — dirty worktrees:** 4.
- **FACT — untracked evidence:** 3 worktrees / 9 files.
- **FACT — local-only history:** six distinct local-only commit SHAs remain after
  ancestry deduplication.
- **FACT — no unknown item classification remains.**
- **FACT — no cleanup mutation was performed.**

### Accepted worktree disposition

**ACTIVE**

- A control-plane checkout (clean but stale by four control commits);
- Lane B PR #18 exact-head observer/corrective checkout;
- Lane C diagnostic-authority checkout at verified `main`.

**FORENSIC-RETAINED**

- canonical `remoteorbit` checkout because of a tracked local edit;
- cross-mode Flight Recorder checkpoint;
- P0 voice experiment and voice-p0-final dirty evidence lines;
- P1-A1 / P1-A3 / P1-A4 / P1-A5 lines because of local-only commits and/or
  untracked observer evidence;
- detached RemoteOrbit Flight Recorder checkpoint.

The six distinct local-only commits remain outside current live remote branches,
remote tags, and current GitHub PR heads and therefore remain preservation blockers.

**SUPERSEDED cleanup candidates — classification only**

1. `/private/tmp/remoteorbit-pr18-corrective-controls`
   - clean detached checkout;
   - no unique commits;
   - HEAD preserved by the live control branch / PR #17 history.
2. `/Volumes/Jack-Dev/Projects/remoteorbit-pr18-validation`
   - clean detached checkout;
   - no unique commits;
   - HEAD preserved by the current PR #18 line.

These are candidates only. No removal/prune/delete is authorized.

### A1 conclusion

**LANE A1 REPOSITORY / BRANCH / WORKTREE GOVERNANCE GATE: PASS**

Every current PR, remote branch, registered worktree, and local branch now has a
fresh evidence-backed disposition or preservation blocker. The Git/worktree layer is
sufficiently understood to move to the next governance layer.

This PASS does **not** establish a destructive-cleanup gate. The filesystem still
contains RemoteOrbit-related non-worktree assets (for example app archives,
diagnostic backups, preservation patches, incident captures, DMGs, observer/build
artifacts) whose preservation value and duplication status have not yet been frozen.

### Lane A2 construction authorization

**A2 CONSTRUCTION GATE: OPEN — READ-ONLY ARTIFACT INVENTORY ONLY**

Objective: inventory and classify RemoteOrbit-related non-worktree filesystem
artifacts so that future cleanup decisions cannot accidentally destroy the only copy
of forensic, release, incident, observer, or preservation evidence.

Scope includes, where present:

- RemoteOrbit app/archive directories;
- diagnostic-backup directories;
- preservation patch files;
- DMG/release/package artifacts;
- incident JSONL/capture bundles;
- observer source/build artifacts that are not already protected by a registered
  worktree;
- other clearly RemoteOrbit-owned filesystem artifacts discovered in the bounded
  project/archive locations.

A2 is inventory/classification only. It must establish path, artifact class,
size/count, provenance when determinable, Git/worktree reachability or duplication
when applicable, preservation value, and candidate disposition.

### A2 acceptance standard

A2 passes only when:

1. bounded scan roots are explicitly listed;
2. every discovered RemoteOrbit-related non-worktree artifact is classified as
   ACTIVE / FORENSIC-RETAINED / RELEASE-RETAINED / DUPLICATE-CANDIDATE /
   SUPERSEDED-CANDIDATE / UNKNOWN-BLOCKED;
3. unique forensic/release/incident evidence is identified and protected;
4. duplicate/candidate claims name the preserved authoritative copy or evidence;
5. registered worktrees are excluded from artifact cleanup classification rather
   than double-counted;
6. no file, directory, worktree, branch, PR, runtime, package, or source is mutated;
7. unresolved provenance is reported as UNKNOWN-BLOCKED, never guessed.

### Gates after this transition

- **A2 read-only artifact inventory:** OPEN.
- **Worktree/branch deletion gate:** BLOCKED.
- **Filesystem artifact deletion gate:** BLOCKED.
- **PR close/merge gate:** BLOCKED.
- **Product-behavior Construction Gate:** BLOCKED.
- **Release/install gate:** BLOCKED.


## Lane C independent audit + merge-gate authorization — 2026-10-04

### Verified state

- **FACT — baseline:** remote `main` remains `7129ef72949eca956b1d0daddce707d5e417eeed`.
- **FACT — C authority:** PR #19 / `codex/diagnostic-authority-audit`.
- **FACT — audited C HEAD:** `cb28bfd91e84309601b5fc2e36f9452b4a02b1d8`.
- **FACT — PR state:** OPEN + Draft + unmerged + mergeable.
- **FACT — C changed-file scope:** ADR, three new diagnostics source files, `WavRecorder.swift`, and two focused test files.
- **FACT — remote CI/status:** no GitHub Actions run and no commit status is attached to the audited C HEAD.
- **FACT — PR-recorded local validation:** 8 `DiagnosticAuthorityTests` passed, 1 `WavRecorderDiagnosticsTests` passed, and staged diff check passed.

### Independent conclusion

The C architecture and bounded proof have reached the施工 threshold for
**merge-gate validation only**.

```text
SINGLE_DIAGNOSTIC_AUTHORITY: PASS
VERSIONED_SCHEMA_V1: PASS
CLOSED_EVENT_CATALOG: PASS
CLOCK_DOMAIN_AND_MACH_TIMEBASE_PROVENANCE: PASS
CORRELATION_AND_PROCESS_PROVENANCE: PASS
FAIL_CLOSED_QUERY_DECODE: PASS
BOUNDED_NONBLOCKING_EMIT_DESIGN: PASS
PRODUCTION_CONTROL_ISOLATION: PASS
MINIMAL_WAVRECORDER_PROOF: PASS
FULL_PRODUCER_MIGRATION: NOT ATTEMPTED
CONFIRMED_CORRECTNESS_DEFECT: NONE
```

For precision, the accepted behavior statement is:

```text
PRODUCTION_CONTROL_BEHAVIOR_CHANGED: NO
VOICE_HID_RECOVERY_BEHAVIOR_CHANGED: NO
USER_VISIBLE_RECORDING_BEHAVIOR_CHANGED: NO
DIAGNOSTIC_SIDE_EFFECT_ADDED: YES
```

The diagnostic side effect is intentional: opt-in WavRecorder lifecycle metadata may
append to `diagnostic-events-v1.jsonl`. No WAV/raw path, filename, audio bytes, or
transcript content is emitted.

### Remaining C merge-gate evidence

Before PR #19 can be considered for merge:

1. add one deterministic queue-saturation/drop contract test;
2. run full `swift test` from `remote-orbit/`;
3. run `swift build -c release` from `remote-orbit/`;
4. prove final PR #19 local/remote HEAD match and clean worktree;
5. stop at `WAITING_FOR_INDEPENDENT_AUDIT` for a fresh web-side review.

No producer migration, retention/rotation, journal-read redesign, CLI, Agent API,
Settings/UI, recovery change, package/install/release, or PR merge is authorized.

### Concurrency / inventory note

Lane A1/A2 remains active and is not superseded. The earlier Lane A remote census
count of 18 PRs / five remote branches predates PR #19 and is now historical for any
future cleanup decision. A future cleanup gate must refresh the remote inventory and
include PR #19 / `codex/diagnostic-authority-audit`.


## Lane C final independent merge-gate audit — 2026-10-04

### Final remote evidence

- **FACT — final PR #19 HEAD:** `ee4effd0b6435b5198a258fa9c9f063717f69136`.
- **FACT — prior audited HEAD:** `cb28bfd91e84309601b5fc2e36f9452b4a02b1d8`.
- **FACT — delta:** exactly one commit ahead, zero behind.
- **FACT — delta file scope:** only `remote-orbit/Tests/RemoteOrbitTests/DiagnosticAuthorityTests.swift`.
- **FACT — delta size:** +28 / -0.
- **FACT — production-source delta after prior audit:** none.
- **FACT — PR #19:** OPEN + Draft + unmerged + mergeable.
- **FACT — remote `main`:** still `7129ef72949eca956b1d0daddce707d5e417eeed`.
- **FACT — GitHub CI/status:** no workflow run and no commit status is attached to the final HEAD.
- **LOCAL-REPORTED EVIDENCE:** full `swift test` = 271 passed / 0 failed; `swift build -c release` exited 0; local/remote PR head matched and worktree was clean.

### Independent test-delta audit

The added test `testQueueSaturationDropsEventWithoutBlockingProducerAndCountsDrop`
deterministically:

1. blocks the first journal append;
2. constrains pending capacity to one;
3. emits a second event while the first remains blocked;
4. proves the second producer call returns while the journal is still blocked;
5. proves `droppedEventCount == 1`;
6. releases the first append and proves only the first event reached the journal.

No production source, Authority contract, journal implementation, WavRecorder behavior,
schema, clock model, or producer wiring changed in the merge-gate delta.

### Final C disposition

```text
QUEUE_SATURATION_DROP_TEST_CONTRACT: PASS
QUEUE_SATURATION_PRODUCER_NONBLOCKING_CONTRACT: PASS
DROPPED_EVENT_COUNT_CONTRACT: PASS
FINAL_DELTA_TEST_ONLY: PASS
PRODUCTION_SOURCE_CHANGED_SINCE_PRIOR_AUDIT: NO
PR19_FINAL_REMOTE_HEAD: ee4effd0b6435b5198a258fa9c9f063717f69136
PR19_MERGEABLE: YES
C_MERGE_GATE: PASS
CONFIRMED_NEW_DEFECTS: NONE
C_LINE_SCOPE: COMPLETE
C_LINE_STATE: MERGE_READY
MERGE_EXECUTED: NO
MERGE_AUTHORIZATION: PENDING_EXPLICIT_USER_AUTHORIZATION
```

C must not resume producer migration, retention/rotation, CLI, Agent API, Settings/UI,
journal-read redesign, recovery changes, packaging, installation, or release under this
task. Any such work requires a new control-plane task after the C line is dispositioned.

Lane A2 remains independently active and is not superseded by this C result.


## Lane C merge authorization — 2026-10-04

**FACT — explicit user authorization:** merge PR #19 and close Lane C.

Authorized transition is exact and bounded:

- PR: #19
- expected head: `ee4effd0b6435b5198a258fa9c9f063717f69136`
- target: `main` currently `7129ef72949eca956b1d0daddce707d5e417eeed`
- action: mark ready if required, merge PR #19, verify resulting `main`, then update control plane to C CLOSED.
- no release/install/producer migration/cleanup is authorized by this transition.


## Lane A2 final independent audit — non-worktree artifact governance

**Independent web audit result: ACCEPTED.**

The A2 scan started at control HEAD `3e5416edea3f7472c8d2af01ba44c8f226574666` and observed a final control HEAD of `688e958bd237b6b6f23b316d9ec67b984c01f947`.
Independent reconciliation proved that this drift was a single C-line control-plane transition only: it modified `CURRENT_STATUS.md` and `CURRENT_TASK.md`, accepted the C merge gate, and explicitly preserved Lane A2.
No A2 scope, artifact, filesystem, or cleanup authority changed. Therefore the collected A2 evidence is valid and does not require a repeat scan.

### Scan coverage

- `/Volumes/Jack-Dev/Projects`
- `/Users/jack7788/Documents/Code` (symlink-equivalent to Projects and deduplicated)
- `/private/tmp`
- `/Users/jack7788/Applications`

The 14 registered worktrees were excluded from non-worktree classification. The scan found 20 non-worktree RemoteOrbit artifact groups. No artifact, worktree, branch, control file, runtime, package, or source was mutated.

### Final classification policy correction

- Identical bytes are not by themselves sufficient when filename/timestamp/context can carry distinct forensic meaning.
- An Applications app is not a cleanup duplicate merely because an exact bundle exists elsewhere if active operational use was not checked.
- A duplicate candidate must identify a preserved copy sufficient for the artifact's relevant preservation purpose.

### Final A2 classifications

**RELEASE-RETAINED — 1**

- `RemoteOrbit-app-archives/RemoteOrbit-0.2.12-41-20261003T154207+0800.zip` — versioned release/package archive; no exact local copy was proven and official release-asset equality was not checked.

**FORENSIC-RETAINED — 10**

- the two distinct v0.2.11 historical app backups under `remoteorbit-diagnostic-backups`;
- the eight nonempty package/test/filesystem/runtime/LaunchServices logs or snapshots under `/private/tmp`.

These objects have distinct content hashes or distinct historical runtime/package identity and no sufficient preserved duplicate was proven.

**DUPLICATE-CANDIDATE — 1**

- `/Volumes/Jack-Dev/Projects/RemoteOrbit-flight-recorder.source-preservation.patch` — byte-for-byte matches the binary patch generated from local commit `01eeddaecd0dff596b7e0fd31cd4b1862360bc9f`; that commit remains preserved by the registered Flight Recorder evidence line.

This is classification only, not deletion authorization.

**UNKNOWN-BLOCKED — 8**

1. `/Users/jack7788/Applications/RemoteOrbit P1A5 Observer.app` — exact bundle duplicate exists inside the retained P1-A5 worktree, but operational/running use was not checked.
2. `/private/tmp/remoteorbit-app-archive-verify.lftOpI/RemoteOrbit.app` — verification-temp provenance is plausible but archive equivalence was not proven.
3. `/private/tmp/remoteorbit-build-tools/swift` — temporary helper purpose/preservation value remains unclear.
4–8. the five zero-byte acceptance/snapshot/LaunchServices files — byte content is identical because each is empty, but distinct filename/timestamp/capture context may itself be evidence and no authoritative contextual replacement was proven.

No A2 artifact is classified SUPERSEDED-CANDIDATE.

### A2 acceptance evaluation

```text
BOUNDED_SCAN_ROOTS_DECLARED: PASS
REGISTERED_WORKTREES_EXCLUDED: PASS
NON_WORKTREE_ARTIFACT_GROUPS_ENUMERATED: 20
EVERY_GROUP_CLASSIFIED: PASS
UNIQUE_FORENSIC_EVIDENCE_PROTECTED: PASS
RELEASE_EVIDENCE_PROTECTED: PASS
DUPLICATE_CLAIM_NAMES_PRESERVED_EVIDENCE: PASS
UNRESOLVED_PROVENANCE_FAILS_CLOSED: PASS
MUTATIONS_PERFORMED: NONE
A2_GATE: PASS
```

### Lane A final disposition

**LANE A — INVENTORY / FREEZE / CLASSIFICATION: COMPLETE**

A1 repository/branch/worktree governance and A2 non-worktree artifact governance are both accepted. The current Lane A mandate was classification/freeze only, so no destructive cleanup follows automatically.

Final destructive gates remain:

- **worktree removal/prune:** BLOCKED;
- **local/remote branch deletion:** BLOCKED;
- **filesystem artifact deletion/move:** BLOCKED;
- **PR close/merge by Lane A:** BLOCKED;
- **reset/clean/stash/history rewrite:** BLOCKED.

Any cleanup requires a new explicit control-plane task with a refreshed remote/live inventory, because PR #18 and PR #19 advanced after the A1 census.

## Lane C closure — 2026-10-04

PR #19 was merged exactly from the independently audited source head
`ee4effd0b6435b5198a258fa9c9f063717f69136`.

```text
PR19_MERGED: YES
PR19_STATE: CLOSED
PR19_SOURCE_HEAD: ee4effd0b6435b5198a258fa9c9f063717f69136
MAIN_MERGE_COMMIT: 5def97bac0f8d4e2896cbb0ee0ee56d0810aff2d
REMOTE_MAIN_HEAD: 5def97bac0f8d4e2896cbb0ee0ee56d0810aff2d
C_IMPLEMENTATION: ACCEPTED
C_MERGE_GATE: PASS
C_LINE_STATE: CLOSED
```

The accepted C deliverable is the single diagnostic Authority/schema skeleton plus
the bounded opt-in WavRecorder proof. No further C construction is authorized.
Retention/rotation, higher-frequency producer migration, CLI, Agent API, Settings/UI,
journal streaming/read redesign, and later integrations require a new task.

Lane A is already complete under its accepted A1/A2 classification scope. Lane B
remains active under its existing scope.


## Lane B reconciliation audit — 2026-10-04

Independent remote reconciliation against the post-C baseline is complete.

```text
REMOTE_MAIN_HEAD: 5def97bac0f8d4e2896cbb0ee0ee56d0810aff2d
PR18_HEAD: ca35022be6cea6262d971ef0aedaa5550324004f
PR18_BRANCH: codex/persistent-long-boundary-probes-v1
PR18_VS_MAIN: DIVERGED — 5 ahead / 3 behind
MERGE_BASE: 7129ef72949eca956b1d0daddce707d5e417eeed
C_LINE: CLOSED
ROOT_CAUSE: UNKNOWN
PRODUCT_CONSTRUCTION_GATE: BLOCKED
```

- **FACT:** PR #19 / Lane C was designed with PR #18 explicitly in view. ADR-0001
  retains existing diagnostic writers as legacy sources and schedules HID boundary
  migration only after PR #18 stabilizes.
- **FACT:** the accepted C change does not modify PR #18's production probe files
  `HIDMonitor.swift`, `P1A4MonotonicClock.swift`, or `main.swift`; C adds the
  Authority/schema surface and the bounded WavRecorder proof producer.
- **FACT:** therefore the post-C baseline does not require PR #18 to migrate its
  HID/CGEvent probes into `DiagnosticAuthority` before the next bounded incident
  capture.
- **FACT:** PR #18 is nevertheless stale against current `main` because C was merged
  after B's current head. B must reconcile the exact current `main` before further
  probe/capture work.
- **CONCLUSION:** no confirmed file or semantic ownership conflict blocks a merge-only
  main reconciliation. Do not use reconciliation as an opportunity to rewrite,
  migrate, or expand B diagnostics.

**B2 reconciliation gate: OPEN** for integrating current `main` into the existing
PR #18 branch and validating equivalence only.

B probe/capture work remains blocked after that merge until local evidence proves:
clean pre-state, conflict-free integration, B probe-path preservation, focused B + C
diagnostic tests PASS, full Swift tests PASS, release build PASS, branch/remote sync,
and clean final worktree. No install, runtime replacement, fresh capture, behavior
fix, producer migration, or PR merge is authorized by this gate.


## Lane A3 cleanup-disposition audit authorization — 2026-10-04

### Gate decision

**AUDIT THRESHOLD: PASS.**

A1 repository/worktree governance and A2 non-worktree artifact governance remain
accepted as frozen evidence, but they are **not** sufficient to authorize destructive
cleanup after later B/C transitions.

Fresh remote reconciliation for this transition establishes:

- **FACT — remote main:** `5def97bac0f8d4e2896cbb0ee0ee56d0810aff2d` (PR #19 merged).
- **FACT — control branch before this transition:** `codex/project-agents-control-plane-v1`
  at `6bb9e1f4f0059324c4f0a17e51c78df01af5f326`.
- **FACT — open PRs:** #17 (control plane) and #18 (B boundary probes).
- **FACT — PR #18 pre-B2 head:** `ca35022be6cea6262d971ef0aedaa5550324004f`.
- **FACT — B2:** exact-main reconciliation is separately authorized; Lane B may
  advance after this snapshot, so A3 must fail freshness and stop if that occurs.
- **FACT — current remote branches at audit authorization:** six: `main`, control,
  PR #18, `codex/diagnostic-authority-audit`,
  `codex/persistent-duplicate-audio-forensics`, and
  `codex/voice-single-owner-session`.
- **FACT — merged C source branch remains present:** `codex/diagnostic-authority-audit`
  at `ee4effd0b6435b5198a258fa9c9f063717f69136`.
- **FACT — prior A2 result:** 20 non-worktree artifact groups were classified, with
  1 duplicate candidate, 8 UNKNOWN-BLOCKED, and no deletion authorization.

Therefore a refreshed local cleanup-disposition audit is justified and bounded.
This transition does **not** assert that any current worktree, branch, or filesystem
artifact is safe to delete.

### A3 purpose

Produce the evidence needed for a later exact cleanup decision without deleting,
moving, pruning, resetting, closing, merging, rebuilding, installing, or changing
product/diagnostic behavior.

A3 must refresh the owning-Mac state and answer separately:

1. which registered/live worktrees and local/remote branch lines remain required;
2. which non-worktree artifacts are uniquely valuable, operationally in use,
   sufficiently duplicated, stale, or still uncertain.

### A3 acceptance standard

A3 is complete only when all of the following are satisfied:

1. **Freshness:** remote main, control branch, PR #18 head, open PR set, remote
   branch set, and owning-Mac worktree registry are captured in one audit window.
2. **Worktree completeness:** every registered entry has path/live state, branch or
   detached identity, HEAD, dirty/untracked state, local-only commits, PR/task
   relation, reachability, preservation evidence, and one final disposition.
3. **Branch completeness:** every local and remote branch has an evidence-backed keep,
   cleanup-candidate, or blocked disposition. Merged status alone is insufficient if
   local evidence or an active worktree still depends on the branch.
4. **Artifact freshness:** the bounded A2 roots are rescanned with registered
   worktrees excluded; the prior 20 groups are reconciled and any new/changed
   RemoteOrbit-owned groups are added.
5. **Operational-use check:** app/observer/runtime artifacts are not called duplicates
   solely from byte equality when running/installed use, identity, filename/timestamp
   context, or capture provenance may matter.
6. **Duplicate proof:** every cleanup candidate names the preserved authoritative copy
   and proves that copy is sufficient for the relevant Git/forensic/release/runtime
   preservation purpose.
7. **Fail-closed:** unresolved provenance, local-only history, dirty evidence,
   operational-use uncertainty, or contextual evidence is `UNKNOWN_BLOCKED`.
8. **Exact manifest:** produce a proposed cleanup manifest split into worktrees, local
   branches, remote branches, files/directories, and registry-prune candidates, with
   explicit preconditions for each item.
9. **No destructive mutation:** no worktree removal/prune, branch deletion, file move
   or deletion, reset/clean/stash/rebase, PR mutation, runtime/install/package change,
   or source edit occurs during A3.

### Gates

- **A3 read-only audit:** OPEN.
- **Control-plane evidence writeback:** OPEN only for a same-commit
  `CURRENT_STATUS.md` + `CURRENT_TASK.md` checkpoint setting
  `READY_FOR_INDEPENDENT_WEB_AUDIT`; it must not authorize cleanup.
- **Worktree removal/prune:** BLOCKED.
- **Local/remote branch deletion:** BLOCKED.
- **Filesystem deletion/move:** BLOCKED.
- **PR close/merge by A3:** BLOCKED.
- **Reset/clean/stash/rebase/history rewrite:** BLOCKED.
- **Runtime/install/package/release mutation:** BLOCKED.

A later destructive-cleanup transition requires independent web audit of the A3
evidence and explicit user authorization of the exact deletion set.


## Lane B B2 reconciliation independent audit — 2026-10-04

Independent remote audit of the reconciliation-only transition is **PASS**.

```text
B2_START_HEAD: ca35022be6cea6262d971ef0aedaa5550324004f
B2_MAIN_BASELINE: 5def97bac0f8d4e2896cbb0ee0ee56d0810aff2d
B2_MERGE_HEAD: a71ce1d48c08bda1ad86bcd5c3a75a5e5ed90353
B2_MERGE_PARENTS:
  ca35022be6cea6262d971ef0aedaa5550324004f
  5def97bac0f8d4e2896cbb0ee0ee56d0810aff2d
PR18_REMOTE_HEAD: a71ce1d48c08bda1ad86bcd5c3a75a5e5ed90353
PR18_STATE: OPEN_DRAFT_UNMERGED
B2_SCOPE: MAIN_RECONCILIATION_ONLY
B2_PROBE_EXPANSION: NONE
B2_GATE: PASS
```

Remote comparison proves the reconciliation added only the accepted C/main tree to the
existing B line. Relative to current `main`, PR #18 contains only the six previously
audited B probe/test paths. No B7/B8 probe implementation was part of B2.

Local-reported validation accepted for this gate:

- focused B diagnostics: 3 suites / 6 tests PASS;
- focused C diagnostics: 2 suites / 10 tests PASS;
- full Swift suite: 277 passed / 0 failed;
- release build: PASS;
- local/remote branch: 0 ahead / 0 behind;
- final worktree: CLEAN.

No install, runtime replacement, incident capture, product fix, or PR merge occurred.

### Lane B next construction threshold

The B2 reconciliation prerequisite is now satisfied. The next bounded construction
stage may address only the already-reconciled external boundary sources:

- **B7 — target-process input-consumer transitions**, if macOS 13-compatible
  read-only CoreAudio observation is proven at implementation time;
- **B8 — actual frontmost-application transitions** via an independent,
  transition-only observer.

B4 external acceptance and B5 external semantic-session state remain
`SOURCE_NOT_FOUND` and are not construction targets. B9 target-text observation
remains deferred pending a separate capability/privacy gate.

C remains CLOSED. The merged DiagnosticAuthority is now infrastructure consumed by
B; this does not reopen Lane C.


## Lane B B3 external-boundary probe independent audit — 2026-10-04

Independent remote audit of PR #18 head
`71ef0e65117f2def4e30d5447ca55246c4d18434` is **PASS** for the authorized
B7/B8 scope.

```text
B3_START_HEAD: a71ce1d48c08bda1ad86bcd5c3a75a5e5ed90353
B3_FINAL_HEAD: 71ef0e65117f2def4e30d5447ca55246c4d18434
PR18_REMOTE_HEAD: 71ef0e65117f2def4e30d5447ca55246c4d18434
PR18_STATE: OPEN_DRAFT_UNMERGED
B8_FRONTMOST_TRANSITION: PASS
B8_POLLING_USED: NO
B7_MACOS13_AVAILABILITY: BLOCKED_BY_DEPLOYMENT_FLOOR
B4_EXTERNAL_ACCEPTANCE: SOURCE_NOT_FOUND
B5_EXTERNAL_SESSION_STATE: SOURCE_NOT_FOUND
B9_TARGET_TEXT: DEFERRED
ROOT_CAUSE: UNKNOWN
PRODUCT_CONSTRUCTION_GATE: BLOCKED
```

Remote diff from the accepted B2 head changes only four paths:
`DiagnosticEvent.swift`, the new
`FrontmostApplicationDiagnosticsObserver.swift`, `main.swift`, and focused B8
tests. The Authority change is limited to the closed catalog definition and string
payload-kind acceptance required by the B8 event. No schema version, envelope,
canonical clock, runtime provenance, queue/emission, journal, query, pagination,
snapshot, or retention mechanism changed.

The B8 observer is diagnostic-gated, notification-driven, and re-reads
`NSWorkspace.frontmostApplication`; it does not poll. Initial state establishes a
baseline without emission, repeated identity is suppressed, and identity changes are
emitted through `DiagnosticAuthority` with bundle ID and PID only. No window title
or user content is recorded. No direct JSONL writer was added and no voice/HID/Option
gate/BLE/audio behavior is changed.

B7 was correctly not implemented for the repository's macOS 13 deployment target.
The implementation-time check reported the modern `AudioHardwareSystem` surface as
unavailable on that floor. Independent review further narrows the compatibility fact:
the public per-process CoreAudio process-object family used for PID/input-running
attribution is documented/used on macOS 14.2+ in the older selector surface, while
newer Swift wrappers may have a later floor. Either way, the required per-process
input-consumer observation is not available under the macOS 13 contract without
raising the deployment target or introducing a different unsupported mechanism.
Therefore B7 remains `BLOCKED_BY_DEPLOYMENT_FLOOR`; no device transition is claimed.

Local validation reported for the exact remote head is accepted for this gate:
focused B tests PASS, DiagnosticAuthorityTests 9 PASS,
WavRecorderDiagnosticsTests 1 PASS, full Swift suite 282 PASS, release build PASS,
diff check PASS, remote sync PASS, and clean final worktree.

### B-line disposition after B3

B8 is now observable. B7 is explicitly unavailable on the current deployment floor.
B4/B5 remain source-not-found rather than inferred from internal state. B9 remains the
only deferred P0/P1-adjacent evidence surface that has not yet received its separate
capability/privacy disposition.

**No new B construction is authorized by this audit.** The next possible transition
is a separate B9 capability/privacy gate whose purpose is to determine whether the
existing target-text observer capability can be safely used or adapted without
recording user content, and otherwise to classify B9 as externally/privacy
unobservable. That transition requires separate authorization before local work.


## Lane A3 independent reconciliation — targeted freshness refresh authorized

### Independent assessment of the returned A3 evidence

The returned A3 evidence package is accepted as a valid **body-of-evidence baseline**:

```text
A3_EVIDENCE_BODY: ACCEPTABLE
REGISTERED_WORKTREES: 14
LIVE_WORKTREES: 14
MISSING_REGISTRATIONS: 0
DIRTY_WORKTREES: 4
UNTRACKED_EVIDENCE_FILES: 9
NON_WORKTREE_ARTIFACT_GROUPS: 20
FULL_A3_RESCAN_REQUIRED: NO
```

The exploratory recursive `find` under the already-authorized `/private/tmp` scan
root enumerated unrelated MemoX/cache path names, but no unrelated file contents were
read and no unrelated result was used to classify RemoteOrbit assets.

Independent disposition:

```text
PROCESS_SCOPE_DEVIATION: YES
EVIDENCE_CONTAMINATION: NO
A3_BODY_INVALIDATED: NO
```

The prior A3 cleanup manifest is therefore not rejected merely for that enumeration.

### Current freshness blocker

The returned A3 snapshot classified the active B line at
`a71ce1d48c08bda1ad86bcd5c3a75a5e5ed90353`.
PR #18 subsequently advanced by one accepted B3 commit to:

`71ef0e65117f2def4e30d5447ca55246c4d18434`.

Independent remote review proves that advancement is bounded to the accepted B8
frontmost-application diagnostic work. It does not by itself invalidate the A3
worktree/artifact classifications, but it makes the deletion manifest stale under the
A3 freshness contract.

Therefore:

```text
A3_CURRENT_FRESHNESS: STALE_DUE_TO_PR18_ADVANCE
TARGETED_FRESHNESS_REFRESH_REQUIRED: YES
FULL_RESCAN_REQUIRED: NO
DESTRUCTIVE_CLEANUP_GATE: BLOCKED
```

### Evidence that may be reused without full rescanning

Unless a targeted refresh proves a material change, retain the existing A3 findings
for:

- the six local-only forensic commit SHAs;
- four dirty worktrees and nine untracked evidence files;
- twenty non-worktree artifact groups and their hashes/classifications;
- two v0.2.11 diagnostic backup apps;
- retained audio/Flight Recorder forensic worktrees;
- the release ZIP;
- the proposed duplicate source-preservation patch;
- the candidate C worktree/branch after PR #19 merge;
- the clean detached corrective-control checkout whose HEAD is an ancestor of the
  control branch.

Do not recompute hashes or recursively rescan all twenty artifact groups unless the
targeted refresh detects a path/mtime/size/count change or a new relevant artifact.

### Targeted refresh gate

A3 may now collect only the delta evidence needed to restore freshness:

1. exact remote main, control HEAD, PR #17/#18 state, PR #18 head, and six-branch set;
2. fresh `git worktree list --porcelain`: registered/live/missing counts;
3. current dirty/untracked status for all four proposed worktree-delete candidates;
4. current ancestry/reachability for the two proposed local-branch deletions and the
   proposed merged C remote-branch deletion;
5. current preservation proof for the Flight Recorder patch/commit dependency;
6. confirmation that the PR #18 validation checkout is not the active B worktree,
   contains no dirty/untracked/local-only evidence, and has no known task dependency;
7. bounded metadata check of the prior 20 non-worktree groups sufficient to establish
   whether path/existence/size/mtime/count changed, plus discovery of any new clearly
   RemoteOrbit-owned artifact created since the A3 snapshot;
8. exact revised cleanup manifest and any remaining UNKNOWN_BLOCKED item.

If metadata indicates a material artifact change, rescan only the affected
artifact/group rather than restarting all A3 evidence.

### Gates

- **Targeted A3 freshness refresh:** OPEN.
- **Full A3 rescan:** NOT REQUIRED unless the targeted refresh discovers material
  change.
- **Control-plane evidence writeback:** OPEN for a same-commit
  `CURRENT_STATUS.md` + `CURRENT_TASK.md` checkpoint only.
- **Destructive cleanup:** BLOCKED.
- **Worktree/branch/file deletion or prune:** BLOCKED.
- **PR mutation:** BLOCKED.

The local executor may stop at `READY_FOR_INDEPENDENT_WEB_AUDIT` only if the
targeted refresh is internally fresh at writeback time and the exact manifest is
fully supported. It must not authorize or execute deletion.


## Lane B B9 capability/privacy audit authorization — 2026-10-04

The user explicitly authorized a B9 audit after B3 acceptance.

Remote pre-audit establishes:

```text
CONTROL_HEAD_BEFORE_B9: 36985064e5cc2b64bed608bc7708b7949a2500b5
REMOTE_MAIN_HEAD: 5def97bac0f8d4e2896cbb0ee0ee56d0810aff2d
PR18_HEAD: 71ef0e65117f2def4e30d5447ca55246c4d18434
PR18_STATE: OPEN_DRAFT_UNMERGED
B8: OBSERVABLE
B7: BLOCKED_BY_DEPLOYMENT_FLOOR
B4: SOURCE_NOT_FOUND
B5: SOURCE_NOT_FOUND
B9: LOCAL_ONLY_CAPABILITY_RECONCILIATION_REQUIRED
PRODUCT_CONSTRUCTION_GATE: BLOCKED
ROOT_CAUSE: UNKNOWN
```

- **FACT:** current remote `main` and PR #18 contain no tracked implementation that
  produces `target-text-observer-current.jsonl`.
- **FACT:** the retained P1-A5 worktree
  `/Volumes/Jack-Dev/Projects/remoteorbit-audio-p1-a5` is preserved with four
  local-only commits and three untracked observer files.
- **FACT:** `/Users/jack7788/Applications/RemoteOrbit P1A5 Observer.app` is preserved
  as an operationally unresolved artifact; its source/build relationship must be
  re-established locally rather than inferred from filename or byte similarity.
- **FACT:** historical incident evidence references
  `target-text-observer-current.jsonl`, but the last bounded PR #18 capture excluded
  it because its source mtime predated that runtime. Historical copies are not fresh
  evidence.
- **FACT:** repository source contains no Doubao-specific/InputMethodKit semantic
  session observer. B9 must not be mislabeled as B4/B5 external semantic
  acknowledgement.

Therefore the next B9 step is a **read-only local source/capability/privacy audit**.
It must determine whether the retained observer can establish a useful external
result/text-mutation boundary using metadata-only or content-minimizing signals, or
whether B9 must be classified as privacy/capability-unobservable.

No new observer implementation, runtime launch, Accessibility/TCC mutation, incident
capture, product change, build/install, PR #18 source change, or PR merge is
authorized by this transition.
