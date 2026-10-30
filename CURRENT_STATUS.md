# CURRENT_STATUS

Last updated: 2026-10-30
State: `RO-VOICE-PIPELINE-SIMPLIFICATION-042 — CORRECTIVE_CANDIDATE_PREPARATION_COMPLETE / READY_FOR_HUMAN_CORRECTIVE_RUNTIME_RETEST`
Repository: `Lost0rz/RemoteOrbit`

## Current authority

- Active branch: `codex/voice-pipeline-simplification-042`.
- Preparation control HEAD audited before the receipt commit: `961661d25f74253f95320faf19ea79cc8d4cee24`.
- `AGENTS.md` remains durable repository authority.
- `CURRENT_TASK.md` is the sole active execution authorization.
- Frozen 041 observability baseline: `ac3132986197bfee4440bb8f388e3d2e5f478f03`.

## Accepted semantic lineage

- Gate A: `50b1d9efabe15f04d5479b39af227d0e6f43a4e3` — CLOSED / INDEPENDENT AUDIT PASS.
- Gate B: `ae0bf10874d34ce556b4b73a506b22f6a9a1a412` — CLOSED / INDEPENDENT AUDIT PASS.
- Gate C: `9abdebc21a1e03c79ab0ac960bf2d9902c24b1d5` — CLOSED / INDEPENDENT AUDIT PASS.
- Gate D: `9cdbf6f5190d9ed453d7f15cf2e8192973cc62ad` — CLOSED / INDEPENDENT AUDIT PASS.
- Gate E candidate before runtime failure: `2d09b6d77f9f75aa46bb4a13838cd22d5589f524` — SOURCE AUDIT PASS; runtime acceptance later FAILED.
- Physical-HTT admission corrective: `7dfd2e0c9ab71d3fa437be9b4c5cfac1282d9b1c` — INDEPENDENT CODE_DIFF AUDIT PASS.

## Runtime incident

Installed candidate `0.2.14 (43)` exposed a real no-waveform regression after the first successful session. Preserved runtime evidence showed valid `PHYSICAL_HTT` AUDIO_START, BLE notifications and decoded PCM, while the matching HID press was rejected `voice_session_busy` and `AudioPipe.remoteActive` never became true.

Incident record:

`docs/incidents/2026-10-30-042-no-waveform-physical-htt-admission-race.md`

The confirmed fault was ownership ordering: a pre-HID physical ATVV stream was being published as session-owned `remoteStreaming`, poisoning direct-session admission.

## Corrective source acceptance

Independent Web audit of exact head `7dfd2e0c9ab71d3fa437be9b4c5cfac1282d9b1c` accepts the bounded corrective source semantics:

- pre-HID physical streaming is separated from `VoicePressCoordinator` session ownership;
- candidate-only pre-HID streaming no longer makes the matching HID press busy;
- direct HID admission still establishes normal profile/trigger ownership and activates the existing remote route;
- an already-active physical stream is adopted before the host-MIC_OPEN path, preventing a duplicate host MIC_OPEN for that stream;
- the existing AudioPipe candidate prebuffer is preserved and promoted through the normal route activation path;
- normal no-preexisting-stream activation still uses the Gate B strict-READY host-MIC_OPEN path;
- unowned physical stream retirement clears candidate state;
- adopted stream retirement continues through the existing Gate A-E tail/output-drain/session-ID boundaries;
- long-lived READY, strict READY, ATVV framing/codec, Gate C ring, Gate D 45 ms reserve, driver and runtime policy were not changed.

Executor evidence at the corrective head records focused suites `225/225` (corrective subset `64/64`), full Swift `574/574`, arm64/x86_64 Release builds, protocol self-tests `3/3`, and `git diff --check` passing. Independent audit accepts source semantics only; installed corrective runtime behavior is not yet accepted.

## Corrective candidate preparation receipt

The corrective source identity is frozen at:

`7dfd2e0c9ab71d3fa437be9b4c5cfac1282d9b1c`

The live branch was fast-forwarded to `961661d25f74253f95320faf19ea79cc8d4cee24`, and local/remote equality was verified before preparation. The pre-build range proof was:

`git diff --name-status 7dfd2e0c9ab71d3fa437be9b4c5cfac1282d9b1c..961661d25f74253f95320faf19ea79cc8d4cee24`

which contained only `M CURRENT_STATUS.md` and `M CURRENT_TASK.md`; product source and package scripts were unchanged.

Established preparation flow completed successfully:

- Command: `./package-dmg.sh --reuse-driver`.
- Result: arm64 Release and x86_64 Release built; Universal2 app packaged; DMG created; app and package signatures verified by the existing scripts.
- App artifact: `/private/tmp/remoteorbit-voice-pipeline-simplification-042/remote-orbit/dist/RemoteOrbit.app`.
- DMG artifact: `/private/tmp/remoteorbit-voice-pipeline-simplification-042/dist/RemoteOrbit-0.2.14.dmg`.
- Candidate identity: Bundle ID `com.lost0rz.RemoteOrbit`, version `0.2.14`, build `43`, architectures `x86_64 arm64`, source-head `961661d25f74253f95320faf19ea79cc8d4cee24`.
- SHA-256: app executable `b2acee7ab8070ea82f066c32e47e2aab493cc7bccd065ed284757e0568b81404`; DMG `71e130248f8d8685ff12c274e7449750c5c31bddf55e530cf44b380e5aa6b616`.
- The DMG was mounted read-only and its embedded app matched the source artifact identity and executable hash.

The old installed candidate PID `80225` exited cleanly. Only `/Applications/RemoteOrbit.app` was replaced from the prepared app artifact. Installed app provenance was exact: source and installed executable hashes matched, all app-bundle file hashes matched, and the installed app passed deep strict code-sign verification. The installed app was launched as PID `8511` at `/Applications/RemoteOrbit.app/Contents/MacOS/RemoteOrbit`, version `0.2.14`, build `43`.

Runtime readiness evidence was observed without driver or TCC mutation:

- `RemoteOrbit.log` for PID `8511` recorded `RemoteOrbit Mic 2ch IOProc 已启动: id=73, 48000 Hz stereo`, restored the default input, `BLE 蓝牙已就绪`, HID permissions `input=true accessibility=true`, event suppressor `ready=true`, RC003 connected in compatibility/monitored mode, and the RC003 voice-key mapping enabled.
- `system_profiler` showed `RemoteOrbit Mic 2ch` as the default 2-channel USB input and RC003 as connected with vendor `0x2717`, product `0x32B8`.
- `voice-diagnostic-current.jsonl` recorded `RUN_START` for PID `8511` and `HID_VERIFY result=MATCH`.
- `/Applications/RemoteOrbit.app/Contents/MacOS/RemoteOrbit diagnostics status` reported the existing journal and read-only mode; `diagnostics verify` returned `{"ok":true,"schema_version":1}`.
- The installed driver remained version `596`, code-sign valid, and its pre/post file hashes matched. No driver replacement/reload or TCC reset was performed.

Preparation is complete. These observations establish candidate provenance and basic runtime readiness only; they do not establish the corrective runtime behavior or a human PASS.

Do not modify product source during candidate preparation. Do not merge, tag, release, reset TCC, replace/reload the driver, alter the 45 ms reserve, or create Gate F.

## Stop / next

Stop at `READY_FOR_HUMAN_CORRECTIVE_RUNTIME_RETEST`.

The user must personally retest the original failure mode: first voice session plus repeated subsequent RC003 presses, verifying Doubao waveform/audio remains present after READY transport reuse. Agent-side packaging or automated tests cannot approve the runtime acceptance.
