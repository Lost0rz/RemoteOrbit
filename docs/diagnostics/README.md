# Diagnostic Architecture

The ADRs in this directory are the retained durable design authority for RemoteOrbit diagnostics.

- `ADR-0001-single-diagnostic-authority.md` — one machine-readable diagnostic authority and schema ownership.
- `ADR-0002-read-only-diagnostic-cli.md` — CLI is a read-only adapter over that authority.
- `ADR-0003-long-term-observability.md` — gated L1/L2 voice observability, retention and export boundaries.

Current implementation routes are indexed in `../DOMAIN_MAP.md`.

Task-specific diagnostic closeouts, audit diaries and corrective plans are not retained here after their durable conclusions have been incorporated into ADRs/source/tests. Use Git history for those artifacts.