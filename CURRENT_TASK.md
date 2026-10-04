# RemoteOrbit Current Task

## Task identity

- **Task:** FOUNDATION GOVERNANCE — B ACTIVE; A / C CLOSED
- **Status:** AUTHORIZED
- **Task authority:** this file
- **Parallel execution:** EXPLICITLY AUTHORIZED
- **Product behavior changes:** FROZEN
- **Root cause:** UNKNOWN
- **Product Construction Gate:** BLOCKED
- **Merge:** PR #19 COMPLETED; no additional merge authorization implied
- **Release / install:** NOT AUTHORIZED

## Coordination model

Three lanes may run concurrently because they own different mutation surfaces.

| Lane | Objective | Write authority | Must not touch |
| --- | --- | --- | --- |
| A | CLOSED — A1/A2 inventory/freeze/classification accepted | none; no further A construction authority | cleanup requires a new explicit task |
| B | boundary probes + capture completeness | PR #18 diagnostic probe surface | control plane, CLI, Settings, Authority schema ownership |
| C | CLOSED — diagnostic Authority skeleton accepted and merged | none; no further C construction authority | all further diagnostic expansion requires a new task |

**Lane A is the sole control-plane writer** while these lanes are active. Lanes B/C
return verified branch/HEAD/test evidence to A; they do not independently edit
`CURRENT_STATUS.md` or `CURRENT_TASK.md`.

If a required change crosses lane ownership, STOP that lane at the boundary and
return the conflict. Do not resolve the conflict by editing another lane's files.

---

## Lane A — repository/worktree governance freeze

### Objective

Produce an authoritative, current inventory of all RemoteOrbit PRs, remote branches,
local branches, and registered/live worktrees, then freeze a lifecycle classification
for each item.

### Required evidence

On the owning Mac, read-only inventory must include at minimum:

1. `git worktree list --porcelain`;
2. local branches with upstream/ahead/behind/HEAD;
3. remote branches after fetch/prune-safe observation (fetch is allowed; deletion is
   not);
4. open/closed/merged PR state from GitHub;
5. clean/dirty/untracked state for every live worktree;
6. unique commits or unpreserved forensic evidence that block deletion.

### Classification

Use only:

- ACTIVE
- MERGED
- SUPERSEDED
- ABANDONED
- FORENSIC-RETAINED
- UNKNOWN-BLOCKED

For each retained item, record the exact reason. For each future cleanup candidate,
record why it appears removable, but **do not remove it in this task**.

### Allowed

- read-only Git/GitHub inspection;
- fetch needed to establish freshness;
- update control-plane documentation on PR #17 after evidence is verified.

### Forbidden

- no `git worktree remove`;
- no `git worktree prune`;
- no branch deletion;
- no PR close/merge;
- no reset/clean/stash/rebase/history rewrite;
- no diagnostic/product source edits;
- no runtime/install/package changes.

### Completion gate

Lane A is complete when every current PR/branch/worktree has one frozen classification
with evidence and blockers, and no cleanup deletion has been performed.

---

## Lane B — boundary probes and capture completeness

### Authority

- **PR:** #18
- **Branch:** `codex/persistent-long-boundary-probes-v1`
- **Existing purpose:** Persistent LONG HID → mapped CGEvent boundary diagnostics.

### Objective

Close only the missing evidence boundaries needed so that the next incident capture
can distinguish where the failure occurred. Favor transition-only, correlation-rich
probes over more internal log volume.

The existing diagnostic architecture/boundary map remains the reference. Lane B may
extend it only where a currently missing boundary fact requires a probe.

### Required properties

Every new probe must be:

- diagnostic-only;
- transition-only where practical;
- causally joinable to adjacent evidence;
- explicit about clock/source/runtime identity;
- bounded enough not to create a new log-volume authority problem;
- covered by the smallest focused test that proves emission/decision semantics.

### Allowed

- diagnostic probes at missing boundaries;
- correlation fields needed by the probe;
- focused diagnostic tests;
- incident capture/architecture documentation.

### Forbidden

- no product behavior fix;
- no trigger/gate ownership semantic change;
- no threshold/timing behavior change;
- no BLE/audio behavior change;
- no CLI;
- no Settings/UI exposure;
- no full diagnostic Authority/schema redesign;
- no merge/release/install.

### Completion gate

Lane B is complete when the remaining P0/P1 incident boundaries are either observable
or explicitly classified as externally unobservable with a documented reason, and the
next incident capture can discriminate adjacent hypotheses without a behavior fix.

---

## Lane C — single diagnostic Authority skeleton + unified schema

### Objective

Create the non-invasive skeleton for a single RemoteOrbit diagnostic Authority.
Define the contract first; do not wire every existing logger/probe into it yet.

### Required contract surface

At minimum define and test:

1. one versioned diagnostic event envelope;
2. event/source/runtime identity;
3. wall-clock + monotonic clock representation and documented clock semantics;
4. run/session/incident/correlation identifiers;
5. subsystem + boundary/event naming;
6. severity/class/category vocabulary sufficient for machine consumption;
7. payload/version compatibility rules;
8. a single writer/emitter interface owned by the Authority;
9. explicit ingestion/adaptation boundary for legacy producers;
10. fail-safe behavior when a producer provides invalid/incomplete diagnostic data.

The design must make it possible for a future read-only diagnostic CLI and Settings
presentation layer to consume the same Authority **without implementing either now**.

### Isolation

Create a fresh isolated branch/worktree from verified `main`. Lane C should prefer
new files under a dedicated diagnostics/authority surface plus focused contract tests
and architecture documentation.

### Allowed

- schema/types/protocols/interfaces;
- no-op or in-memory test implementation needed to validate the contract;
- focused unit/contract tests;
- architecture documentation.

### Forbidden

- no full existing-logger migration;
- no call-site-wide rewiring;
- no edits to Lane B's active probe call sites unless separately re-authorized;
- no CLI;
- no Settings/UI exposure;
- no product behavior change;
- no release/install.

### Completion gate

Lane C is complete when the Authority contract and schema compile, focused tests prove
versioning/identity/clock/correlation/fail-safe behavior, and no existing product
diagnostic producer has been forced through the new Authority yet.

### Lane C transition — skeleton/proof accepted; merge-gate validation authorized

**Status:** the C skeleton and the single opt-in WavRecorder proof are independently
audited PASS. The original completion wording above is superseded only for that one
explicitly accepted proof producer. No other producer migration is authorized.

**Authority:** PR #19 / `codex/diagnostic-authority-audit` at
`cb28bfd91e84309601b5fc2e36f9452b4a02b1d8`.

#### Final conclusion

The single Authority, schema v1, clock/correlation/provenance contract, query boundary,
failure isolation, and minimal proof are accepted for this stage. No confirmed
correctness defect was found. Remaining work is merge-gate validation only.

#### Authorized施工 scope

On the existing PR #19 line only:

1. add one deterministic **test-only** saturation/drop contract test, preferably in
   `DiagnosticAuthorityTests.swift`;
2. run `swift test` from `remote-orbit/`;
3. run `swift build -c release` from `remote-orbit/`;
4. commit/push only the test-only change to PR #19;
5. report final local/remote HEAD, clean/dirty state, full test result, release-build
   result, and stop at `WAITING_FOR_INDEPENDENT_AUDIT`.

If the saturation test exposes a production-source defect, STOP and return evidence.
This task does not authorize a corrective production patch.

#### Forbidden

- no edits to `DiagnosticAuthority.swift`, `DiagnosticEvent.swift`,
  `JSONLinesDiagnosticJournal.swift`, or `WavRecorder.swift` without a new
  corrective authorization;
- no new producer migration or `VoiceDiagnosticLogger` migration;
- no HID/EventTap/BLE/audio state-machine changes;
- no retention/rotation or streaming/read redesign;
- no CLI, Agent API, Settings/UI;
- no packaging/install/release;
- no PR #19 merge.

#### Acceptance

```text
PR19_START_HEAD: cb28bfd91e84309601b5fc2e36f9452b4a02b1d8
QUEUE_SATURATION_DROP_TEST: PASS
QUEUE_SATURATION_PRODUCER_NONBLOCKING: PASS
DROPPED_EVENT_COUNT_CONTRACT: PASS
FULL_SWIFT_TEST: PASS
RELEASE_BUILD: PASS
PRODUCTION_SOURCE_CHANGED: NO
PR19_REMOTE_SYNC: PASS
WORKING_TREE: CLEAN
FINAL_STATE: WAITING_FOR_INDEPENDENT_AUDIT
```

Passing these gates does not authorize merge. A fresh independent audit of the final
PR #19 HEAD is required before any merge transition.


### Lane C final state — merge-gate PASS / explicit merge authorization pending

**Independent audit result:** PASS at final PR #19 HEAD
`ee4effd0b6435b5198a258fa9c9f063717f69136`.

The merge-gate delta is test-only and proves the bounded-queue saturation contract.
The executor-reported full Swift suite and release build passed. No new production
source change occurred after the previously accepted C implementation audit.

Current C state:

```text
C_IMPLEMENTATION: COMPLETE
C_MERGE_GATE: PASS
C_STATE: MERGE_READY
PR19_STATE: OPEN_DRAFT_UNMERGED
MERGE_AUTHORIZATION: NOT_YET_GRANTED
```

No further C construction is authorized under this task. Do not modify PR #19 merely
to make it "more complete." Do not migrate additional producers or add retention,
CLI, Agent, Settings, or runtime behavior.

The next C transition, if explicitly authorized by the user, is limited to PR #19
merge disposition against the verified final head. Merge itself remains blocked until
that separate authorization is recorded.
---

## Global stop conditions

Stop the affected lane and return for control-plane disposition if:

- branch/HEAD/worktree authority drifts;
- two lanes need to modify the same production file or semantic owner;
- a diagnostic-only change would alter user-visible/product behavior;
- Lane B begins defining a second durable schema authority;
- Lane C requires full call-site wiring to make its contract testable;
- Lane A discovers unique evidence that makes a cleanup candidate unsafe.

## Global completion condition

This parallel phase is ready for independent audit when:

- Lane A has a frozen authoritative governance inventory;
- Lane B has a bounded probe/capture-completeness result with no behavior fix;
- Lane C has a tested Authority/schema skeleton with no broad wiring;
- all three lanes report exact branch/HEAD and validation evidence;
- the control plane remains coherent;
- Product Construction Gate remains BLOCKED pending separate authorization.


## Lane A execution checkpoint — A1 accepted / A2 authorized

### A1 disposition

**A1 STATUS: COMPLETE / ACCEPTED**

The fresh owning-Mac census has been independently reviewed against the remote
inventory. Repository, PR, branch, and worktree classifications are now frozen.

Accepted headline facts:

- 14 registered worktrees; all 14 live; 0 missing registrations;
- 11 local branches;
- 4 dirty worktrees;
- 3 worktrees with 9 untracked evidence files;
- six distinct local-only commit SHAs require preservation;
- two clean superseded worktrees are cleanup candidates only;
- no unknown classification remains;
- no destructive cleanup was performed.

The stale local control checkout is a known freshness condition. It is not the task
authority and must not be used to author control-plane changes until updated in a
separately authorized synchronization action.

### Current A-line task

**A2 — NON-WORKTREE ARTIFACT INVENTORY AND CLASSIFICATION**

Purpose: complete the governance picture outside Git worktrees before any cleanup
decision is considered.

This task is **read-only**.

#### Scope

Inventory RemoteOrbit-related non-worktree assets in bounded project/archive
locations, including archive/backup directories, preservation patches, release/DMG
artifacts, incident captures, observer/build artifacts, and other RemoteOrbit-owned
filesystem evidence not already represented by a registered worktree.

Do not recursively inventory unrelated user data or system/cache directories.

#### Required evidence per artifact/group

Record enough to decide preservation without mutation:

- exact path;
- file/directory type;
- size and item count where useful;
- obvious artifact class/purpose;
- modification timestamp;
- whether it is inside a registered worktree;
- whether equivalent content is preserved by Git, a live worktree, release asset,
  another archive, or another named path when this can be proven;
- preservation value / blocker;
- proposed classification.

Use only these A2 classifications:

- ACTIVE
- FORENSIC-RETAINED
- RELEASE-RETAINED
- DUPLICATE-CANDIDATE
- SUPERSEDED-CANDIDATE
- UNKNOWN-BLOCKED

#### Acceptance

A2 is complete when the bounded non-worktree RemoteOrbit filesystem surface is
enumerated, every artifact/group has one evidence-backed classification, unique
forensic/release evidence is protected, duplicate claims identify the preserved
copy, and no mutation has occurred.

#### Construction gate

**OPEN for read-only A2 inventory only.**

Still forbidden:

- file/directory deletion or move;
- worktree remove/prune;
- branch deletion;
- PR mutation;
- reset/clean/stash/rebase;
- source or diagnostic edits;
- build/install/package/runtime mutation;
- control-plane edits from the local agent.

Return the complete inventory and classifications for independent web audit. A
separate control-plane transition is required before any cleanup action.



## Lane C merge execution authorization

The user explicitly authorized merging PR #19 and closing Lane C.

Execute only if freshness remains exact:

```text
PR19_EXPECTED_HEAD: ee4effd0b6435b5198a258fa9c9f063717f69136
MAIN_EXPECTED_PREMERGE: 7129ef72949eca956b1d0daddce707d5e417eeed
C_MERGE_GATE: PASS
```

Allowed: mark PR #19 ready for review if GitHub requires it; merge PR #19 using the
verified head; verify merged PR and new main HEAD; then write a same-commit
CURRENT_STATUS/CURRENT_TASK closure transition marking C CLOSED.

Forbidden: any source amendment, producer migration, release/install, A2 cleanup, or
other PR mutation.


## Lane A final state — A1/A2 complete

**Lane A inventory/freeze/classification scope is complete.**

A1 repository/worktree census: ACCEPTED.
A2 non-worktree artifact inventory: ACCEPTED.

Final A2 count:

```text
NON_WORKTREE_ARTIFACT_GROUPS: 20
RELEASE_RETAINED: 1
FORENSIC_RETAINED: 10
DUPLICATE_CANDIDATE: 1
SUPERSEDED_CANDIDATE: 0
UNKNOWN_BLOCKED: 8
```

The only A2 duplicate candidate is the Flight Recorder source-preservation patch, whose content is byte-for-byte preserved by the retained local Flight Recorder commit `01eedda...`.

The P1A5 Observer app is not cleanup-authorized despite an exact bundle copy in a retained worktree because active operational use was not checked. The five zero-byte files are not treated as interchangeable cleanup duplicates because their filename/timestamp context may carry separate evidence.

**No further Lane A construction is authorized under this task.**

The next A transition, if explicitly authorized by the user, must be a separate cleanup/disposition task. Before that task can authorize deletion it must refresh the live PR/remote-branch/worktree inventory, including current B and C heads, and define the exact deletion set with preservation evidence.

Until then all destructive cleanup gates remain BLOCKED.

## Lane C closure

**C STATUS: CLOSED**

PR #19 was merged into `main` as
`5def97bac0f8d4e2896cbb0ee0ee56d0810aff2d` from the exact audited source head
`ee4effd0b6435b5198a258fa9c9f063717f69136`.

No further work is authorized on Lane C under this task. Do not continue producer
migration, retention/rotation, CLI, Agent API, Settings/UI, or journal redesign under
the closed C line. Any such work requires a separately authorized future task.

Lane A is also complete under its accepted A1/A2 scope. Lane B remains the only
active construction/investigation lane under this foundation task.
