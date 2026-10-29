# RemoteOrbit Current Task

## RO-OBSERVABILITY-039 — Long-Term Production-Safe Observability

Status: `AIR_VALIDATION_ACTIVE / OWNER_NATURAL_USE`

Repository: `Lost0rz/RemoteOrbit`
Canonical repository: `/Volumes/Jack-Dev/Projects/remoteorbit`
Active branch: `codex/observability-039`

## Objective

Use the independently audited production-safe observability build during ordinary MacBook Air use, then export bounded structured diagnostics that can distinguish where real omission/stall/latency incidents arise before any further audio corrective is authorized.

## Current authority

- Semantic implementation HEAD: `62d58765c6a0bffbd7853861eae50cdf094bb586`.
- Packaged candidate source/control HEAD: `bc5a7c19b212d18d4fd67184e8ed7fbb94dabe74`.
- Candidate DMG: `/private/tmp/remoteorbit-air-validation-20261029-export-recency/RemoteOrbit-0.2.14-AIR-VALIDATION-EXPORT-RECENCY.dmg`.
- DMG SHA-256: `4887595e28ea4aacf9fa567c73d3bb46be2b70c647f7ce51e9565f7c9b935e72`.
- Executable SHA-256: `958d9db4d126b43b2afe00df8e209eb83563e6442e86acb81d8ef4a5a74ea670`.
- Embedded source revision: `bc5a7c19b212d18d4fd67184e8ed7fbb94dabe74`.
- App version/build: `0.2.14 (43)`; architectures: `x86_64 arm64`.
- Independent Web audit: `PASS` for observability plus exporter and export-recency correctives.
- PR #25 remains `OPEN / DRAFT / UNMERGED`; this task does not authorize merge/tag/release.

## Verification gate

- Focused exporter tests: `10/10 PASS`.
- Release build: `PASS`.
- x86 build: `PASS`.
- Protocol self-tests: `3/3 PASS`.
- `git diff --check`: `PASS`.
- DMG provenance/content/signature/architecture checks: `PASS`.
- Packaging run historical caveat: one failure in `VoicePersistentSessionTests.testPersistentSessionAcceptsMultipleAudioOnlySegmentsThenClosesByTap` after a fixed 0.85-second timing wait.
- Follow-up exact-candidate verification: target test `30/30 PASS`; one full Swift suite `471/471 PASS`; no source/test/DMG/runtime changes.
- Classification: `CONSISTENT_WITH_ONE_OFF_TIMING_FLAKE`; current Air validation is not blocked by that historical single failure.

## Active validation workflow

1. Run the packaged candidate naturally on the MacBook Air.
2. Do not enable special continuity environment variables, artificial jitter, ATVV A/B, debug launch flags, or speculative audio changes.
3. Preserve existing logs/evidence; do not clear or rotate them manually merely to make export succeed.
4. Use normal SHORT, LONG, and Persistent flows.
5. If a visible omission, text-update stall, trigger delay, or persistent-session anomaly occurs, keep using the app naturally unless the product becomes unusable; do not immediately restart or change configuration solely to clean the incident.
6. After enough samples accumulate, export a recent bounded diagnostics window and provide the resulting archive for independent Web analysis.

### Air diagnostics export

```bash
OUTPUT_DIR="$HOME/Desktop/RemoteOrbit-diagnostics-$(date +%Y%m%d-%H%M%S)"
END_MS=$(( $(date +%s) * 1000 ))
START_MS=$(( END_MS - 3 * 60 * 60 * 1000 ))
mkdir -p "$OUTPUT_DIR"

/Applications/RemoteOrbit.app/Contents/MacOS/RemoteOrbit diagnostics export \
  --output "$OUTPUT_DIR" \
  --host-role TEST_HOST \
  --since-unix-ms "$START_MS" \
  --until-unix-ms "$END_MS"
```

Expected result: a `RemoteOrbit-diagnostics-<timestamp>.tar.gz` archive in the output directory. The exporter may honestly mark individual evidence sources bounded/unavailable in `manifest.json`; a single oversized source must not destroy the whole archive.

## Evidence questions for the next review

Correlate real incidents across the existing chain:

`HID/lifecycle → AUDIO_START → BLE cadence → decode → PCM submit → AudioPipe queue → render/starvation → main-queue lag → receiver timing`

The next review should determine what the evidence supports; it must not preselect a root cause. In particular, distinguish upstream BLE/remote delivery gaps from host main-queue scheduling delay before considering an audio corrective.

## Frozen non-goals

- No ATVV MIC_OPEN mode change.
- No BLE protocol/scheduling corrective.
- No ADPCM/decode change.
- No AudioPipe jitter/buffer/playout/gain change.
- No HID/gesture/Option/Control or persistent-session behavior change.
- No receiver behavior change or invasive Accessibility/raw-text capture.
- No automatic upload or automatic settings/key backup.
- No merge, tag, GitHub Release, PR #25 mutation, or release claim.

## Stop conditions

Stop and report if evidence integrity is compromised, runtime identity does not match the packaged candidate, a new reproducible Persistent Session failure appears, or analysis would require changing frozen product behavior before the current natural-use evidence is reviewed.

## Current completion condition

This task remains active until owner natural-use evidence is exported and independently reviewed. A successful diagnostics archive does not by itself establish root cause or release readiness.
