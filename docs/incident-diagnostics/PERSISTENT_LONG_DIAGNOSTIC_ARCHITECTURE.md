# Persistent LONG Incident — Diagnostic Architecture

Status: remote audit frozen 2026-10-03  
Authority: reference only; `CURRENT_STATUS.md` and `CURRENT_TASK.md` own mutable state.

## 1. Audit basis

Remote source audited:

- `main` — `7129ef72949eca956b1d0daddce707d5e417eeed`
- retained forensic branch — `d0a1ab06d8fafa0e9a8a1ae3b79cbc0d299a07be`
- abandoned PR #16 — diagnostic prototypes only, never production authority
- current control plane — see `CURRENT_STATUS.md`

Fresh incident runtime:

- source marker `01eeddaecd0dff596b7e0fd31cd4b1862360bc9f`
- executable SHA-256
  `df27b16ff41dcc35191c4699700cbbe522bfd576cbfba7c376712821c58388c2`

GitHub cannot resolve `01eedda...`. Therefore this document maps the remote
architecture and probe gaps but does not claim line-for-line identity with the
installed incident binary.

## 2. State-machine map

### SM-1 — Physical HID / device lifecycle

Owner: `HIDMonitor`.

Key states / data:

```text
disconnected
  ↓ deviceDidMatch
connected / monitored
  ↓ input report
activeUsages + debounce decision
  ↓ accepted microphone edge
onButtonEdgeAt
  ↓ device removal
pendingReconnectUsages
  ↓ reconnect report
held-or-released reconciliation
```

Existing remote facts:

- raw IOHID reports are parsed on the main run loop where possible;
- `eventSuppressor.updateHeld()` is armed from accepted HID state;
- edge callback carries `systemUptime`;
- main does not emit a structured raw microphone-report sequence.

Abandoned PR #16 prototypes a transition-only raw HID record and report sequence.
That is useful design evidence but not current production authority.

### SM-2 — Voice gesture classifier

Owner: `VoicePressCoordinator`.

```text
idle
  ↓ accepted keyDown
pending
  ├─ release < 300 ms → short → idle
  └─ threshold reached → holding
                         ↓ physical release + drain
                         idle
```

Orthogonal ownership includes deferred repress, output drain, physical-up ownership
and release-bounce fencing.

Persistent-open LONG uses the same 300 ms semantic classifier.

### SM-3 — RemoteOrbit Persistent intent/belief

Owner: `VoicePressCoordinator.voiceSessionMode`.

```text
idle
  ↓ persistent trigger dispatch succeeds
persistentOpen
  ↓ persistent close trigger dispatch succeeds
idle
```

Critical architectural fact:

`persistentOpen` is committed after trigger dispatch/suppression logic reports
success. There is no Doubao semantic ACK.

Therefore this is **RemoteOrbit's belief/intention state**, not proof of external IME
state.

### SM-4 — Mapped-trigger ownership

Owners: `HardwareOptionGate`, `VoiceKeyFilter`, `VoiceOptionTrigger`.

Conceptual states:

```text
NO_OWNER
  ↓ beginOptionDeferral
ACTIVE_DEFERRAL
  ├─ short/replay → resolved
  ├─ persistent LONG → SUPPRESSED_OWNER
  └─ cancel → NO_OWNER

SUPPRESSED_OWNER
  ↓ physical release + output drain + quiet period
NO_OWNER

hardware replay may additionally enter HELD_HARDWARE_RELEASE
synthetic fallback has a separate SYNTHETIC_OWNER / DOWN state
```

Existing structured events include gate begin/capture/suppress/replay/closed and
mapped-trigger decisions.

Critical gap: current remote main does not first-class correlate the mapped CGEvent
to a raw HID report sequence, and the logger timestamp is the observation time, not
the original CGEvent timestamp.

### SM-5 — BLE / ATVV transport

Owner: `BLEBridge`.

```text
stopped
  ↓ prepareVoiceTransport
preparing / prewarmed
  ↓ long confirmed
voiceInputRequested
  ↓ ATVV ready
micOpenRequested
  ↓ AUDIO_START
streaming
  ↓ AUDIO_STOP / release
drain / post-release grace
  ↓ micClose / transport close
stopped or prepared
```

Main has detailed lifecycle timing. The retained forensic line adds structured
ATVV boundary events.

### SM-6 — Audio route / CoreAudio

Owner: `AudioPipe` + `SystemAudioDeviceManager`.

```text
candidate prebuffer
  ↓ LONG route activation
remoteActive
  ↓ decoded PCM scheduled/rendered
active output
  ↓ route deactivation
draining queued PCM
  ↓ queue empty
inactive
```

A separate system-default-input action points the app-facing input toward
RemoteOrbit Mic.

Critical distinction:

```text
RemoteOrbit requested / set default input
≠
target process actually opened / kept consuming that input
```

The second fact is a process boundary and is not proven by internal route state.

### SM-7 — Focus / target application

RemoteOrbit chooses a target and may:

- send a distributed command to FloatTabs and receive a request-ID ACK;
- inspect/act on Codex through Accessibility;
- inspect `NSWorkspace.frontmostApplication`.

This is intent/handshake data. It is not a continuous authoritative WindowServer
timeline for the incident.

### SM-8 — External Doubao / IME semantic session

Conceptual states needed for diagnosis:

```text
CLOSED
  ↓ external trigger accepted
OPEN / LISTENING
  ↓ segment activity
OPEN / LISTENING
  ↓ unexpected close condition
STOPPED / CLOSED
```

RemoteOrbit does not own or directly observe this state machine in audited remote
source.

This is the highest-value diagnostic gap because the incident is defined by a
transition in this external machine.

## 3. Boundary map

| Boundary | Producer → Consumer | Existing evidence | Gap | Priority |
| --- | --- | --- | --- | --- |
| B1 | physical remote → IOHID | HID state/edge path exists | raw mic transition is not structured in main | P0 |
| B2 | IOHID edge → HIDMonitor gesture callback | uptime passed to callback | no stable raw-report sequence in main | P0 |
| B3 | hidutil mapping → CGEvent tap | `MAPPED_TRIGGER_EVENT`, gate action | no raw-report join key; no first-class original CGEvent timestamp | P0 |
| B4 | CGEvent delivery → Doubao/IME trigger acceptance | RemoteOrbit sees send/pass decision | no receiver ACK / semantic acceptance | P0 |
| B5 | RemoteOrbit persistent belief → actual external session | internal `PERSISTENT_STATE_CHANGE` | external state can diverge silently | **P0** |
| B6 | remote ATVV → BLEBridge | rich timing; forensic structured ATVV | mostly correlation, not event-volume gap | P1 |
| B7 | AudioPipe/HAL → target process audio consumption | route/default-input actions, render stats | target process consumer open/close not observed | P1 |
| B8 | RemoteOrbit focus intent → WindowServer actual frontmost state | FloatTabs ACK / AX / NSWorkspace spot checks | no independent continuous incident timeline | P1 |
| B9 | external IME → target text/result | local target-text observer exists by evidence filename | source/capability not in remote repo; semantic session coverage unknown | P0 pending local reconciliation |

## 4. Probe inventory and policy

### Existing / strong enough for now

- runtime identity capture outside the product;
- structured RemoteOrbit gesture/gate diagnostics;
- BLE/ATVV lifecycle timing;
- AudioPipe submit/render/drain diagnostics;
- sealed incident raw evidence + hashes.

### Existing but capability must be reconciled locally

- `voice-flight-recorder-current.jsonl`;
- `voice-flight-recorder-incident.jsonl`;
- `target-text-observer-current.jsonl`;
- local runtime checkpoint `01eedda...`.

Their filenames prove existence, not what boundary each observer can prove.

### P0 minimal boundary probes

Do not implement until local reconciliation proves they are missing.

#### P0-A — External IME semantic session observer

Question:

> Did the external voice/IME session transition OPEN/LISTENING → STOPPED, and at
> exactly what boundary time?

Requirements:

- external to RemoteOrbit's internal state;
- read-only;
- transition-only;
- records process/bundle/PID or other stable target identity;
- wall clock plus a monotonic clock usable for cross-source correlation;
- does not infer session state solely from RemoteOrbit trigger intent.

If the existing target-text observer already proves this transition, no new probe.

#### P0-B — Raw HID → mapped CGEvent correlation

Question:

> Did a mapped trigger reach the CGEvent boundary before its HID gesture gate existed?

Minimum fields if missing:

- raw microphone transition sequence;
- raw HID monotonic timestamp;
- accepted/suppressed HID edge;
- mapped CGEvent original timestamp;
- mapped key / flags;
- gate owner/state/action;
- synthetic marker;
- runtime PID.

PR #16 contains a tested prototype for the HID half. Reuse the concept only if the
local runtime/observer inventory shows the boundary is still missing.

#### P0-C — Cross-process correlation anchor

Every independent boundary observer should provide:

- wall-clock timestamp;
- monotonic timestamp from a documented clock where possible;
- observer PID / executable identity;
- incident/run identity.

Do not try to solve cross-process ordering by file write order.

### P1 probes

#### P1-A — WindowServer/frontmost observer

Question:

> Did actual foreground/focus ownership change immediately before the external
> session stop?

Prefer an independent observer or existing system evidence, not RemoteOrbit's own
requested focus transition.

#### P1-B — CoreAudio target consumer observer

Question:

> Did the target process keep, switch, or close its audio input client when
> RemoteOrbit changed routing?

This is more useful than another `AudioPipe` internal queue event.

#### P1-C — ATVV correlation

Existing transport evidence is already dense. Add only missing correlation IDs or
clock anchors if the sealed incident cannot join ATVV to the target boundary.

### P2 — internal audio detail

Do not expand by default.

PCM fingerprints, queue depth, decode and render timing already provide substantial
internal evidence. Only add a specific internal measurement if a later hypothesis
cannot be tested otherwise.

## 5. Diagnostic flow

Use boundary-first diagnosis.

```text
0. Bind runtime identity and sealed incident
   ↓
1. Establish actual external IME session transition
   ↓
2. Establish physical HID microphone edge
   ↓
3. Establish mapped CGEvent delivery / suppression outcome
   ↓
4. Establish gate ownership at that exact boundary
   ↓
5. Check independent WindowServer/frontmost state
   ↓
6. Check ATVV transport state
   ↓
7. Check target-process CoreAudio consumption
   ↓
8. Only then inspect deeper PCM/queue internals
```

### Decision branches

**External stop + escaped mapped trigger immediately preceding it**

- strong support for trigger-boundary causality;
- still require a broken contract and pre-fix failing acceptance before construction.

**External stop + mapped edge fully captured/suppressed**

- move away from the gate;
- inspect focus/external-session/audio-consumer boundaries.

**External stop not independently timestamped**

- stop diagnosis at B5/B9;
- this is a probe gap, not evidence for any internal root cause.

**No target-process audio-consumer evidence**

- do not equate `setDefaultDevice`, `remoteActive`, or ATVV state with what the
  external process consumed.

## 6. Construction Gate

Construction remains BLOCKED until all are true:

1. one broken contract is identified at a specific state/boundary;
2. the sealed incident directly supports that contract violation;
3. competing adjacent boundaries are either observed or explicitly ruled out enough
   to make the change falsifiable;
4. a minimal pre-fix acceptance can fail for the same reason;
5. the proposed scope changes only the proven boundary;
6. instrumentation/probe changes are separated from behavior fixes unless the user
   explicitly authorizes otherwise.

A static race window, an internal state inconsistency, or recovery after restart is
not sufficient by itself.

## 7. Anti-expansion rule

Do not increase diagnostic volume inside a state machine just because the event is
easy to log.

Prefer:

```text
one missing boundary fact
→ one transition-only probe
→ one explicit hypothesis decision
```

over:

```text
more internal logs
→ larger timelines
→ same unknown cross-process boundary
```
