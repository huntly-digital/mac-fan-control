# MFanControl Architecture

This document describes the current implementation. It is not a roadmap.

## Design goals

MFanControl separates display, privilege, policy, and low-level hardware access
so that no UI or transport can issue an arbitrary SMC operation.

The main boundaries are:

1. The app owns presentation and user intent.
2. Shared protocol types define the complete command surface.
3. The privileged helper owns control and recovery.
4. `FanCore` owns policy, capability approval, recovery, and model-aware fan
   behavior.
5. `SMCBridge` owns the minimal AppleSMC transport and typed codecs.

## Runtime control flow

```text
MFanControlApp
  FanMenuView / SettingsView
            |
            v
  FanStore / HelperStore / PresetStore
            |
            v
  HelperFanClient
  NSXPCConnection(machServiceName: io.clover.mfancontrol.helper)
            |
            | Data containing bounded FanRequest
            v
  HelperXPCService
            |
            v
  SessionCoordinator / RequestProcessor
  SafetyStateMachine
            |
            v
  FanController -> AppleSiliconFanEngine
            |
            v
  SMCBridge -> AppleSMC user client
```

The app polls status once per second and sends a heartbeat every two seconds
while connected. The helper safety timer evaluates heartbeat expiry every
second. Each XPC connection has an internal session UUID; one healthy session
owns the write lease while observers retain read-only telemetry.

## Package targets

| Target | Responsibility |
| --- | --- |
| `SMCBridge` | AppleSMC user-client connection, key metadata, typed RPM/temperature codecs, package-internal writes |
| `FanProtocol` | `FanRequest`, `FanResponse`, hardware/fan/temperature models, errors, bounded JSONL codec |
| `HelperProtocol` | Objective-C-compatible XPC interface and service identifiers |
| `HelperServiceCore` | Privileged XPC endpoint, client signing requirement, lifecycle and safety hooks |
| `HelperManagement` | App-side helper installation state, ping client, and persistent fan-request XPC client |
| `FanCore` | Hardware capability discovery, approvals, recovery journal, RPM/preset policy, stateful fan engine, sensor registry, probe, and safety state machine |
| `FanDaemonCore` | Request processing, development Unix-socket server, and peer UID policy |
| `fancontrold` | Read-only probe, development daemon, and privileged Mach-service entry point |
| `MFanControlApp` | SwiftUI menu-bar UI, settings, stores, and presentation logic |

Tests follow these boundaries in separate SwiftPM test targets.

## Protocol boundary

The allowed commands are:

- `hello`
- `status`
- `setManual`
- `setPreset`
- `setAutomatic`
- `setAllAutomatic`
- `heartbeat`
- `shutdown`
- `validateHardware`

`FanRequest` contains only a request identifier, command, optional fan index,
optional RPM, optional preset percentage, and explicit validation confirmation.
It cannot carry an SMC key, data type, raw bytes, file path, or shell command.

`HelperXPCProtocol.performFanRequest` accepts `Data`, but both sides encode and
decode it with `JSONLineCodec`. Requests are limited to 4 KiB. Telemetry
responses, including bounded sensor diagnostics, are limited to 32 KiB.

The XPC listener applies a code-signing requirement containing:

- bundle identifier `io.clover.mfancontrol`;
- Apple generic anchor;
- the Team ID read from the helper's own signature.

The helper refuses to start without a usable Apple Development Team signature.

## Privileged helper lifecycle

`script/package_helper.sh` builds and signs `fancontrold`, then creates a local
component package containing:

```text
/Library/PrivilegedHelperTools/io.clover.mfancontrol.helper
/Library/LaunchDaemons/io.clover.mfancontrol.helper.plist
```

The launchd plist publishes the Mach service
`io.clover.mfancontrol.helper`. The app embeds
`MFanControlHelper.pkg` under `Contents/Resources` and opens it with the
standard macOS Installer after an explicit user action.

The app considers the helper connected only when:

1. the installed helper path is executable; and
2. an XPC ping returns protocol version 4.

Protocol version 3 is incompatible. Reinstalling the local package replaces the
helper and reloads the same launchd label.

## Request processing and recovery

`RequestProcessor` is the only component that translates protocol commands into
`FanControlling` calls. It receives the internal connection session ID from the
XPC service; session IDs are never part of public IPC.

- Status commands return hardware, fan, and optional temperature snapshots.
- Manual and preset commands are rejected during serious or critical thermal
  pressure.
- Presets calculate one bounded target per current fan.
- A partial preset failure calls `setAllAutomatic()`.
- Disconnect, heartbeat timeout, sleep, thermal emergency, and shutdown are
  routed through the shared `SafetyStateMachine`.

The first healthy `hello` owns the write lease. Other accepted signed clients
are observers and receive `controllerBusy` for write and validation commands.
Owner invalidation invokes the shared full-restoration path and releases the
lease.

## Hardware discovery and SMC access

`HardwareProfiler` reads only the fan count and known fan/key candidates. For
every detected fan it profiles `Ac`, `Tg`, `Mn`, `Mx`, the selected mode key,
their data types, and the reported range. It selects:

- `F%dMd` when `F0Md` exists;
- `F%dmd` when `F0md` exists;
- unsupported when neither exists.

`Ftst` presence selects the bounded direct-then-fallback strategy. A
deterministic capability fingerprint covers model, fan count, keys, types,
ranges, and strategy. Discovery alone never grants write eligibility.

`FanController` exposes typed operations and delegates write transitions to
`AppleSiliconFanEngine`:

- discover hardware;
- read fan and temperature snapshots;
- produce a read-only probe;
- set one fan to a bounded manual target;
- restore one or all fans to Auto.
- validate hardware after explicit confirmation.

Raw key writes remain internal to the controller and transport package.

Before the first temporary floor write, the engine captures baseline minima and
atomically persists a root-owned `0600` recovery journal. Startup restores only
a fingerprint-matching journal. Approval is stored separately and is keyed by
the exact model, macOS build, and fingerprint. Neither store contains a serial
number or manual target to reapply.

## Temperature registry

The sensor registry selects generation-specific allowlists for Mac12 through
Mac17 plus validated cross-platform keys. It never enumerates AppleSMC keys.
Invalid, malformed, unsupported, or out-of-range samples are discarded.
Derived CPU/GPU Average and Hotspot values reference the exact source-key
sample. The app stores only the selected stable metric ID; Hotspot remains the
default and display fallback.

## Read-only probe

`fancontrold probe` reads only known candidates:

```text
F%dAc F%dTg F%dMn F%dMx F%dMd F%dmd Ftst
```

It does not enumerate AppleSMC keys. The report is designed to exclude unique
device identifiers.

## Development Unix socket

`make run-daemon` starts a development-only server at:

```text
/var/run/mfancontrol-<uid>.sock
```

The socket is owned by the allowed UID with mode `0600`. Each accepted client
is checked with `getpeereid`, and frames use the same bounded codec and request
processor as XPC.

The packaged app uses privileged XPC, not this socket.

## App state

- `FanStore` owns connection, fan/temperature snapshots, validation and lease
  presentation, primary-temperature preference, current UI preset, and
  heartbeat tasks.
- `PresetStore` persists Quiet, Balanced, and Cool percentages.
- `HelperStore` owns installation and XPC availability state.

An active preset is display state only. Connection failure resets it to Auto.
The helper also begins idle under macOS control.

## Extension rules

When adding functionality:

- add typed domain data before extending transport data;
- keep raw AppleSMC behavior inside `SMCBridge` and `FanCore`;
- extend `FanCommand` only for a bounded user intent;
- never add a generic key name or raw byte field to IPC;
- route every new manual-control path through the same safety processor;
- keep read-only discovery separate from write validation;
- add tests at the narrowest owning module;
- update [SAFETY.md](SAFETY.md) when recovery behavior changes.
