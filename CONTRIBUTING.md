# Contributing to MFanControl

Thank you for helping improve MFanControl. This project controls physical
hardware, so safety, evidence, and narrowly scoped changes matter more than
feature speed.

## Before you start

Please read:

- [README.md](README.md) for the current project status and build flow;
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for module boundaries;
- [docs/SAFETY.md](docs/SAFETY.md) for non-negotiable safety invariants;
- [SECURITY.md](SECURITY.md) for private vulnerability reporting;
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for community expectations.

For a large change, open a feature request before implementation. Explain the
problem, hardware scope, safety impact, and the smallest useful outcome.

## Development setup

Requirements:

- macOS 15 or newer;
- Xcode beta at `/Applications/Xcode-beta.app`;
- a Swift 6.2-compatible toolchain;
- an Apple Development identity only when validating privileged XPC locally.

Run the default verification:

```sh
make test
make release
```

Build and inspect the app bundle:

```sh
make verify-app
```

Do not install or run the privileged helper merely to validate documentation,
protocol models, or pure policy code.

## Change workflow

1. Start from the latest source.
2. Keep each change focused on one observable outcome.
3. Add or update tests before changing control behavior.
4. Run the narrowest relevant test while iterating.
5. Run `make test` before requesting review.
6. Update documentation when a command, contract, limitation, or safety
   behavior changes.
7. State clearly which checks were software-only and which ran on hardware.

Do not include unrelated formatting, renames, or refactors in a safety-sensitive
pull request.

## Code style

- Follow the formatting already used by the Swift sources.
- Use two-space indentation in Swift and shell files.
- Prefer small types with one responsibility.
- Keep public interfaces typed and narrow.
- Use Swift Testing (`@Suite`, `@Test`, and `#expect`) in existing test targets.
- Keep shell scripts compatible with the system Bash used by macOS.
- Treat compiler warnings and shell syntax warnings as failures.

## Tests

Changes must include focused regression coverage where applicable:

- `SMCBridgeTests` for ABI and codec behavior;
- `FanProtocolTests` for message boundaries and serialization;
- `HelperProtocolTests` and `HelperServiceCoreTests` for XPC contracts;
- `HelperManagementTests` for app-side helper lifecycle;
- `FanCoreTests` for discovery, RPM policy, presets, control, and safety;
- `FanDaemonCoreTests` for authorization and request processing;
- `MFanControlAppTests` for pure presentation behavior.

Run all non-hardware tests with:

```sh
make test
```

Hardware tests are opt-in:

```sh
MFAN_HARDWARE_TESTS=1 make test
```

Never add an automatic hardware test that performs SMC writes. Write validation
requires a documented manual procedure and an explicit operator.

## Safety requirements

Every control-related change must preserve these rules:

- no arbitrary SMC key or raw-byte command reaches the app or IPC boundary;
- RPM targets are nonzero and bounded by current reported limits;
- manual mode and target speed are verified;
- a partial preset failure restores every fan to Auto;
- disconnect, heartbeat timeout, sleep, thermal emergency, termination signals,
  and orderly shutdown restore Auto;
- wake, relaunch, and reconnect never restore manual mode automatically;
- `Ftst` is reset only when the current process acquired it;
- unknown hardware is never promoted to supported by guesswork.

If a proposed change cannot satisfy these requirements, open a design
discussion instead of weakening a guard.

## Hardware evidence

Use `make probe` before proposing model-specific support.

A hardware fixture may contain:

- model identifier;
- processor name;
- fan count;
- known fan-key types and sanitized values;
- selected strategy.

It must not contain serial numbers, hardware UUIDs, account names, hostnames,
network identifiers, or unrelated SMC data.

New model support remains experimental until the complete gate in
[docs/SAFETY.md](docs/SAFETY.md) passes on the stated macOS build.

## SMC research and provenance

MFanControl intentionally exposes only the AppleSMC behavior required by known
fan and temperature keys.

When adding protocol facts:

- cite public specifications, public research, or project-owned probe evidence;
- record whether behavior was observed, inferred, or documented;
- do not copy upstream source, comments, type layout, or application structure;
- retain required third-party notices for copied or substantially derived work;
- do not enumerate unknown keys on user machines.

Update [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) when attribution changes.

## Pull requests

A pull request should include:

- a concise problem and outcome;
- affected modules and hardware;
- software test commands and results;
- hardware test status, explicitly stating when it was not run;
- safety and recovery impact;
- screenshots for visible UI changes;
- provenance notes for new SMC behavior;
- documentation changes.

By contributing, you agree that your contribution is licensed under the
project's [MIT License](LICENSE).
