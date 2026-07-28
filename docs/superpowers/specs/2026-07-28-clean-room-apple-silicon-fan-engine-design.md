# Clean-room Apple Silicon Fan Engine Design

## Status

Approved for implementation on 2026-07-28.

## Intent

MFanControl will reproduce the useful active-session behavior of
[smcFanControl](https://github.com/wolffcatskyy/smcFanControl) with an
independently written Swift implementation for Apple Silicon.

smcFanControl is a behavioral reference only. Its GPL-2.0 source, implementation
structure, names, and translated code must not enter this MIT-licensed project.
Apple Silicon key research may use the MIT-licensed
[macos-smc-fan](https://github.com/agoodkind/macos-smc-fan), with attribution in
`THIRD_PARTY_NOTICES.md`.

## Product behavior

- Keep the compact preset-first menu and existing Auto, Quiet, Balanced, Cool,
  Max, and manual controls.
- Manual control is temporary and exists only during one healthy owner session.
- Other signed app instances may read telemetry but cannot validate or write.
- Wake, disconnect, heartbeat expiry, sleep, thermal emergency, shutdown, or
  repeated power-source drift returns every fan to Auto and restores its
  captured hardware minimum.
- Max uses each fan's exact reported maximum.
- Hardware remains Experimental until the complete non-CI hardware gate passes.

## Protocol v4

The Objective-C XPC method continues to accept only bounded encoded `Data`.
The domain protocol adds:

- `FanCommand.validateHardware`;
- `HardwareProfile.writeEligibility` and `capabilityFingerprint`;
- `HardwareValidationReport` on `FanResponse`;
- `FanSnapshot.effectiveMinimumRPM`, while `minimumRPM` remains the captured
  baseline used by preset calculations;
- `[TemperatureReading]` with stable IDs, labels, groups, roles, Celsius values,
  sample counts, and allowlisted source keys;
- bounded errors for required validation, controller ownership, capability
  mismatch, and baseline restoration failure.

An installed protocol-v3 helper is incompatible and uses the existing helper
reinstall flow.

## Capability and approval

Read-only discovery profiles each fan's `Ac`, `Tg`, `Mn`, `Mx`, mode-key
casing, SMC data types, reported range, and `Ftst` availability. Inconsistent
keys, types, indices, or ranges make the profile ineligible for writes.

A deterministic SHA-256 fingerprint covers the model, fan count, key names,
types, ranges, and selected control strategy. Approval is keyed by the exact
model, macOS build, and fingerprint and is stored at:

`/Library/Application Support/MFanControl/hardware-approvals.json`

The helper writes it atomically as root-owned mode `0600`. It contains no
serial number or other direct identifier.

## Stateful transition engine

`FanController` remains the public actor and `FanControlling` remains the
policy boundary. An internal `AppleSiliconFanEngine` owns SMC transitions.

Before the first floor write, the engine captures all affected baselines and
atomically creates:

`/Library/Application Support/MFanControl/recovery-state.json`

Manual order:

1. validate target against captured baseline minimum and reported maximum;
2. write temporary `F%dMn = target`;
3. acquire manual mode directly, with bounded `Ftst` fallback when required;
4. write `F%dTg = target`;
5. verify effective floor, non-system manual mode, target, and actual RPM within
   15 percent.

Automatic restoration order:

1. clear manual mode;
2. restore captured `F%dMn`;
3. accept only automatic or system mode readback;
4. release `Ftst` only when this engine acquired it;
5. delete the journal only after complete readback verification.

Any partial failure restores every affected fan transactionally. A failed
baseline restoration revokes approval and blocks writes for the runtime.
Startup recovery restores only a matching fingerprint; mismatch blocks writes
instead of guessing.

## Validation and ownership

Each accepted XPC connection receives an internal UUID. The first healthy
`hello` obtains the write lease. Owner-only commands are manual, preset,
automatic, all-automatic, validation, and shutdown. Observers receive
`controllerBusy` for those commands.

Validation requires explicit UI confirmation. It tests fans sequentially at
`min + 500 RPM`, capped at the reported maximum, restores all fans fully, and
writes approval only after every fan passes.

During a healthy manual session, a power-source change permits one bounded
reapply. Repeated drift or failed reapply restores Auto. Wake never reapplies.

## Temperature registry

The registry uses generation-specific allowlists for Mac12 through Mac17 plus
validated cross-platform sensors. It never enumerates arbitrary SMC keys.
Only supported temperature types and values within `-40...150°C` are accepted.

CPU Average and CPU Hotspot are derived from the same CPU-core sample. GPU
Average and GPU Hotspot are derived equivalently when available. Battery
remains separate when a validated key is present.

The selected primary metric defaults to CPU Hotspot. Menu fallback order is:

1. selected metric;
2. CPU Hotspot;
3. CPU Average;
4. first valid CPU reading.

Thermal shutdown continues to use `ProcessInfo.thermalState`, never the display
metric.

## Non-goals

- Intel/OCLP support or boot daemons;
- persistent manual targets or wake reapplication;
- generic SMC IPC or unrestricted key scanning;
- automatic promotion to Verified;
- copying, translating, or structurally mirroring GPL implementation.
