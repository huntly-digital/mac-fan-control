## Summary

Describe the problem and the observable outcome.

## Scope

- Affected modules:
- Affected hardware:
- Out-of-scope work:

## Verification

- [ ] Focused tests were added or updated where applicable.
- [ ] `make test` passes.
- [ ] `make release` passes.
- [ ] `make verify-app` passes when packaging is affected.
- [ ] Documentation was updated when behavior or commands changed.

Commands and results:

```text
Paste concise software verification evidence here.
```

## Hardware validation

- [ ] Hardware behavior is not affected.
- [ ] Hardware behavior is affected and the tests below were run.
- [ ] Hardware behavior is affected but hardware validation was not run.

Model, macOS build, procedure, and result:

```text
State "Not run" when applicable. Never imply software tests are hardware validation.
```

## Safety

- [ ] No arbitrary SMC key or raw-byte field reaches UI or IPC.
- [ ] RPM targets remain nonzero and bounded by current reported limits.
- [ ] Manual mode and target response remain verified.
- [ ] Partial preset failure returns every fan to Auto.
- [ ] Disconnect, timeout, sleep, thermal, signal, and shutdown recovery remain intact.
- [ ] Wake and reconnect do not restore manual mode.
- [ ] `Ftst` ownership remains explicit.

## Privacy and provenance

- [ ] Logs and fixtures contain no serial numbers, UUIDs, account names, credentials, or signing secrets.
- [ ] New SMC facts include public or project-owned provenance.
- [ ] Required third-party attribution is preserved.

## Visual changes

Attach before/after screenshots for UI or icon changes.
