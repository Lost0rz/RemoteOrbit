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

## Retired historical document locations

Completed or superseded design and investigation materials remain recoverable through Git history, rather than serving as current RemoteOrbit architecture:

- `docs/design/` task 043/045 audit, corrective and retirement plans;
- `docs/superpowers/` historical plans/specs, including dual-receiver and old voice-pipeline plans;
- `remote-orbit/docs/superpowers/plans/2026-09-24-post-release-capture-grace.md` — legacy P1-A9 execution plan with a retired external Skill requirement;
- `docs/incident-diagnostics/PERSISTENT_LONG_DIAGNOSTIC_ARCHITECTURE.md`;
- `docs/diagnostics/2026-10-28-task-038-b-audio-continuity-closeout.md`.

Their history remains recoverable from Git. Deletion from the current tree means **“not a current navigation/design authority”**, not “the historical work never existed.”

