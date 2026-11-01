# Task 045D Domain 1 — Remote-Only PCM Attribution Retirement

Date: 2026-11-01
Task: `RO-DIAGNOSTICS-LEGACY-RETIREMENT-045`
Phase: Wave D
Domain: `REMOTE_ONLY_PCM_ATTRIBUTION`
Audit basis: merged `main@640256238941856c3eaa82a54cb6518d59792015`

## Design question

After the local/external AVCapture microphone path is gone, what is the smallest remaining realtime-audio residue that can be removed without changing the proven remote AudioPipe algorithm or diagnostics semantics?

## Verified facts

- RemoteOrbit production now has a single PCM source for `FixedCapacityPCMFrameRing`: decoded remote ATVV audio.
- `AudioPipe.schedule(...)` writes only remote PCM. No production `.local` write remains.
- The ring still models two sources through `AudioPipePCMSource.remote/local` and separately maintains `remoteQueuedFrames` in addition to the monotonic read/write indices that already define total queue depth.
- For current production traffic, every accepted frame is remote. Therefore remote queue depth is identical to total queue depth at every publication boundary.
- `AudioRemoteQueueAttribution` remains in `AudioDataPlaneDiagnostics.swift`, but the current production source does not call it. Its local/mixed-source behavior is historical residue from the retired capture path.
- Tests still create `.local` frames and mixed remote/local FIFOs. These cases no longer model reachable product behavior.
- Remote diagnostic snapshots still expose fields named remote queue depth / pending remote frames. Those names and observable values are useful evidence and do not need to be renamed in this domain.
- The ring's capacity, lock-free reader/reset gate, FIFO behavior, reserve integration and output-drain behavior remain live performance/correctness authority.

## Selected option

Retire only the dead source-attribution layer while preserving the current ring algorithm and the observable remote diagnostics contract.

Concretely:

1. remove the local/mixed source model and redundant per-source atomic counter;
2. make remote-depth result fields derive from the same total queue depth that is now authoritative;
3. update AudioPipe call sites to the simplified remote-only ring API;
4. remove dead attribution helper/test cases;
5. keep external diagnostic field names and all remote realtime behavior stable.

## Why not a broader AudioPipe rewrite

The existing ring has already accumulated extensive evidence around realtime safety, exact full/empty handling, wraparound, reset coordination, reserve behavior and drain ordering. Replacing that algorithm merely because the second source disappeared would mix dead-code retirement with a new realtime architecture and weaken regression attribution.

This domain therefore treats the redundant source discriminator/counter as the only mutation target.

## Ownership after this domain

### Canonical PCM ownership

All frames in the output ring are remote ATVV frames. Total queued frames are also the remote queued frames.

### Diagnostics compatibility

Existing internal/result/snapshot fields with remote-oriented names may remain to avoid broad schema churn. Their values must equal the corresponding total queue depth/consumption values under the remote-only model.

### Realtime authority

Keep unchanged:

- ring capacity;
- monotonic read/write indices;
- reader/reset gate protocol;
- FIFO and zero-fill behavior;
- playout reserve decisions;
- render callback constraints;
- output drain completion;
- remote candidate/prebuffer lifecycle.

## KEEP / RETIRE / FROZEN

### RETIRE

- `AudioPipePCMSource.local`;
- the source discriminator if no retained caller needs it;
- separate `remoteQueuedFrames` atomic state and source-conditioned add/subtract/reset work;
- `AudioRemoteQueueAttribution` local/mixed-source helper logic if no current caller exists;
- tests whose only contract is mixed/local PCM attribution.

### KEEP

- total ring depth;
- remote queue/depth result fields where consumers still use them;
- overflow/drop diagnostics and all external meanings;
- AudioPipe remote producer, reserve, render and drain;
- Domain 6 temporary input lease;
- all current voice/transport correctness.

### FROZEN

- live historical `ShortTap`/`AudioOnly` naming in suppression ownership;
- broader diagnostics/resource-timer cleanup;
- unrelated test/document naming residue;
- final hardware acceptance.

## Verification strategy

Use existing deterministic ring tests plus focused replacements for remote-only attribution.

Acceptance requires:

- no production local PCM source or redundant per-source counter;
- FIFO/full/empty/wrap/reset/stress unchanged;
- remote queue depth fields remain equal to total queue depth at write/read boundaries;
- remote diagnostics, reserve, output drain and realtime callback source contracts remain green;
- Domain 6 lease and current LONG-only/BLE/suppression regressions remain green;
- full Swift/Release/Universal2 durable CI passes.

## Reversibility

High. This removes an unreachable attribution dimension without changing the externally visible PCM path or queue semantics. Rollback reintroduces only redundant source bookkeeping.

## Next step

One bounded local implementation, then independent Web exact-head audit. No other Wave D domain is authorized by this design.