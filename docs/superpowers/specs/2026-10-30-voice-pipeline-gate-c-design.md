# Gate C Realtime-safe Audio Data Plane Design

**Task:** `RO-VOICE-PIPELINE-SIMPLIFICATION-042-GATE-C-EXECUTE-001`

## Intent

Replace AudioPipe's dynamic `pendingOutput` array and render-shared ordinary
lock with one bounded, preallocated PCM transport ring while preserving the
existing audio semantics, output-drain boundary, diagnostics authority, and
Gate A/B behavior.

## Goals

- Keep one fixed-capacity PCM storage path for local and remote output samples.
- Keep the logical producer serialized by the existing producer-side state
  ownership while removing `stateLock` from the CoreAudio callback.
- Make the callback direct-to-output, allocation-free, collection-free,
  formatting-free, I/O-free, and non-dispatching.
- Preserve FIFO ordering, partial reads/writes, exact full/empty behavior,
  truthful underflow and overflow evidence, remote-frame attribution, tail
  rendering, and session reset behavior.
- Preserve 041 continuity/export evidence by publishing bounded scalar render
  observations for off-path consumption.

## Non-goals and anti-goals

- No Gate D startup reserve, jitter tuning, or playout threshold.
- No Gate E start/tail policy change.
- No BLE/ATVV, codec, gain, limiter, resampling, driver, install, TCC, or Air
  runtime change.
- No intentional delay: the ring starts empty and the first available sample is
  rendered immediately.

## Selected approach

The current 96,000-frame maximum queue is retained as a structural capacity at
48 kHz. A preallocated Float storage ring uses monotonic producer/consumer
indices and bounded atomic publication. Remote-frame attribution is published
with the write index so the consumer can preserve the existing remote/tail
diagnostic meaning. Ring-full input is rejected deterministically; unread
samples are never overwritten and rejected remote samples become overflow
evidence.

The CoreAudio callback reads directly into the supplied `AudioBufferList`,
zero-fills only the missing suffix, and updates bounded atomic counters. It
does not acquire `stateLock`, allocate a sample array, mutate a dynamic
collection, format output, log, or dispatch. Existing render/continuity
observations are transferred through a fixed scalar mailbox and consumed by
normal non-realtime AudioPipe operations. Output-drain completion is signaled
only after the ring reports inactive route plus actual empty state; a separate
non-realtime waiter delivers the existing main-queue completion.

The compatibility `compaction_count` field remains present but is frozen at
zero because compaction no longer exists.

## Validation boundary

Tests cover ring FIFO/wrap/full/empty/partial behavior, underflow,
overflow/order, render-path source constraints, drain and tail ordering,
session reset, counter mapping, and bounded producer/consumer activity.
Focused AudioPipe/Gate A/B/ATVV/041 suites plus the full Swift/build/self-test
matrix remain required before delivery.
