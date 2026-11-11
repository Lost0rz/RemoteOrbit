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

The accepted root `AGENTS.md` declares RemoteOrbit's control mode and project-specific rules. The installed Engineering Governance plugin owns general task authorization, approval, receipt, and artifact lifecycle procedures. Documents under `docs/` describe RemoteOrbit sources, designs, and evidence; they are not task authorization. The retired root `CURRENT_TASK.md` and `CURRENT_STATUS.md` remain available in Git history but have no live authority.

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

## RemoteOrbit documentation boundaries

This map identifies project-owned documents and historical evidence. It does not define task approval, verification, delivery, or documentation-maintenance workflows; those procedures belong to the installed Engineering Governance plugin.

- `AGENTS.md` contains RemoteOrbit-specific durable rules and accepted control declarations; it is not a duplicate task workflow.
- `diagnostics/ADR-*.md` retains accepted RemoteOrbit diagnostic architecture. Current implementation locations are indexed by `DOMAIN_MAP.md`.
- `incidents/` retains time-bounded forensic records. Incident evidence does not authorize current writes or revive retired RC003 voice behaviors.
- Root `RELEASE_NOTES_v*.md` describes historical releases only; published release state is in GitHub Releases.
- `DOMAIN_MAP.md` is a derived navigation aid for source, runtime, and tests, not an independent task controller or live task-status store.
- Completed one-off task plans, audits, and superseded designs are recoverable in Git history and are not treated as current project instructions.
