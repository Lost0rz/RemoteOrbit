# RemoteOrbit v0.2.15

## Release purpose

This release establishes the next stable runtime and diagnostics baseline after v0.2.14.

It includes accepted reliability work and the new opt-in audio continuity evidence path. It does **not** claim that the remaining audio-continuity root cause has been fixed.

## Reliability updates

- Includes the Task 038-A rapid re-press admission correction and regression coverage.
- Includes shortcut-recorder exclusive capture / restoration hardening so shortcut recording does not silently damage the normal global voice-trigger path.
- Preserves the existing SHORT/LONG, persistent-session, Option ownership, ATVV transport, and audio-routing contracts outside the accepted changes above.

## Audio continuity diagnostics

v0.2.15 includes the Task 038-B observation-only continuity chain:

`BLE notifications -> decode -> PCM submission -> AudioPipe queue/render -> underrun`

The evidence path uses stable session identity and 100 ms monotonic buckets and records BLE cadence, decoded supply, submission, queue depth, active-stream/tail render behavior, underrun and overflow accounting.

The diagnostic implementation was hardened before runtime use so render/submission observation does not introduce shared diagnostic lock/dictionary contention on the real-time path.

Continuity evidence remains **opt-in** and is enabled only with:

`REMOTE_ORBIT_CONTINUITY_EVIDENCE=1`

Normal product launch keeps the continuity ledger disabled.

## Current diagnostic conclusion

The frozen 038-B evidence set contained 10 usable natural LONG sessions.

Established findings:

- active-stream underrun is real;
- decoder rejects were 0 across the usable sessions and are downgraded as an explanation;
- AudioPipe overflow drops were 0 and are downgraded as an explanation;
- BLE cadence degradation is supported as a recurring contributor, but not an exclusive root cause;
- aggregate PCM supply deficit was only weakly enriched and its earlier `SUPPORTED` interpretation was downgraded;
- most total unfilled frames were tail/teardown artifacts and are separated from active-stream continuity defects;
- final text omission and human-visible quality correlation remain unverified.

Final root-cause status:

`NARROWED_NOT_ESTABLISHED`

The remaining technical boundary is finer-grained ordering inside the current 100 ms bucket between BLE arrival, decoded PCM availability, AudioPipe queue depth and render demand.

## Post-release observation

The intended next step is to run this released build for a longer real-world observation window with the opt-in continuity evidence enabled, then analyze the resulting logs against the exact v0.2.15 runtime identity.

No buffer, queue-target, pacing, codec, BLE timing, AUDIO_STOP, Adaptive Playout, or speculative AudioPipe corrective is introduced by this release preparation.

## Version

RemoteOrbit 0.2.15
Build 44
Universal 2
