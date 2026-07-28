# MFanControl Support

MFanControl is experimental, source-only software maintained on a best-effort
basis. There is no paid support, compatibility guarantee, or official binary
distribution.

## Before opening an issue

1. Read the current [README.md](README.md).
2. Confirm that you built the latest source.
3. Run `make test` and record the result.
4. Run `make probe` before any model-specific control test.
5. Return all fans to Auto before collecting diagnostics.
6. Search existing
   [GitHub Issues](https://github.com/huntly-digital/mac-fan-control/issues).

## Supported questions

GitHub Issues are appropriate for:

- source builds and Swift toolchain failures;
- local Apple Development signing;
- helper package installation and XPC connection state;
- menu-bar UI problems;
- read-only probe results;
- reproducible compatibility problems;
- focused feature requests.

Use the structured issue forms whenever possible.

## What to include

- exact commit;
- macOS version;
- hardware model identifier such as `Mac15,7`;
- processor family;
- affected area;
- reproduction steps;
- expected and actual behavior;
- sanitized logs;
- whether the helper was installed;
- whether every fan returned to Auto.

Do not include serial numbers, hardware UUIDs, account names, hostnames, email
addresses, signing private keys, or unrelated SMC values.

## Immediate safety issue

If control behaves unexpectedly:

1. Select **Auto** in MFanControl.
2. Quit the app normally.
3. Stop any development daemon with `Ctrl+C`.
4. Do not attempt unknown SMC writes.
5. If Auto cannot be confirmed, stop testing and report the case privately
   under [SECURITY.md](SECURITY.md).

## Not supported

- unofficial binary builds;
- Intel Macs;
- arbitrary SMC experiments;
- temperature-curve requests presented as bug reports;
- hardware repair or thermal-engineering advice;
- modified forks without a reproducible comparison to this repository.

For security-sensitive reports, do not use a public issue. Follow
[SECURITY.md](SECURITY.md).
