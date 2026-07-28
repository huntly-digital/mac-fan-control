# MFanControl Safety Contract

MFanControl can influence physical cooling hardware. The requirements in this
document are release blockers, not optional recommendations.

## Safety objective

macOS remains the default owner of every fan. MFanControl may request a bounded
manual target only during an active, healthy client session and must attempt to
return every fan to Auto and restore its captured minimum when that session or
its safety assumptions fail.

## Assumptions and limitations

- SMC keys and behavior vary by model and firmware.
- Reported minimum and maximum RPM are policy inputs, not proof of safe hardware
  limits.
- A successful write does not prove that the fan reached the target.
- Userspace cannot catch `SIGKILL`, kernel failure, power loss, or firmware
  failure.
- Software tests cannot validate physical fan response.
- macOS behavior observed on one build may change on another.

The project therefore uses conservative model states and requires repeated
on-device validation.

## Control invariants

### Narrow command surface

Neither UI nor IPC can name an arbitrary SMC key or provide raw bytes. Every
writable operation is owned by `FanController`.

### Bounded target

A requested RPM must:

- be nonzero;
- be at or above the captured hardware baseline minimum;
- be at or below the current reported maximum;
- refer to an existing fan.

Presets derive a separate target for every current fan:

```text
target = roundTo100(minimum + percentage × (maximum - minimum))
```

### Capability-gated writes

No write is accepted until the exact model, macOS build, and deterministic
capability fingerprint has passed explicit validation. Missing keys, unexpected
types, invalid fan indices/ranges, or a changed fingerprint blocks writes.
Discovery and unit tests never create approval.

### Verified floor and manual mode

Before any floor write, every affected baseline is captured and a root-owned
`0600` recovery journal is atomically persisted.

The controller writes `F%dMn` to the bounded target before acquiring manual
mode. `minimumRPM` remains the captured baseline for policy; the current SMC
floor is reported separately as `effectiveMinimumRPM`.

The direct strategy writes the selected mode key, waits 100 ms, and reads the
mode back. Failure or an immediate return to system mode is not accepted as a
successful transition.

When `Ftst` is available, the bounded fallback:

1. records the prior `Ftst` state;
2. writes `Ftst=1`;
3. waits 500 ms;
4. retries the manual-mode write every 100 ms;
5. stops after the configured ten-second limit.

`Ftst=0` is written only if this process changed `Ftst` from a different state.

### Verified target response

After writing the target, the controller verifies the temporary floor, manual
mode, target readback, and actual RPM. The actual reading must approach within
15% of the requested target during the configured ten-second window.

Failure performs full transactional restoration and returns a bounded error.

### Verified baseline restoration

Restoration order is mode Auto, captured `F%dMn`, automatic/system readback,
owned-`Ftst` release, and recovery-journal deletion. Manual or unknown readback
is never accepted. A failed baseline restoration revokes approval and blocks
all additional runtime writes.

### Transactional presets

If any fan fails while a preset is being applied, the helper attempts to return
all fans to Auto. A preset must not leave a successful subset in manual mode.

## Automatic recovery events

The helper attempts `setAllAutomatic()` after:

- XPC client invalidation following an active fan session;
- development socket disconnect;
- more than five seconds without a heartbeat while manual control is active;
- system sleep;
- serious or critical thermal pressure;
- `SIGINT`;
- `SIGTERM`;
- orderly helper shutdown;
- partial preset application;
- target verification failure.
- repeated power-source drift or failed bounded reapply.

Wake sets the safety state to Auto and never restores a prior preset.

The app also resets its displayed active preset to Auto when the helper
connection fails.

## Crash recovery and `kill -9`

`SIGKILL` cannot run cleanup code. On startup the helper restores a stale
recovery journal before accepting writes, but only when its capability
fingerprint matches. A mismatch blocks writes instead of guessing.

A model cannot be marked verified until an on-device forced-termination test
proves the journal path restores mode and every baseline floor.

## Hardware support states

### Unsupported

Required known keys are absent or no supported mode-key format is available.
The project does not scan for alternatives or guess a write strategy.

### Experimental

Known keys and a bounded strategy are available. Writes still require explicit
approval for the exact model, current macOS build, and fingerprint.

### Verified

The full gate has passed and the anonymized evidence is recorded. A later
macOS or firmware change may require returning the profile to experimental.

The current implementation discovers supported-shaped hardware as
experimental. No model is automatically promoted to verified.

## Required validation order

1. Run unit and integration tests without hardware writes.
2. Run `make probe`.
3. Review the anonymized known-key report.
4. Confirm the model and macOS build.
5. Explicitly confirm validation, which starts with `minimum + 500 RPM`, capped
   at the reported maximum.
6. Run one Auto → Manual → Auto cycle.
7. Confirm mode readback and RPM response.
8. Run twenty consecutive cycles.
9. Test app disconnect.
10. Test helper termination and orderly shutdown.
11. Test sleep and wake.
12. Test serious and critical thermal recovery.
13. Run the separate `kill -9` reclaim test.

Stop immediately on an unexpected mode, RPM, key type, timeout, or recovery
failure. Return to Auto and do not broaden the key search.

## Prohibited shortcuts

- Exposing arbitrary SMC access for debugging convenience.
- Treating reported min/max as proven mechanical limits.
- Persisting or restoring active manual state.
- Deleting a recovery journal before verified baseline restoration.
- Writing after a capability mismatch or failed baseline restoration.
- Letting multiple app instances share write ownership.
- Disabling heartbeat recovery to simplify development.
- Reusing write sequences from another model without read-only evidence.
- Running write tests automatically or in CI.
- Marking a profile verified from unit tests or a single successful cycle.
- Clearing `Ftst` without ownership.
- Hiding a failed Auto restoration.

## Pull-request safety checklist

For any control, helper, IPC, packaging, or SMC change:

- [ ] The command surface remains typed and bounded.
- [ ] No raw key or byte field reaches UI or IPC.
- [ ] RPM validation remains nonzero and current-range bounded.
- [ ] Manual mode and target response remain verified.
- [ ] Preset failure remains transactional.
- [ ] Disconnect, timeout, sleep, thermal, and shutdown recovery still converge
      on Auto.
- [ ] Wake does not restore manual state.
- [ ] `Ftst` ownership is preserved.
- [ ] Software tests cover the changed branch.
- [ ] Hardware testing is explicitly identified as run or not run.
- [ ] Diagnostic evidence contains no direct identifiers.
- [ ] New SMC facts include provenance.

Potentially dangerous unpublished findings belong in a private report under
[SECURITY.md](../SECURITY.md), not a public issue.
