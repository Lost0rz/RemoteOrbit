# RemoteOrbit Current Task

## RO-MAPPING-CONFIG-SIMPLIFY-040 — Settings bounded corrective

Status: `WAITING_FOR_INDEPENDENT_WEB_AUDIT`

Repository: `Lost0rz/RemoteOrbit`

Canonical repository: `/Volumes/Jack-Dev/Projects/remoteorbit`

Active branch: `codex/mapping-config-simplify-040`

Active writer worktree: `/private/tmp/remoteorbit-mapping-config-simplify-040`

DESIGN_MODE: `DESIGN_IMPLEMENT`

## Current corrective (delivered)

The owner has frozen the already accepted Settings / Control Center UI and manual JSON import/export behavior as PASS. This continuation is limited to two bounded corrections on the existing 040 implementation:

### A. Deterministic mapping-page entry

Every entry into the `按键映射` section must reset only editor navigation/selection state to:

- `Mapping Scope = Global / 通用`;
- `Selected Button = Microphone / 语音键`;
- the template/editor selection must show the global UI state.

The entry reset must not mutate actual global mappings, App templates, Active Template, runtime routing, or button semantics. User-driven App/template changes while inside the section remain editable; leaving and re-entering resets the editor state again. Add automated coverage for entry, leave/re-enter, and unchanged App-template runtime state.

### B. Observable debug-recording runtime chain

Trace and minimally correct the existing production chain:

`Settings Toggle → onRecordingChanged → BLEBridge.setRecordingEnabled → AUDIO_START → WavRecorder.createNext → appendRawBytes / appendSamples → close → filesystem`.

The implementation must establish observable evidence for the toggle value, enable propagation, AUDIO_START state, recorder creation, WAV/RAW URLs, file creation, raw/sample writes, close, and final WAV/data lengths. Creation or write failures must not disappear as silent nil/failure. Preserve existing BLE/ATVV protocol, AudioPipe, codec, gesture, persistence, import/export, Settings UI, and recording semantics. Add focused tests for disabled/no file, enabled WAV+RAW, observable creation failure, and valid finalization; ensure a second session creates independent files and existing recordings are not deleted.

Delivered in `9669420ecfd65034ebeb61ade08386dd0ca20659`: mapping entry is deterministic and navigation-only; the recorder now uses unique non-destructive paths, throws observable creation errors, reports write/close evidence, and has focused production-chain test seams.

The owner-reported live-session root cause remains `UNKNOWN` because no Air/hardware session was run here. Source evidence confirms the previous silent recorder creation/write boundary and same-millisecond filename collision/deletion risk; local tests now cover the corrected chain.

### Corrective non-goals and acceptance

- Do not redesign the Settings / Control Center UI or revisit the owner-frozen import/export acceptance.
- Do not touch `RO-OBSERVABILITY-039`, PR #25, the Air runtime, release metadata, or any unrelated code.
- Run focused mapping/recording tests, full Swift tests, release build, and `git diff --check`.
- Push only `codex/mapping-config-simplify-040`, create the independent corrective PR, and stop before merge at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`.

## Objective

Remove the overbuilt local mapping-backup/history workflow and replace it with a minimal manual configuration-transfer workflow: export the current mapping configuration to JSON, or import a JSON configuration.

This task is simplification/retirement work. It must reduce product and code surface rather than hide the old backup system behind a smaller UI.

## Historical pre-implementation baseline

Current code contains all of the following:

1. `SettingsView` renders an “按键配置备份” card with:
   - automatic-backup explanatory copy;
   - `导出当前配置…`;
   - `导入配置…`;
   - `打开备份文件夹`;
   - recent backup history;
   - per-backup `恢复` actions;
   - restore confirmation state.
2. `MappingStore` contains:
   - `MappingBackup`;
   - `mappingBackups()`;
   - `latestValidBackup()`;
   - `restoreMappingBackup()`;
   - `backupInvalidConfiguration()`;
   - `backupMappingData()`;
   - backup-before-import/restore;
   - backup-before-ordinary-save;
   - backup creation during migration;
   - automatic historical-backup recovery during load.
3. `AppStorage` owns and eagerly creates `Backups/Mappings`.

The owner does not want this automatic/history backup workflow. The baseline above is historical; the delivered state is recorded below.

## Delivered implementation

- `SettingsView` now presents only the compact `配置导入与导出` surface with manual `导出当前配置…`, `导入配置…`, and concise success/error feedback.
- `MappingStore` no longer creates, scans, restores, or reports automatic mapping backups; canonical atomic JSON persistence, backward-compatible decoding, manual import/export, and the UserDefaults compatibility mirror remain intact.
- `AppStorage.prepare()` no longer creates the retired `Backups/Mappings` directory.
- Existing backup files were not deleted.
- No BLE/audio/HID/diagnostic/driver/observability code or PR #25 was changed.

## Authorized product design

### UI

Replace the current backup/history card with a single compact configuration-transfer card.

Preferred structure:

- title: `配置导入与导出`;
- short explanation: mappings are stored locally; export manually when a copy is needed; import replaces the current mapping configuration;
- primary actions:
  - `导出当前配置…`
  - `导入配置…`
- one concise inline success/error message area when needed.

Import may show one lightweight confirmation after selecting a valid JSON file:

- explain that import replaces current mappings/templates/active selections;
- explicitly state that RemoteOrbit will not create an automatic backup;
- suggest exporting first if the user wants a copy.

Do not add version browsers, history lists, restore timelines, undo stacks, cloud sync, auto-backup toggles, retention settings, or other replacement complexity.

### Backend retirement

Retire the historical backup subsystem rather than merely hiding it:

- remove `MappingBackup` and restore/history APIs when no longer referenced;
- remove backup-before-save;
- remove backup-before-import/restore;
- remove automatic backup creation during migration;
- remove invalid-config snapshot generation;
- remove automatic recovery from historical backup files;
- remove mapping-backup directory creation from app preparation when no longer needed;
- remove backup-specific error cases/messages and unused date/timestamp helpers.

Existing backup files already on disk must not be automatically deleted by this task.

### Persistence contract to preserve

Keep:

- canonical file-backed mapping configuration;
- atomic file writes;
- existing JSON configuration schema and backward-compatible decode behavior;
- manual export;
- manual import;
- current mapping/template/gesture/active-template semantics;
- the existing UserDefaults compatibility mirror unless concrete evidence proves it must change.

A corrupt canonical file may fall through to the existing compatibility/default path, but must not create or scan historical backup snapshots.

## Non-goals

Do not modify:

- button action semantics;
- app-template routing or built-in template contents;
- global pinning semantics;
- advanced gesture semantics;
- voice trigger configuration semantics;
- persistent/momentary voice behavior;
- BLE/audio/HID/driver code;
- RO-OBSERVABILITY-039 instrumentation or Air runtime;
- PR #25/release metadata.

Do not delete existing user backup folders/files automatically.

## Implementation expectations

Prefer deleting obsolete code and state over introducing compatibility wrappers for the retired history UI.

Expected affected production files are limited to the smallest necessary set, likely:

- `remote-orbit/Sources/RemoteOrbit/KeyMapping/SettingsView.swift`
- `remote-orbit/Sources/RemoteOrbit/KeyMapping/MappingStore.swift`
- `remote-orbit/Sources/RemoteOrbit/AppStorage.swift`

Tests may be added/updated as required.

## Verification

At minimum prove:

1. export still produces a valid JSON configuration;
2. importing that JSON restores/replaces the complete mapping configuration correctly;
3. import no longer requires or creates an automatic pre-import backup;
4. ordinary mapping edits/saves no longer create per-change history snapshots;
5. app launch no longer creates the mapping backup directory solely for this retired feature;
6. no remaining UI references to recent backups, restore, or backup-folder navigation;
7. no remaining production references to `MappingBackup`, `mappingBackups()`, `restoreMappingBackup`, `backupMappingData`, or backup-before-save filenames;
8. relevant mapping/settings focused tests pass;
9. full `swift test` passes;
10. release build and `git diff --check` pass.

For the UI, automated/build evidence is implementation evidence only. Final product-interface acceptance remains owner-controlled.

## Delivery

Push only `codex/mapping-config-simplify-040`.

After implementation and verification:

- Delivered implementation commit: `c3b8c74ee933f666bcc9688be9554d9b79416993`.
- Local verification is complete: focused mapping 11/11, focused keymap presentation 10/10, full `swift test` 422/422, release build PASS, and `git diff --check` PASS.
- Retired mapping backup/history residue check is PASS; no retired production/test identifiers remain.
- Remote delivery is `PUSHED_VERIFIED`; `origin/codex/mapping-config-simplify-040` contains the implementation commit and paired control records.
- The task now stops at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`.
- Bounded corrective commit: `9669420ecfd65034ebeb61ade08386dd0ca20659`.
- Corrective verification: focused mapping/recording 20/20, full `swift test` 430/430, release build PASS, and `git diff --check` PASS.
- Corrective PR: `#26` Draft/Open/Unmerged — `https://github.com/Lost0rz/RemoteOrbit/pull/26`.
- do not merge;
- do not tag or release;
- do not modify PR #25;
- do not modify/install the owner's Air validation runtime;
- stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`;
- report exact changed files, removed backup/history surfaces, verification results, and human UI acceptance as `PENDING`.

## Stop conditions

Stop rather than broaden scope if:

- the task would require changing mapping runtime semantics;
- import/export schema compatibility cannot be preserved without a material redesign;
- old backup files must be destructively removed to make the feature work;
- implementation would require touching audio/BLE/HID/observability product paths;
- branch/control identity drifts unexpectedly or unique local work is discovered.
