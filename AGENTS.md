# RemoteOrbit Agent Instructions

Before changing code, packaging, runtime configuration, or diagnostics, read
[README.md](README.md), [SETUP_NOTES.md](SETUP_NOTES.md), and the documents relevant
to the requested subsystem.

## Project policy

1. Product behavior and explicitly accepted contracts take precedence over
   implementation convenience. Do not silently redesign user-visible behavior.
2. Keep this file limited to durable project rules. Current PR, branch, HEAD,
   incident, release candidate, and active-task status belong in Git/PR/runtime
   evidence or a dedicated state record, not in AGENTS.md.
3. Do not expand a bounded diagnostic or corrective task into unrelated cleanup,
   refactoring, packaging, release, or installation work without authorization.

## Runtime identity and evidence

4. Treat these as distinct identities unless proven otherwise:
   - source checkout and source HEAD;
   - built executable or app bundle;
   - installed `/Applications/RemoteOrbit.app`;
   - running process;
   - installed `RemoteOrbitAudio.driver`;
   - LaunchAgent/runtime configuration.
5. Any runtime conclusion that depends on identity must report the material
   identity evidence, such as source HEAD, executable path/hash, app version/build,
   Bundle ID/code identity, installed component version, or running process.
6. A Terminal/helper permission result does not prove the RemoteOrbit product
   process has the same TCC/Accessibility/Input Monitoring/Event access. Product
   permission claims require evidence from the product process or an equivalent
   identity-preserving check.
7. Symptom recovery, restart success, reload success, or temporary stability does
   not by itself establish root cause. Separate observed recovery from causal proof.
8. Distinguish verified facts, plausible mechanisms, and uninspected layers.
   Unknown must remain unknown.

## Forensic and side-effect discipline

9. During an incident/forensic capture, preserve the observed runtime by default.
   Do not rebuild, reinstall, replace the app, change TCC permissions, alter
   LaunchAgents, replace/reinstall the HAL driver, restart CoreAudio, or change
   diagnostic behavior unless the task explicitly authorizes that mutation.
10. Packaging, installation, driver replacement, `coreaudiod` restart, TCC
    changes, and LaunchAgent changes are side-effectful operations. An audit,
    diagnosis, or source-only task does not authorize them.
11. Do not stack a speculative production fix on top of unresolved diagnostic
    work without first reconciling what is observation-only, what is experimental,
    and what is intended for production.

## Validation

12. Validate the changed boundary with the smallest sufficient evidence. Protocol,
    audio, HID, packaging, permission, and installed-runtime claims may require
    different validation; one class of evidence must not be substituted for another.
13. Tests should establish contract behavior or regression protection, not merely
    increase test count. Use broader regression only when the affected boundary or
    requested acceptance criteria justify it.
14. Before recommending merge or release, state remaining uncertainty and any
    runtime behavior that was not directly validated.
