# Security Policy

MFanControl combines a menu-bar app, a privileged helper, XPC, launchd, package
installation, and low-level hardware control. Please report security issues
privately so the maintainer can assess both software and hardware impact before
details become public.

## Supported versions

MFanControl has no stable binary release.

| Version | Security support |
| --- | --- |
| Latest source on `main` | Supported on a best-effort basis |
| Older commits, forks, and unofficial binaries | Not supported |

The project does not distribute official binaries. A report involving a
third-party build should include the exact commit and describe any downstream
changes.

## Report a vulnerability

Use GitHub's private vulnerability reporting:

<https://github.com/huntly-digital/mac-fan-control/security/advisories/new>

Do not open a public issue for:

- privileged XPC authentication or signing bypasses;
- arbitrary SMC key or raw-write access;
- unsafe failure to restore Auto;
- helper or package replacement;
- permission, ownership, or launchd persistence flaws;
- malformed payloads that cross the privilege boundary;
- unpublished SMC write sequences that may damage hardware;
- sensitive data exposure in probes or logs.

Include:

- the affected commit;
- macOS version and hardware model identifier;
- preconditions and impact;
- minimal reproduction steps;
- sanitized logs or proof of concept;
- whether manual fan control was active;
- whether all fans returned to Auto.

Never include serial numbers, hardware UUIDs, account names, credentials,
signing private keys, or unrelated device data.

## Response process

The maintainer aims to:

1. acknowledge a complete report within seven days;
2. provide an initial assessment within fourteen days;
3. coordinate a fix and disclosure window appropriate to the risk;
4. credit the reporter when requested and safe.

These are best-effort targets for a volunteer project, not a service-level
agreement.

Please allow a reasonable remediation period before public disclosure. If the
issue creates immediate hardware risk, stop testing, return all fans to Auto,
and say so prominently in the report.

## Out of scope

Use [SUPPORT.md](SUPPORT.md) and GitHub Issues for:

- build and signing questions;
- unsupported hardware;
- ordinary crashes without a security boundary impact;
- feature requests;
- macOS or firmware behavior outside MFanControl's control.

Social engineering, denial of service against public project infrastructure,
and testing on devices you do not own or have permission to use are out of
scope.
