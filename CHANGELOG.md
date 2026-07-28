# Changelog

All notable changes to MFanControl will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
The project does not yet publish stable releases or official binaries.

## [Unreleased]

### Added

- Source-only SwiftPM project for macOS 15 and Apple Silicon.
- SwiftUI menu-bar app with compact fan telemetry and controls.
- Auto, Quiet, Balanced, and Cool fixed-RPM presets.
- Per-fan manual controls with bounded target validation.
- CPU maximum temperature and optional GPU and battery telemetry for validated
  model keys.
- Typed XPC boundary for the privileged helper.
- Local component-package installation through the standard macOS Installer.
- Read-only known-key hardware probe and anonymized `Mac15,7` fixture.
- Safety state machine for heartbeat, disconnect, sleep, thermal, and shutdown
  recovery.
- Unit coverage across SMC codecs, protocol, helper lifecycle, fan policy,
  controller, daemon processing, and presentation logic.
- macOS app icon and deterministic asset generation.
- Contributor, security, support, conduct, architecture, and safety
  documentation.

### Security

- Requests are bounded and decoded through shared typed models.
- Privileged XPC clients are constrained by bundle identifier, Apple-trusted
  signature, and helper Team ID.
- The app and IPC expose no arbitrary SMC key or raw-write command.

[Unreleased]: https://github.com/huntly-digital/mac-fan-control/commits/main
