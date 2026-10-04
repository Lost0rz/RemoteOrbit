# RemoteOrbit Current Task

## Task identity

- **Task:** FOUNDATION GOVERNANCE — PARALLEL LANES A / B / C
- **Status:** AUTHORIZED
- **Task authority:** this file
- **Parallel execution:** EXPLICITLY AUTHORIZED
- **Product behavior changes:** FROZEN
- **Root cause:** UNKNOWN
- **Product Construction Gate:** BLOCKED
- **Merge / release / install:** NOT AUTHORIZED

## Coordination model

Three lanes may run concurrently because they own different mutation surfaces.

| Lane | Objective | Write authority | Must not touch |
| --- | --- | --- | --- |
| A | repository/worktree governance inventory + freeze/classification | control-plane docs only | diagnostic/product source |
| B | boundary probes + capture completeness | PR #18 diagnostic probe surface | control plane, CLI, Settings, Authority schema ownership |
| C | single diagnostic Authority skeleton + unified schema/interface | new isolated Authority/schema files + focused tests/docs | control plane, PR #18 probe call sites, CLI, Settings, product behavior |

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


## Lane A execution checkpoint — remote census complete

### Completed

The fresh remote read-only census is complete and frozen in `CURRENT_STATUS.md`.

Remote classification result:

- PRs: ACTIVE 2 / MERGED 11 / SUPERSEDED 4 / ABANDONED 1.
- Remote branches: 5 total.
- Active branches: `main`, control-plane #17, boundary-probe #18.
- Evidence-retained branches: `codex/persistent-duplicate-audio-forensics`,
  `codex/voice-single-owner-session`.
- No remote deletion/close/merge mutation was performed.

### Current A-line gate

**WAITING FOR FRESH OWNING-MAC CENSUS**

The next authorized A-line action is read-only local inventory only. Revalidate the
current worktree and local-branch state from the owning Mac. Do not reuse the
historical 10-worktree snapshot as current truth.

Required result must report, for every registered worktree:

`PATH | EXISTS | HEAD | BRANCH/DETACHED | CLEAN/DIRTY | TRACKED MODS | UNTRACKED |
UPSTREAM | AHEAD/BEHIND | UNIQUE LOCAL COMMITS | CLASSIFICATION CANDIDATE | RETAIN
REASON/BLOCKER`

Also report all local branches not attached to a worktree, with upstream,
ahead/behind, merge-base/reachability or unique-commit evidence sufficient to decide
whether the branch is preserved elsewhere.

### Still forbidden

No worktree remove/prune, branch delete, PR mutation, reset/clean/stash/rebase,
diagnostic/product source edit, install, package, or runtime mutation.
