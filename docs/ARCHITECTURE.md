# MFanControl Architecture

This document describes the current implementation. It is not a roadmap.

## Design goals

MFanControl separates display, privilege, policy, and low-level hardware access
so that no UI or transport can issue an arbitrary SMC operation.

The main boundaries are:

1. The app owns presentation and user intent.
2. Shared protocol types define the complete command surface.
3. The privileged helper owns control and recovery.
4. `FanCore` owns policy and model-aware fan behavior.
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
  RequestProcessor
  SafetyStateMachine
            |
            v
  FanController
            |
            v
  SMCBridge -> AppleSMC user client
```

The app polls status once per second and sends a heartbeat every two seconds
while connected. The helper safety timer evaluates heartbeat expiry every
second.

## Package targets

| Target | Responsibility |
| --- | --- |
| `SMCBridge` | AppleSMC user-client connection, key metadata, typed RPM/temperature codecs, package-internal writes |
| `FanProtocol` | `FanRequest`, `FanResponse`, hardware/fan/temperature models, errors, bounded JSONL codec |
| `HelperProtocol` | Objective-C-compatible XPC interface and service identifiers |
| `HelperServiceCore` | Privileged XPC endpoint, client signing requirement, lifecycle and safety hooks |
| `HelperManagement` | App-side helper installation state, ping client, and persistent fan-request XPC client |
| `FanCore` | Hardware discovery, RPM/preset policy, fan control, probe, and safety state machine |
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

`FanRequest` contains only a request identifier, command, optional fan index,
optional RPM, and optional preset percentage. It cannot carry an SMC key,
data type, raw bytes, file path, or shell command.

`HelperXPCProtocol.performFanRequest` accepts `Data`, but both sides encode and
decode it with `JSONLineCodec`. The codec rejects payloads larger than 4 KiB.

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
2. an XPC ping returns the expected protocol version.

Reinstalling the local package replaces the helper and reloads the same launchd
label.

## Request processing and recovery

`RequestProcessor` is the only component that translates protocol commands into
`FanControlling` calls.

- Status commands return hardware, fan, and optional temperature snapshots.
- Manual and preset commands are rejected during serious or critical thermal
  pressure.
- Presets calculate one bounded target per current fan.
- A partial preset failure calls `setAllAutomatic()`.
- Disconnect, heartbeat timeout, sleep, thermal emergency, and shutdown are
  routed through the shared `SafetyStateMachine`.

The XPC service marks a fan session after `hello`. Connection invalidation then
invokes the same disconnect recovery path.

## Hardware discovery and SMC access

`HardwareProfiler` reads only the fan count and known mode-key candidates. It
selects:

- `F%dMd` when `F0Md` exists;
- `F%dmd` when `F0md` exists;
- unsupported when neither exists.

`Ftst` presence selects the bounded direct-then-fallback strategy. A discovered
mode key is still marked experimental; discovery alone never verifies a model.

`FanController` exposes typed operations:

- discover hardware;
- read fan and temperature snapshots;
- produce a read-only probe;
- set one fan to a bounded manual target;
- restore one or all fans to Auto.

Raw key writes remain internal to the controller and transport package.

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

- `FanStore` owns connection, fan/temperature snapshots, current UI preset, and
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
