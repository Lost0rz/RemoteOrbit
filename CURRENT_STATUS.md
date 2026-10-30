# CURRENT_STATUS

Last updated: 2026-10-31
State: `RO-VOICE-PIPELINE-SIMPLIFICATION-042 — WAITING_FOR_INDEPENDENT_WEB_AUDIT`
Repository: `Lost0rz/RemoteOrbit`

## Current authority

- Active branch: `codex/voice-pipeline-simplification-042`.
- Live branch before this control transition: `4902223a28d1b051dd36608df16eb946377aa3fe`.
- Independent Web `CODE_DIFF` audit PASS remains valid for the prior admission-atomic source through `6fb609ea9fdda31cbe7dbd87b78c64839e47a065`.
- Installed RC003 candidate: `0.2.14 (43)`, packaged from control state `00106e6d02b6fc21030737cd660b456976db68e9`; this candidate FAILED final Task 042 human runtime acceptance under extreme rapid re-press.
- Driver and TCC were not changed during runtime preparation or testing.
- Evidence/design authority: `docs/incidents/2026-10-30-042-host-mic-open-rapid-repress.md`.
- `AGENTS.md` remains durable repository authority.
- `CURRENT_TASK.md` remains the sole active execution authorization.

## RC003 corrective implementation evidence

The RC003 failure model was confirmed against the live source and incident
record. The bounded source corrective is implemented on the existing 042
branch and is locally GREEN; independent Web source audit remains pending.

- Physical supersession is limited to a real AUDIO_STOP drain with a pending
  stop reason, incoming `AUDIO_START reason=0x03`, a different stream ID, and
  an old physical stream (`.preHIDPhysical` or adopted physical origin).
- The old drain callback carries its transport epoch and cannot retire a newer
  stream. The old AudioPipe output queue remains separate from the replacement
  candidate prebuffer.
- Candidate PCM uses candidate-only ingress, survives old route teardown, and
  is promoted only on later session adoption.
- Direct re-press admission retains one pending B as soon as A physical UP and
  BLE-owned live physical-candidate truth overlap; B remains serialized behind
  existing output/trigger-UP ownership.
- HID microphone debounce bypass is evidence-gated by the synchronous BLE
  live-candidate read. Generic 180 ms debounce remains unchanged otherwise.

Verification evidence:

- Focused Task 042 boundary suite: 95 tests, 0 failures.
- Full Swift test suite: 603 tests, 0 failures.
- ARM64 Release build: PASS; single `arm64` binary verified.
- x86_64 Release build: PASS; single `x86_64` binary verified.
- ATVV protocol self-tests: 3/3 PASS.
- `git diff --check`: PASS.
- No package, install, runtime retest, driver, CoreAudio, or TCC mutation was
  performed.

## RC003 runtime result

Human runtime acceptance: `FAIL`.

Observed user-visible failures during extreme rapid re-press:

- the IME waveform can remain active briefly after physical release;
- a new hold can show waveform/input activation while speech produces no transcription;
- failures concentrate in very fast release/re-press sequences.

Captured evidence is sufficient for corrective work; no broad new probe phase is required.

Evidence summary from the RC003 capture:

- `late AUDIO_START ignored during drain`: 13 observed occurrences;
- `voice_session_busy` admission rejection following rapid re-press: 7 observed occurrences;
- microphone HID DOWN suppressed by the existing debounce window: 8 observed occurrences;
- at least streams 31 and 48 carried physical audio with `session_id=NA` and zero render callbacks / filled frames;
- no permanent stuck session was observed; the runtime recovered to idle/READY.

## Root-cause layer

The remaining defect is an ownership-model problem at the overlap of BLE transport drain, AudioPipe candidate buffering, direct-session serialization, and voice-key debounce.

Current behavior incorrectly couples three different lifetimes:

1. late BLE packets from old stream A may still be accepted for up to 350 ms after `AUDIO_STOP`;
2. old stream A remains the active transport/decoder owner during that window;
3. a new voice session B is blocked while that drain work item exists.

If a new explicit physical `AUDIO_START reason=0x03` with a new stream ID arrives during A's drain, current code ignores the new start. Subsequent B audio can then be accounted under the old transport epoch while B HID admission is rejected or debounced. This explains the observed waveform-without-transcription failure.

The fixed 350 ms window is not itself the defect. RC003 contains late old audio near that boundary, so globally shortening the drain would risk restoring tail loss.

## Selected corrective design

### 1. Transport epoch supersession

A new explicit physical `AUDIO_START reason=0x03` with a different stream ID is the authoritative boundary for a new ATVV transport epoch when the previous physical-HTT stream is already in terminal `AUDIO_STOP` drain.

Under that narrow predicate:

- retire/cancel only the old BLE ingress drain barrier/generation;
- preserve already queued old PCM so output can finish normally;
- reset/start decoder state for the incoming stream;
- install the new stream ID;
- classify the incoming stream as `.preHIDPhysical` candidate ownership;
- retain READY;
- stale old drain callbacks must not retire or mutate the new epoch.

Do not globally reinterpret non-0x03 events, same-stream duplicates, UNKNOWN origin, or normal HOST_MIC_OPEN behavior.

### 2. Candidate PCM isolation

PCM for `.preHIDPhysical` must have a candidate-only path into AudioPipe. It must not enter the previous session's active output merely because `remoteActive == true` for old session A.

Old A output drain may continue consuming already queued A frames, while B candidate PCM accumulates separately for later adoption. Old-session teardown must not clear a live replacement candidate/prebuffer.

### 3. Earlier direct re-press deferral

When old direct session A has observed physical UP and a live new physical candidate B exists, retain one pending direct B even if A has not yet reached `directOutputDrainRequested`.

B remains serialized: no B trigger DOWN, route activation, or session promotion until A transport/output/trigger-UP ownership has retired through the existing ordering. Matching early B UP still cancels cleanly.

### 4. BLE-owned live-candidate truth

Expose a thread-safe BLE truth for a live `.preHIDPhysical` candidate so critical admission/debounce decisions do not depend only on asynchronous main-queue propagation.

### 5. Evidence-gated voice-key debounce bypass

Keep generic 180 ms debounce behavior. For the microphone voice key only, a rapid DOWN may bypass debounce when BLE already proves a live new physical candidate. Without that evidence, existing debounce behavior remains unchanged.

## Preserved behavior / non-goals

- Do not globally shorten/remove the 350 ms tail window.
- Do not globally disable the 180 ms HID debounce.
- Do not run two ATVV decoders/transport epochs in parallel for ambiguous packets.
- Preserve prior Task 042 HOST_MIC_OPEN grace supersession and MIC_CLOSE safety.
- Preserve A-UP-before-B-DOWN hardware serialization and promoted-B UP/output-drain lifecycle.
- Preserve long-lived READY, strict READY, Gate C ring, Gate D 45 ms reserve, ATVV codec/framing, driver/TCC behavior.
- No global UNKNOWN remap.
- No Gate F.
- No merge/tag/release until the new corrective passes independent source audit and human runtime acceptance.

## Next

The source corrective and deterministic regressions are delivered on the
existing Task 042 branch. Push the existing branch, verify exact local/remote
equality, and stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`. Do not
package/install or perform the human RC003 runtime retest until independent Web
source audit accepts this state.
