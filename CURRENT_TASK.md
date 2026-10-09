# RemoteOrbit Current Task

## Current task — RECEIVER B EXTERNAL SHORTCUT SEMANTICS GATE

- **Status:** ACTIVE / USER MANUAL EXTERNAL SEMANTICS TEST ONLY
- **Task ID:** `RO-DUAL-RECEIVER-B-EXTERNAL-SEMANTICS-GATE-026`
- **Previous task:** `RO-DUAL-RECEIVER-SET-B-RELEASE-INCIDENT-025` — INTERNAL RELEASE COMPLETE / EXTERNAL DIVERGENCE
- **Corrective branch HEAD:** `458e28d91b5ff748613bb88f5b89212d660279c7`
- **Installed source:** `406f1242e7c3bc17b1fa0da43b069a0b2c6874c8`
- **Merge:** FORBIDDEN

## Proven internal result
The accepted 025 snapshot proves a true B transaction completed internally:

```text
second DOWN gap = 140.400083 ms
SECOND_RAW_DOWN_EMITTED = YES
mapped key = right_option
B HardwareOptionGate = begin -> long-ready -> physical-up -> output-drained -> closed
B classified = YES
first PCM before B DOWN replay = YES
mapped B UP observed = YES
output drain complete = YES
B UP released after drain = YES
MOMENTARY_COMPLETE = YES
B->A restore = success
normal synthetic trigger edges = 0
```

The user nevertheless reported Receiver B remained open. Therefore the next question is not an internal transaction question.

## Authorized test
User performs exactly one direct physical-keyboard test against Receiver B, without using the Xiaomi remote:

```text
physically press and hold Right Option
confirm whether Receiver B opens
release physical Right Option
confirm whether Receiver B closes/ends
```

Use the normal physical Right Option key. Do not use the RemoteOrbit remote gesture for this test.

Record only:

```text
PHYSICAL_RIGHT_OPTION_OPENS_B: YES/NO
PHYSICAL_RIGHT_OPTION_RELEASE_CLOSES_B: YES/NO
STUCK_AFTER_PHYSICAL_RELEASE: YES/NO
```

## Interpretation
If physical Right Option release also does not close B, classify:

`RECEIVER_B_SHORTCUT_NOT_MOMENTARY_OR_EXTERNAL_CONFIG_SEMANTICS`

Do not change RemoteOrbit code.

If physical Right Option hold/release opens and closes B normally, classify:

`REMOTEORBIT_REPLAY_NOT_EXTERNALLY_EQUIVALENT_TO_PHYSICAL_RIGHT_OPTION`

Then stop and return to Web. A later task may compare captured/replayed CGEvent shape and modifier flags; do not modify code in this task.

## Strict prohibitions

```text
NO RemoteOrbit source/test edits
NO build/install/restart
NO mapping/settings changes
NO remote Set-B retry
NO Set C
NO driver/CoreAudio/TCC changes
NO merge
```

## Stop
After exactly one physical Right Option hold/release result, return to Web.
