# RemoteOrbit Current Task

## Task identity

- **Task:** FOUNDATION GOVERNANCE — A3 TARGETED FRESHNESS REFRESH; B3 ACCEPTED; C CLOSED
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
| A | A3 targeted freshness refresh over accepted A3 evidence | owning-Mac delta evidence + control-plane evidence checkpoint only | no deletion/prune/move/PR mutation/runtime or product-source change |
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


## Lane B transition — B2 main reconciliation authorized

**Status:** AUTHORIZED — reconciliation only.

**Authority anchors**

```text
B_EXPECTED_START_HEAD: ca35022be6cea6262d971ef0aedaa5550324004f
MAIN_EXPECTED_HEAD: 5def97bac0f8d4e2896cbb0ee0ee56d0810aff2d
PR: #18
BRANCH: codex/persistent-long-boundary-probes-v1
```

The next local action is limited to integrating the exact current `origin/main` into
the existing PR #18 branch without rewriting B history or changing probe semantics.

### Required execution

1. Revalidate repository remote identity, exact PR #18 worktree/branch, expected B
   HEAD, exact fetched `origin/main`, and clean worktree.
2. Merge `origin/main` into the B branch. Do not rebase or force-push.
3. If any merge conflict occurs, STOP without resolving it and return the conflict.
4. Prove the six existing PR #18 changed paths are unchanged relative to
   `ca35022...`; reconciliation should only add the accepted C/main tree.
5. Run focused B diagnostics:
   `HIDMonitorDiagnosticsTests`, `VoiceBoundaryDiagnosticsTests`,
   `VoiceInputSourceDiagnosticsTests`.
6. Run focused C diagnostics:
   `DiagnosticAuthorityTests`, `WavRecorderDiagnosticsTests`.
7. Run full `swift test` and `swift build -c release` from `remote-orbit/`.
8. Push the merge commit normally, verify remote branch HEAD equality and clean final
   worktree, then STOP at `WAITING_FOR_INDEPENDENT_AUDIT`.

### Acceptance

```text
B2_PRECHECK: PASS
B2_MAIN_HEAD_MATCH: PASS
B2_MERGE_CONFLICT: NONE
B2_B_PROBE_PATHS_PRESERVED: PASS
B2_FOCUSED_B_TESTS: PASS
B2_FOCUSED_C_TESTS: PASS
B2_FULL_SWIFT_TEST: PASS
B2_RELEASE_BUILD: PASS
B2_REMOTE_SYNC: PASS
B2_FINAL_WORKTREE: CLEAN
FINAL_STATE: WAITING_FOR_INDEPENDENT_AUDIT
```

### Still forbidden

No probe expansion, Authority migration, behavior fix, threshold/timing change,
install, runtime replacement, fresh incident capture, PR #18 merge, release, or
control-plane edits from Lane B.


## Lane A3 — refreshed cleanup-disposition audit

**Status:** AUTHORIZED — READ-ONLY AUDIT ONLY.

A1/A2 proved inventory/freeze/classification at their audit times. Since then PR #19
merged into `main`, B advanced, and the merged C source branch remains present.
Those facts require a fresh disposition audit before any deletion decision.

### Scope

Refresh and reconcile:

- all registered/live/missing RemoteOrbit worktrees on the owning Mac;
- all RemoteOrbit local branches and upstream/ahead/behind/reachability state;
- all current remote branches and open/merged PR relationships;
- dirty/untracked/local-only evidence in every live worktree;
- the same bounded A2 roots:
  - `/Volumes/Jack-Dev/Projects`
  - `/Users/jack7788/Documents/Code` (deduplicate symlink-equivalent content)
  - `/private/tmp`
  - `/Users/jack7788/Applications`
- the prior 20 non-worktree artifact groups plus any new or changed
  RemoteOrbit-owned groups;
- operational-use uncertainty for app/observer/runtime artifacts;
- exact preservation source for every proposed stale/duplicate cleanup candidate.

### Required final classifications

Use only:

- `KEEP_ACTIVE`
- `KEEP_FORENSIC`
- `KEEP_RELEASE`
- `SAFE_DELETE_CANDIDATE`
- `UNKNOWN_BLOCKED`

A worktree or branch may be `SAFE_DELETE_CANDIDATE` only when it has no dirty or
untracked evidence, no unique local-only history, no active task/PR authority, and no
unpreserved forensic/runtime dependency.

### Acceptance output

Return:

```text
A3_FRESHNESS_GATE
REMOTE_MAIN
CONTROL_HEAD
OPEN_PRS
REMOTE_BRANCHES
REGISTERED_WORKTREE_COUNT
LIVE_WORKTREE_COUNT
MISSING_REGISTRATION_COUNT
DIRTY_WORKTREE_COUNT
UNTRACKED_EVIDENCE_COUNT
LOCAL_ONLY_COMMIT_SET
WORKTREE_DISPOSITION_TABLE
LOCAL_BRANCH_DISPOSITION_TABLE
REMOTE_BRANCH_DISPOSITION_TABLE
NON_WORKTREE_ARTIFACT_GROUP_COUNT
ARTIFACT_DISPOSITION_TABLE
EXACT_PROPOSED_CLEANUP_MANIFEST
UNKNOWN_BLOCKERS
DESTRUCTIVE_CLEANUP_GATE = BLOCKED
FINAL_STATE = READY_FOR_INDEPENDENT_WEB_AUDIT
```

The local executor may write verified A3 evidence to `CURRENT_STATUS.md` and
`CURRENT_TASK.md` **together in one commit** on the control branch, but may set only
`READY_FOR_INDEPENDENT_WEB_AUDIT`. It may not set cleanup PASS or authorize deletion.

### Freshness / stop rules

- If control HEAD changes after the local audit starts, STOP and reconcile.
- If `main`, PR #18, the open PR set, or remote branch set changes during the audit,
  restart the freshness snapshot before classifying affected candidates.
- A B2 merge/reconciliation advancement is not an A3 failure by itself, but A3 may not
  reuse a pre-B2 snapshot to authorize a candidate.
- If any candidate has dirty/untracked content, unproven local-only history, uncertain
  operational use, or unresolved forensic context, classify it `UNKNOWN_BLOCKED`.
- If a required scan root is unavailable, STOP with the missing evidence.

No destructive cleanup is authorized by this task.


## Lane B transition — B3 external-boundary probe construction authorized

**Status:** AUTHORIZED — bounded B7/B8 diagnostic construction only.

### Authority anchors

```text
B3_EXPECTED_START_HEAD: a71ce1d48c08bda1ad86bcd5c3a75a5e5ed90353
MAIN_BASELINE: 5def97bac0f8d4e2896cbb0ee0ee56d0810aff2d
PR: #18
BRANCH: codex/persistent-long-boundary-probes-v1
C_LINE: CLOSED
DIAGNOSTIC_AUTHORITY_BASELINE: ACCEPTED_ON_MAIN
```

B2 reconciliation is independently accepted. B may now consume the merged
DiagnosticAuthority as infrastructure.

### Authorized objective

Implement only:

1. **B8 frontmost-application transition probe** using an independent
   `NSWorkspace.frontmostApplication` observation path, transition-only and without
   high-frequency polling;
2. **B7 target-process input-consumer transition probe** using read-only CoreAudio
   process/input state if and only if the implementation is safe for the repository's
   macOS 13 deployment target.

Both probes must emit through the accepted `DiagnosticAuthority`. No direct JSONL
writer is allowed.

### Narrow catalog exception

For this B3 task only, Lane B may edit
`Sources/RemoteOrbit/Diagnostics/DiagnosticEvent.swift` solely to:

- register the minimum closed-catalog event definitions required by B7/B8; and
- add only the minimum payload value kinds required for those exact event payloads.

This exception **does not** authorize a schema redesign and does not reopen Lane C.

Still forbidden in the Authority surface:

- schema-version change;
- envelope-field change;
- canonical clock change;
- runtime/provenance contract change;
- `DiagnosticAuthorityService` queue/emission mechanics;
- journal path/format/append behavior;
- query/filter/pagination/snapshot behavior;
- retention/rotation;
- generic/extensible schema engines.

If B7/B8 cannot be represented without one of those changes, STOP and return the
cross-boundary blocker.

### B8 contract

Required fact:

> actual frontmost application identity changed.

Use a separate observer component. Notification/KVO may trigger re-observation, but
the emitted fact must be based on the observed `frontmostApplication` state.

Requirements:

- transition-only;
- no high-frequency polling;
- initial state establishes baseline but emits no change event;
- repeated same identity emits nothing;
- payload is limited to stable process/application identity needed for diagnosis;
- no window title or user content.

### B7 contract

Required fact:

> a target process changed input-consumer running state.

Before implementation, verify the exact CoreAudio API/header availability against the
macOS 13 deployment target.

Requirements:

- read-only;
- no PCM/audio tap;
- no default-device mutation;
- no CoreAudio restart;
- no driver/install;
- no global high-frequency process polling;
- no claim of device switching unless the API semantics directly prove it;
- if safe target correlation cannot be established without changing product behavior,
  classify target correlation as PARTIAL rather than logging all system clients.

If the required CoreAudio observation is unavailable under the current deployment
contract, B7 may stop as `BLOCKED_BY_AVAILABILITY` while B8 proceeds.

### Explicit non-targets

```text
B4_EXTERNAL_ACCEPTANCE: SOURCE_NOT_FOUND — DO NOT IMPLEMENT
B5_EXTERNAL_SESSION_STATE: SOURCE_NOT_FOUND — DO NOT IMPLEMENT
B9_TARGET_TEXT: DEFERRED — DO NOT IMPLEMENT
```

Do not substitute internal dispatch, Persistent state, frontmost state, audio state,
or text mutation for B4/B5 semantic acknowledgement.

### Runtime and behavior isolation

Prefer the existing diagnostics-only runtime gate when practical. New observers must
not become dependencies of voice, HID, Option ownership, BLE, audio routing, focus
control, or recovery behavior.

No Settings, CLI, Agent API, install, runtime replacement, fresh incident capture,
product fix, threshold/timing change, or PR #18 merge is authorized.

### Required tests

B8 focused tests must prove at minimum:

- initial baseline emits nothing;
- A→B emits exactly once;
- B→B emits nothing;
- B→C emits exactly once;
- process/application identity is preserved;
- invalid catalog payloads fail closed.

If B7 is implemented, focused tests must prove at minimum:

- inactive→active emits once;
- same-state repetition emits nothing;
- active→inactive emits once;
- unrelated process/state is ignored by the target filter;
- listener teardown does not fabricate a transition;
- invalid event payload/type fails closed.

No wall-clock sleeps should be required for deterministic unit tests.

### Validation

Run:

- existing PR #18 B diagnostics;
- new B7/B8 focused tests;
- `DiagnosticAuthorityTests`;
- `WavRecorderDiagnosticsTests`;
- full `swift test`;
- `swift build -c release`;
- `git diff --check`.

Final audit report must explicitly state:

```text
B3_START_HEAD
B3_FINAL_HEAD
REMOTE_HEAD
WORKTREE_CLEAN
CATALOG_ONLY_EXCEPTION_SCOPE
AUTHORITY_MECHANICS_CHANGED
B7_MACOS13_AVAILABILITY
B7_TARGET_CORRELATION
B7_INPUT_RUNNING_TRANSITION
B7_DEVICE_TRANSITION
B8_FRONTMOST_TRANSITION
B8_POLLING_USED
B4_EXTERNAL_ACCEPTANCE
B5_EXTERNAL_SESSION_STATE
B9_STATUS
DIRECT_JSONL_WRITER_ADDED
VOICE_BEHAVIOR_CHANGED
HID_BEHAVIOR_CHANGED
OPTION_GATE_CHANGED
BLE_AUDIO_BEHAVIOR_CHANGED
FOCUSED_TESTS
AUTHORITY_TESTS
FULL_SWIFT_TEST
RELEASE_BUILD
DIFF_CHECK
FINAL_STATE = WAITING_FOR_INDEPENDENT_AUDIT
```

Commit/push normally to PR #18 and stop at independent audit. Do not merge PR #18.


## Lane B B3 final state — accepted; next gate not yet authorized

**B3 STATUS: COMPLETE / ACCEPTED**

Accepted remote head:

```text
PR18_HEAD: 71ef0e65117f2def4e30d5447ca55246c4d18434
B8: OBSERVABLE
B7: BLOCKED_BY_DEPLOYMENT_FLOOR
B4: SOURCE_NOT_FOUND
B5: SOURCE_NOT_FOUND
B9: DEFERRED
PRODUCT_CONSTRUCTION_GATE: BLOCKED
ROOT_CAUSE: UNKNOWN
```

No further B7/B8 construction is authorized under the completed B3 task. Do not add
polling, alternative CoreAudio fallbacks, raise the deployment target, widen the
DiagnosticAuthority schema, install/relaunch a diagnostic runtime, perform a fresh
incident capture, merge PR #18, or begin a product fix.

The next candidate B transition is a **separate B9 capability/privacy audit**. It is
not authorized yet. If later authorized, it must first reconcile the existing
target-text observer/source/capability and determine whether a metadata-only,
content-minimizing observation can establish a useful external result boundary. It
must not assume permission to record target text, transcript content, window titles,
or other user content.

Until that separate transition is authorized, Lane B remains stopped after B3 at an
independently accepted diagnostic state.


## Lane A3 transition — targeted freshness refresh

**Status:** AUTHORIZED — DELTA EVIDENCE ONLY.

The previous A3 result is not discarded. Its evidence body remains the baseline.
The only confirmed reason it cannot yet reach independent cleanup review is freshness:
PR #18 advanced from `a71ce1d...` to accepted B3 head `71ef0e6...`.

### Do not repeat

Do not repeat the full A3 scan, full artifact hashing, full forensic classification,
or broad recursive filesystem search unless a delta check identifies a material
change.

In particular, do not use generic recursive `find` across unrelated `/private/tmp`
content. Inspect only named prior RemoteOrbit artifact paths plus newly discovered
paths whose names/locations clearly establish RemoteOrbit ownership.

### Required delta evidence

Produce one compact freshness package containing:

```text
A3_REFRESH_START_CONTROL_HEAD
A3_REFRESH_FINAL_CONTROL_HEAD
REMOTE_MAIN
OPEN_PRS
PR17_HEAD
PR18_HEAD
REMOTE_BRANCH_SET
REGISTERED_WORKTREE_COUNT
LIVE_WORKTREE_COUNT
MISSING_REGISTRATION_COUNT

CANDIDATE_WORKTREE_REFRESH
  /private/tmp/remoteorbit-c-diagnostic-authority-audit
  /private/tmp/remoteorbit-cross-mode-flight-recorder-minimal
  /private/tmp/remoteorbit-pr18-corrective-controls
  /Volumes/Jack-Dev/Projects/remoteorbit-pr18-validation

CANDIDATE_LOCAL_BRANCH_REFRESH
  codex/diagnostic-authority-audit
  codex/cross-mode-flight-recorder-minimal

CANDIDATE_REMOTE_BRANCH_REFRESH
  codex/diagnostic-authority-audit

FLIGHT_RECORDER_PRESERVATION
PR18_VALIDATION_DEPENDENCY_STATUS
PRIOR_ARTIFACT_GROUPS_METADATA_CHANGED
NEW_REMOTEORBIT_ARTIFACT_GROUPS
REVISED_EXACT_CLEANUP_MANIFEST
UNKNOWN_BLOCKERS
A3_TARGETED_REFRESH_GATE
DESTRUCTIVE_CLEANUP_GATE = BLOCKED
FINAL_STATE
```

For each candidate worktree, report current HEAD/branch-or-detached state,
clean/dirty/untracked state, local-only commit status, and exact preservation source.

For the prior twenty artifact groups, a path/existence/size/mtime/count comparison is
enough when unchanged. Re-hash or deeply inspect only changed groups.

### Freshness rule

Before writing back, re-read live:

- remote `main`;
- control branch;
- PR #17 and #18 state/head;
- remote branch set.

If any differs from the snapshot used to produce the manifest, reconcile the affected
delta before setting final state.

If all delta evidence passes, write the verified result to
`CURRENT_STATUS.md` and `CURRENT_TASK.md` together in one direct-child commit and
set only:

`FINAL_STATE = READY_FOR_INDEPENDENT_WEB_AUDIT`

Do **not** set destructive cleanup PASS. Do not delete or prune anything.

If any candidate becomes dirty, gains untracked/local-only evidence, loses its
preserved copy, is actively required by the current task, or cannot be proven safe,
set that item to `UNKNOWN_BLOCKED` and return the evidence.


## Lane B transition — B9 read-only capability/privacy audit authorized

**Status:** AUTHORIZED — READ-ONLY AUDIT ONLY.

### Authority anchors

```text
B9_CONTROL_AUTHORITY_PARENT: 36985064e5cc2b64bed608bc7708b7949a2500b5
PR18_EXPECTED_HEAD: 71ef0e65117f2def4e30d5447ca55246c4d18434
MAIN_EXPECTED_HEAD: 5def97bac0f8d4e2896cbb0ee0ee56d0810aff2d
PRODUCT_CONSTRUCTION_GATE: BLOCKED
FRESH_CAPTURE: NOT AUTHORIZED
PR18_MERGE: NOT AUTHORIZED
```

### Audit objective

Reconcile the existing local-only target-text/P1-A5 observer and decide one of:

- `B9_OBSERVABLE_METADATA_ONLY`
- `B9_PARTIAL_METADATA_ONLY`
- `B9_BLOCKED_BY_CAPABILITY`
- `B9_BLOCKED_BY_PRIVACY`
- `B9_SOURCE_NOT_RECOVERED`

This audit does **not** authorize B9 implementation.

### Required local evidence

Start with a fresh read-only control/repository snapshot, then inspect:

1. `/Volumes/Jack-Dev/Projects/remoteorbit-audio-p1-a5`;
2. its four local-only commits and three untracked observer files;
3. `/Users/jack7788/Applications/RemoteOrbit P1A5 Observer.app`;
4. any source/config/binary metadata that can be proven to produce
   `target-text-observer-current.jsonl`;
5. existing target-text observer JSONL schema/field names and timestamp/correlation
   model, if that file still exists;
6. relevant Accessibility/AX APIs and target-application boundary used by the
   observer.

For source, app, config, and artifact, record exact path, identity/hash where useful,
source HEAD or local-only commit relationship, bundle/process identity, and whether
the relationship is proven or inferred.

### Privacy boundary

The audit report and control-plane writeback must **not include** target text,
transcript/dictation contents, window titles, clipboard contents, user-entered field
values, or screenshots containing user content.

If existing files contain user content, inspect only what is necessary locally to
identify schema/capability. Report only field names, types, event counts, lengths,
hashes, booleans, transition classes, timestamps, process/bundle identity, error
codes, and capability conclusions. Do not copy content values into Git, chat, test
fixtures, or new artifacts.

### Capability questions

Answer from direct evidence:

1. What exact external boundary does the observer read?
2. Does it observe the target process directly or only RemoteOrbit state?
3. What API/permission is required?
4. Can it distinguish no-change, value-change, element-change, process/focus-change?
5. Can it distinguish IME semantic session OPEN/STOP? If not, explicitly NO.
6. What timestamp model and stable process/bundle identity are available?
7. What correlation keys can join PR #18/B8 evidence?
8. Can the same diagnostic fact be emitted without storing actual text content?
9. What failure modes exist: AX error, unsupported role/value, secure field,
   permission loss, process restart, missing focused element, stale observer, etc.?
10. Does historical `target-text-observer-current.jsonl` prove current runtime
    capability? Historical/stale files must answer NO unless current source/runtime
    identity is independently established.

### Required classification

Return:

```text
B9_CONTROL_HEAD_START
PR18_HEAD_VERIFIED
P1A5_WORKTREE_PATH
P1A5_HEAD
LOCAL_ONLY_COMMITS
UNTRACKED_OBSERVER_FILES
OBSERVER_APP_PATH
OBSERVER_BUNDLE_ID
OBSERVER_BINARY_HASH
OBSERVER_SOURCE_PROVENANCE
TARGET_TEXT_JSONL_FOUND
TARGET_TEXT_JSONL_FRESHNESS
TARGET_TEXT_SCHEMA
CONTENT_VALUES_EXPORTED = NO
OBSERVED_EXTERNAL_BOUNDARY
TARGET_PROCESS_DIRECTLY_OBSERVED
REQUIRED_PERMISSION
AX_ERROR_BEHAVIOR
VALUE_CHANGE_OBSERVABLE
ELEMENT_CHANGE_OBSERVABLE
PROCESS_FOCUS_CHANGE_OBSERVABLE
IME_SEMANTIC_OPEN_STOP_OBSERVABLE
TIMESTAMP_MODEL
CORRELATION_MODEL
METADATA_ONLY_POSSIBLE
B9_CLASSIFICATION
B9_PROVES
B9_DOES_NOT_PROVE
NEW_PROBE_REQUIRED
PRIVACY_RISK
PRODUCT_SOURCE_CHANGED = NO
RUNTIME_CHANGED = NO
TCC_CHANGED = NO
FRESH_CAPTURE_PERFORMED = NO
FINAL_STATE = READY_FOR_INDEPENDENT_WEB_AUDIT
```

### Stop conditions

STOP without workaround if:

- control authority/PR #18/main freshness materially changes;
- the P1-A5 worktree or observer source is missing;
- source-to-app/artifact provenance cannot be established;
- inspecting capability would require launching/replacing the observer or changing
  TCC/Accessibility permission;
- the only way to prove B9 would require exporting actual user content;
- the observer is actually a B4/B5 semantic-session observer; do not silently
  reclassify boundaries.

### Allowed

Read-only Git/file/source/bundle inspection; hashes and code-signing/bundle metadata
reads; read-only inspection of existing logs/artifacts under the privacy restrictions;
static API/header/documentation inspection; same-commit
`CURRENT_STATUS.md` + `CURRENT_TASK.md` evidence checkpoint after completion,
setting only `READY_FOR_INDEPENDENT_WEB_AUDIT`.

### Forbidden

No product/probe source edits; no new DiagnosticAuthority event; no observer launch;
no app install/rebuild; no TCC/Accessibility changes; no new capture; no synthetic
input; no target-app automation; no PR #18 commit; no merge; no cleanup/deletion.

A later B9 implementation or B-line closeout requires a separate independent web
audit and explicit transition.
