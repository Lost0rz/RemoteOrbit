# RemoteOrbit Documentation Map

This directory contains only documentation that still has a clear current or historical role. Git history is the archive for completed task plans and superseded design artifacts.

## Current documentation

| Document | Role | Authority class |
| --- | --- | --- |
| `../README.md` | Current product/repository landing page | current guidance |
| `../SETUP_NOTES.md` | Current install, validation and troubleshooting guide | current guidance |
| `DOMAIN_MAP.md` | Domain/capability → source/runtime/test navigation | derived projection |
| `diagnostics/ADR-0001-single-diagnostic-authority.md` | Durable diagnostic authority decision | design authority |
| `diagnostics/ADR-0002-read-only-diagnostic-cli.md` | Durable read-only CLI boundary | design authority |
| `diagnostics/ADR-0003-long-term-observability.md` | Durable long-term observability decision | design authority |

`AGENTS.md` owns only durable RemoteOrbit-specific product and runtime constraints. The installed Engineering Governance plugin and its global policy own reusable control-mode selection, task authorization, approvals, Issue handling, audit, verification and delivery. No document in `docs/` defines an alternative workflow. The legacy root `CURRENT_TASK.md` and `CURRENT_STATUS.md` remain retired from active authority; their prior contents remain in Git history.

## Historical evidence

### `incidents/`

Incident files are time-bounded evidence. They may mention old branches, tasks, Persistent mode, dual Receiver behavior, local microphone capture, experimental probes or earlier runtime designs. Those statements describe the captured incident and must not be promoted to current product/design authority.

See `incidents/README.md` before using an old incident as evidence.

### Root `RELEASE_NOTES_v*.md`

Release notes describe the behavior of the named historical release. They are intentionally not rewritten when the product contract later changes. In particular, a release note that mentions dual Receiver or other retired behavior is evidence about that old release, not the current `main` contract.

Published release state lives in GitHub Releases. Current source version metadata lives in `remote-orbit/Packaging/Info.plist`.

## Removed from the active documentation tree on 2026-11-01

The following classes were removed because they were completed task artifacts, superseded business designs, duplicated planning surfaces or frozen diagnostic architecture that could be mistaken for current authority:

- `docs/design/` task 043/045 audit, corrective and retirement plans;
- `docs/superpowers/` historical plans/specs, including dual-receiver and old voice-pipeline plans;
- `docs/incident-diagnostics/PERSISTENT_LONG_DIAGNOSTIC_ARCHITECTURE.md`;
- `docs/diagnostics/2026-10-28-task-038-b-audio-continuity-closeout.md`.

Their history remains recoverable from Git. Deletion from the current tree means **“not a current navigation/design authority”**, not “the historical work never existed.”

## Authoring rules

1. Put durable **RemoteOrbit-specific** product, hardware, runtime and data-safety MUST/MUST-NOT rules in `AGENTS.md`; do not copy reusable engineering workflow or permission declarations there.
2. Do not prescribe generic task authorization, Issue approval, PR lifecycle or audit procedures in repository documentation. Those belong to the installed Engineering Governance plugin; current PR, CI, commit and release facts remain in their GitHub records.
3. Add a durable design/ADR only when future tasks genuinely need the decision after the current task ends.
4. Completed task plans, audit diaries, branch/PR progress logs and one-off corrective cards should normally disappear from the active documentation tree after their durable conclusions have moved to the correct owner.
5. Preserve incident evidence when it has unique forensic value, but label it historical and never let it override current authority.
6. Keep release notes version-specific; do not rewrite old releases to match current product semantics.
7. `DOMAIN_MAP.md` is navigation only. Refresh affected routes from current source/tests when ownership or paths change; do not copy task status into it.
