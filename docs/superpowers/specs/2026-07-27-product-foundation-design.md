# MFanControl Product Foundation Design

## Summary

MFanControl will become a source-only open-source macOS menu-bar utility for
Apple Silicon fan telemetry and safe fixed-RPM control. The next version adds a
compact preset-first interface, read-only temperature telemetry, an app-managed
privileged helper, and an independently implemented minimal AppleSMC layer.

The supported validation target remains the `Mac15,7` MacBook Pro with M3 Pro.
Other fan-equipped Apple Silicon machines remain experimental until a hardware
fixture and the full safety gate exist for that model.

## Product decisions

- Distribution is source-only. There are no official prebuilt binary releases.
- Each user builds locally and signs with their own Xcode team, including a
  Personal Team for local use.
- The privileged service uses `SMAppService` and starts automatically after the
  user approves it in System Settings.
- The app remains menu-bar-only and does not show a Dock icon.
- The approved interface is Compact Control, option A.
- Presets use fixed fan targets derived from each fan's reported range.
- The primary temperature is maximum CPU temperature. Settings also expose GPU
  and battery temperatures when supported.
- No active manual mode or selected preset is restored after app launch, helper
  restart, wake, disconnect, or a safety event.
- The AppleSMC implementation has no runtime dependency on `macos-smc-fan` or
  another third-party SMC package.

Before the full helper migration, a minimal feasibility build must prove that
an app and bundled LaunchDaemon signed locally with the selected Personal Team
can register, reach the approval state, start, and communicate on the target
macOS version. If that gate fails, helper installation returns to design review;
the project does not silently substitute a deprecated privilege API.

## Scope

### Included

- A native Xcode app project that builds the existing Swift modules, menu-bar
  app, privileged launch daemon, tests, and locally signed app bundle.
- One-click helper registration and a guided approval state using
  `SMAppService`.
- A narrow XPC request channel between the app and privileged daemon.
- Read-only fan and temperature telemetry available without privileged control.
- Four preset choices: Auto, Quiet, Balanced, and Cool.
- A separate Settings scene for presets, sensors, helper status, general
  behavior, and project information.
- Independent low-level AppleSMC code with provenance notes and tests.

### Excluded

- Official GitHub binary releases, Developer ID signing, notarization, DMG or
  installer packaging.
- Temperature-dependent fan curves.
- Profiles that automatically activate based on apps, power state, or time.
- Arbitrary SMC reads or writes through UI or IPC.
- Restoring manual control automatically after launch or wake.
- Intel support.

## Architecture

```text
MFanControl.app
  MenuBarExtra + Settings
  FanStore / PresetStore / HelperStore
        |
        +---- read-only ----> TelemetryCore ----> SMCBridge ----> AppleSMC
        |
        +---- bounded XPC --> fancontrold (root, SMAppService)
                                  |
                                  +--> FanController --> SMCBridge --> AppleSMC
```

### App target

The app owns display state, the selected nonpersistent preset, editable preset
percentages, sensor selection, and helper registration state. It reads telemetry
through `TelemetryCore` once per second, so fan and temperature information can
remain visible when the helper is disabled or temporarily unavailable.

The app never imports an arbitrary SMC write interface. Control requests go
only through the fixed privileged protocol.

### TelemetryCore

`TelemetryCore` exposes typed, read-only snapshots:

- fan count;
- actual, target, minimum, maximum RPM;
- fan mode;
- maximum CPU temperature;
- optional GPU and battery temperatures.

Temperature discovery uses a model-scoped allowlist of known candidate keys and
data types. It does not enumerate the SMC keyspace. Unsupported or malformed
sensors are omitted rather than guessed.

### Privileged helper

`fancontrold` is embedded as an app-managed LaunchDaemon and registered with
`SMAppService`. The first-run UI provides an Enable Helper action. When approval
is still required, the app explains the state and opens the correct System
Settings pane.

Once approved, launchd starts the helper at boot. The idle helper leaves every
fan under system control. It never applies a preset at startup.

### XPC boundary

The helper exposes one narrow XPC method carrying the existing bounded Codable
request and response payload as `Data`. The payload remains limited to 4 KiB.
Allowed commands are:

- hello;
- status;
- setPreset;
- setManual;
- setAutomatic;
- setAllAutomatic;
- heartbeat;
- shutdown.

There is no key name, raw byte, or arbitrary write command in the protocol.
Connection acceptance validates the local peer identity supported by the local
development signature and records the peer UID. Invalid peers are rejected.

The app sends a heartbeat every two seconds. XPC interruption, invalidation, or
more than five seconds without a heartbeat triggers `setAllAutomatic()`.

## Independent AppleSMC implementation

The low-level implementation will be rewritten around a project-owned,
minimal API:

- open and close the AppleSMC user client;
- read key metadata;
- read a typed value;
- write only through package-internal, controller-owned operations;
- decode only the data formats required by verified fan and temperature keys.

The rewrite is specification- and evidence-driven:

- public IOKit ABI definitions;
- publicly documented Apple Silicon SMC behavior;
- read-only probes from supported hardware;
- project-owned unit and hardware tests.

No upstream source files, comments, type layout, or application architecture are
copied. A provenance document records each protocol fact and its public source.
The project may retain a non-license acknowledgement of prior research. The
third-party MIT notice is removed only after a source-similarity and provenance
audit concludes that no copied or substantially derived code remains.

## Presets

Targets are calculated independently for each fan:

```text
target = roundTo100(minimum + percentage * (maximum - minimum))
```

Default percentages:

| Preset | Percentage | Purpose |
| --- | ---: | --- |
| Auto | n/a | Return all fans to macOS |
| Quiet | 10% | Low continuous airflow |
| Balanced | 30% | Active cooling without excessive noise |
| Cool | 55% | Stronger continuous cooling |

Settings allows editing Quiet, Balanced, and Cool within a bounded safe range.
The helper recalculates and validates every target against current SMC min/max
values. Applying a preset is transactional: if any fan cannot enter manual mode
or reach its target, every fan returns to automatic control.

Preset percentages persist. The active preset does not persist.

## Interface

### Menu bar label

The label is the fan symbol plus maximum CPU temperature, for example `57°C`.
If the primary temperature is unavailable, it falls back to the fan symbol
without displaying a fabricated value.

### Compact menu

The approved 320–340 point menu contains:

1. MFanControl title, helper state, maximum CPU temperature, and sensor label.
2. A single segmented row: Auto, Quiet, Balanced, Cool.
3. One compact row per fan with name, actual RPM, and a thin range indicator.
4. A collapsed Manual Control disclosure containing per-fan sliders and Apply
   actions.
5. Hardware identity, Settings action, and Quit action.

Preset actions are immediate. Auto is always available. Manual controls and
non-Auto presets are disabled until the helper is enabled and connected.

### Settings

Settings is a native separate scene with five sections:

- Presets: bounded percentage controls and calculated target previews.
- Sensors: CPU maximum, GPU, and battery values plus primary-sensor status.
- Helper: registration state, Enable, Open System Settings, restart, and
  disable actions.
- General: optional launch-at-login setting and display preferences.
- About: version, source repository, license, safety warning, and provenance.

## First-run and helper states

```text
Not registered
  -> Enable Helper
Registered, approval required
  -> Open System Settings
Enabled, starting
  -> bounded connection retry
Connected
  -> presets and manual controls enabled
Error
  -> keep read-only telemetry visible; disable writes; show recovery action
```

Registration is user-initiated. The app never types or stores an administrator
password. macOS owns the approval UI.

## Safety and error handling

- All targets must be nonzero and inside current SMC min/max values.
- Direct manual mode writes are verified by readback.
- The documented Ftst fallback has bounded timing and retries.
- Actual RPM must approach target within 15% in at most 10 seconds.
- Preset application rolls back all fans on partial failure.
- Disconnect, heartbeat timeout, XPC invalidation, sleep, thermal pressure,
  SIGINT, SIGTERM, or orderly shutdown restores automatic control.
- Wake never restores a preset.
- The helper clears Ftst only if it acquired ownership.
- Temperature read failure never results in a guessed temperature.
- Control errors remain visible until a successful user action or explicit
  dismissal; background refresh does not erase them.

## Testing

### Unit tests

- SMC ABI size and offsets.
- Fan and temperature codecs.
- Model-scoped sensor selection.
- Preset calculations, rounding, and bounds.
- Transactional preset rollback.
- XPC payload size and command decoding.
- Helper registration-state mapping.
- Heartbeat, interruption, sleep, thermal, and shutdown safety transitions.
- Ftst ownership and retry behavior.

### Integration tests

- Locally signed app registers its bundled LaunchDaemon.
- Approval-required and enabled states render correctly.
- XPC rejects invalid peers and oversized payloads.
- Helper restart leaves fans in Auto.
- Telemetry remains visible with helper disabled.

### Hardware gate

On `Mac15,7`, repeat the existing manual-control safety gate for every preset:

- one successful apply and Auto restore;
- 20 Auto → preset → Auto cycles;
- disconnect and app termination;
- helper termination;
- sleep and wake;
- thermal safety path;
- separate kill-9 reclaim validation.

No profile becomes verified until the current macOS build passes the complete
gate.

## Delivery order

1. Establish the Xcode project and pass the Personal Team `SMAppService`
   feasibility gate with minimal app/helper targets.
2. Rewrite and validate the independent SMC read layer.
3. Add temperature telemetry and model fixture.
4. Introduce bounded XPC and `SMAppService`.
5. Add preset calculation and transactional daemon command.
6. Build the approved compact menu and Settings scene.
7. Run software verification and the explicit hardware gate.
