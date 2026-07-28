# Open-Source Foundation Design

## Summary

MFanControl will receive a production-ready visual identity and a
contributor-ready documentation baseline. The project remains source-only,
experimental, safety-first, and focused on Apple Silicon Macs with
`Mac15,7 / M3 Pro` as the initial hardware validation target.

The work does not change the fan-control protocol, introduce new SMC writes,
publish binary releases, or claim hardware validation that has not occurred.

## App icon

The approved icon is a front-facing physical fan module:

- a softly rounded brushed-aluminium housing;
- a deep navy fan cavity;
- a symmetric dark-blue rotor;
- a clean integrated RPM gauge;
- a restrained cyan-to-amber status arc;
- no words, numbers, emoji, logos, or decorative symbols.

The generated source image will be adapted non-destructively for macOS:

1. Preserve the approved housing, rotor, materials, and gauge.
2. Remove only the external backdrop so the icon has transparent corners.
3. Produce the standard macOS icon sizes from one high-resolution source.
4. Package the sizes as `Resources/AppIcon.icns`.
5. Set the bundle icon in `Resources/Info.plist`.
6. Copy the icon into the built app in `script/package_app.sh`.

The source image and generated iconset remain in `Resources/AppIcon/` so future
contributors can regenerate the `.icns` deterministically.

## Documentation set

### README

`README.md` will be the English-language project entry point and include:

- project identity, badges, and the approved icon;
- experimental-status and hardware-risk warnings;
- current capabilities and explicit non-goals;
- supported and experimental hardware;
- requirements;
- source build and local helper-package workflow;
- usage and return-to-Auto instructions;
- read-only probing and hardware-validation gates;
- architecture and repository structure;
- troubleshooting;
- testing;
- contribution, security, support, license, and attribution links.

Statements must describe the current implementation and packaging scripts.
Design-only features must not be presented as complete.

### Contributor documents

- `CONTRIBUTING.md`: development setup, workflow, tests, code style, pull
  requests, safety invariants, SMC boundary rules, hardware evidence, privacy,
  and provenance requirements.
- `SECURITY.md`: supported-version policy, private vulnerability reporting
  through GitHub Security Advisories, response expectations, sensitive
  hardware-control disclosures, and out-of-scope support requests.
- `CODE_OF_CONDUCT.md`: Contributor Covenant-based community expectations and
  enforcement process.
- `SUPPORT.md`: supported questions, diagnostic information, privacy-safe
  reporting, and boundaries between support and security reports.
- `CHANGELOG.md`: Keep a Changelog structure with the current development state
  under `Unreleased`.
- `docs/ARCHITECTURE.md`: module responsibilities, app/helper boundaries,
  protocol flow, packaging path, and extension rules.
- `docs/SAFETY.md`: safety invariants, failure recovery, hardware-validation
  gate, prohibited shortcuts, and contributor checklist.

### GitHub collaboration files

- `.github/ISSUE_TEMPLATE/bug_report.yml`
- `.github/ISSUE_TEMPLATE/feature_request.yml`
- `.github/ISSUE_TEMPLATE/config.yml`
- `.github/PULL_REQUEST_TEMPLATE.md`
- `.github/CODEOWNERS`

Templates must request actionable environment data without collecting serial
numbers, UUIDs, account names, or other direct identifiers. Blank issues will
remain available for discussions that do not fit the structured forms.

## Security and safety posture

The documentation must preserve these invariants:

- no arbitrary SMC key or raw-write API through UI or IPC;
- RPM targets remain nonzero and bounded by the current reported range;
- Auto is restored on disconnect, heartbeat timeout, sleep, thermal emergency,
  helper failure, signal, and orderly shutdown;
- active manual state is not restored automatically after launch or wake;
- read-only probing precedes all model-specific write validation;
- unsupported machines are not guessed into support;
- hardware control is not described as validated without a complete on-device
  gate for the current macOS build;
- potentially dangerous unpublished write sequences are reported privately.

## Verification

The completed change will be checked with:

- icon source dimensions and alpha-channel inspection;
- validation of every required icon size;
- `iconutil` compilation of `AppIcon.icns`;
- `plutil` validation of the app property list;
- shell syntax checks for modified packaging scripts;
- local Markdown-link validation;
- repository checks for placeholders and stale architecture claims;
- the existing Swift test suite;
- app packaging and bundle-icon verification when the local toolchain permits.

Software verification does not constitute hardware validation.

## Non-goals

- No official binary releases, notarization, DMG, or App Store packaging.
- No new branch.
- No fan-control behavior changes.
- No temperature curves or additional presets.
- No contributor license agreement, formal multi-maintainer governance,
  sponsorship configuration, or release automation at the current project
  stage.
