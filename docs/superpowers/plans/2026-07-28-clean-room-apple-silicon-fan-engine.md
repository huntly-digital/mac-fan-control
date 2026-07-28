# Clean-room Apple Silicon Fan Engine Implementation Plan

## Goal

Replace direct mode/target writes with a capability-gated, recoverable,
single-owner Apple Silicon fan engine while preserving the current presets,
manual UX, MIT license, and source-only distribution.

## Work items

1. Update architecture, safety, design, implementation, and third-party
   documentation before hardware changes.
2. Introduce protocol v4 domain types and bounded errors.
3. Add deterministic capability profiling and exact
   model/build/fingerprint approvals.
4. Add atomic root-owned approval and recovery stores.
5. Implement floor → mode → target transactions and verified full restoration.
6. Recover a matching stale journal before accepting control requests.
7. Add per-XPC-connection owner leases, validation gating, and observer
   telemetry.
8. Add one bounded power-drift reapply and Auto fallback.
9. Add the allowlisted Mac12–Mac17 temperature registry and derived metrics.
10. Add primary-temperature preference, validation UI, observer UI, and sensor
    diagnostics.
11. Verify focused tests, `make test`, release build, signatures, and
    `build_and_run.sh --verify`.

## TDD checkpoints

- Protocol tests prove v4 encoding and the baseline/effective-floor split.
- Capability tests prove missing/wrong keys and ranges are rejected and
  fingerprints are stable.
- Persistence tests prove bounded, atomic approval and recovery round trips.
- Engine tests prove write order, direct/Ftst paths, rollback at each failure,
  exact Max targets, and baseline restoration.
- Helper tests prove owner/observer behavior, validation gating, disconnect,
  heartbeat, power drift, and safety recovery.
- Sensor tests prove generation selection, invalid-sample rejection,
  aggregation, stable IDs, and fallback.
- App tests prove validation, busy/reinstall presentation, and temperature
  preference behavior.

## Hardware gate

Hardware writes are never run in CI. Explicit on-device validation must cover a
read-only probe, every fan, twenty Auto → Manual → Auto cycles, every preset,
AC/battery drift, disconnect, helper termination, sleep/wake, thermal recovery,
and `kill -9` reclaim including restoration of every `F%dMn`.

Unit tests and automatic discovery never promote hardware to Verified.
